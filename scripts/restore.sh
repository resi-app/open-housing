#!/bin/bash
# OpenResiApp — Database restore script
# Usage:
#   ./scripts/restore.sh <backup-file.sql.gz>       Restore from local backup file
#   ./scripts/restore.sh list                        List remote archives (borg or restic)
#   ./scripts/restore.sh borg <archive|latest>       Restore from remote borg archive
#   ./scripts/restore.sh restic <snapshot-id|latest> Restore from remote restic snapshot

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
BACKUP_DIR="${BACKUP_DIR:-/backups/resiapp}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

die() {
  log "ERROR: $*"
  exit 1
}

# --- Load .env if present ---
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# --- Shared helpers ---
get_db_container() {
  DB_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q db 2>/dev/null || echo "")"
  if [ -z "$DB_CONTAINER" ]; then
    die "Database container not found. Is docker compose running?"
  fi
}

restore_sql_file() {
  local SQL_FILE="$1"
  get_db_container

  echo ""
  echo "WARNING: This will OVERWRITE the current database with:"
  echo "  $SQL_FILE"
  echo ""
  read -p "Type 'yes' to continue: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  log "Restoring database from: $SQL_FILE"

  if [[ "$SQL_FILE" == *.gz ]]; then
    gunzip -c "$SQL_FILE" | docker exec -i "$DB_CONTAINER" psql -U postgres -d resiapp --quiet
  else
    docker exec -i "$DB_CONTAINER" psql -U postgres -d resiapp --quiet < "$SQL_FILE"
  fi

  log "Database restore complete."
  log "Restart the app to pick up changes: docker compose -f $COMPOSE_FILE restart app"
}

restore_uploads_from_archive() {
  local UPLOADS_FILE="$1"
  if [ -n "$UPLOADS_FILE" ]; then
    echo ""
    read -p "Also restore uploads? (y/N): " RESTORE_UPLOADS
    if [ "$RESTORE_UPLOADS" = "y" ]; then
      log "Restoring uploads..."
      docker compose -f "$COMPOSE_FILE" cp "$UPLOADS_FILE" app:/tmp/uploads_restore.tar.gz
      docker compose -f "$COMPOSE_FILE" exec app sh -c \
        "cd /app && tar xzf /tmp/uploads_restore.tar.gz && rm -f /tmp/uploads_restore.tar.gz"
      log "Uploads restored"
    fi
  fi
}

# --- Borg helpers ---
setup_borg_env() {
  BORG_REPO="${BORG_REPO:-}"
  BORG_PASSPHRASE="${BORG_PASSPHRASE:-}"
  BORG_SSH_KEY="${BORG_SSH_KEY:-$HOME/.ssh/id_ed25519_borg}"

  if [ -z "$BORG_REPO" ]; then
    die "BORG_REPO not set. Configure it in .env"
  fi
  if [ -z "$BORG_PASSPHRASE" ]; then
    die "BORG_PASSPHRASE not set. Configure it in .env"
  fi

  export BORG_REPO
  export BORG_PASSPHRASE
  export BORG_RSH="ssh -i $BORG_SSH_KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"
}

# --- Restic helpers ---
setup_restic_env() {
  RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
  RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"

  if [ -z "$RESTIC_REPOSITORY" ]; then
    die "RESTIC_REPOSITORY not set. Configure it in .env"
  fi
  if [ -z "$RESTIC_PASSWORD" ]; then
    die "RESTIC_PASSWORD not set. Configure it in .env"
  fi

  export RESTIC_REPOSITORY
  export RESTIC_PASSWORD

  # Export cloud provider credentials if set
  [ -n "${AWS_ACCESS_KEY_ID:-}" ] && export AWS_ACCESS_KEY_ID
  [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && export AWS_SECRET_ACCESS_KEY
  [ -n "${AZURE_ACCOUNT_NAME:-}" ] && export AZURE_ACCOUNT_NAME
  [ -n "${AZURE_ACCOUNT_KEY:-}" ] && export AZURE_ACCOUNT_KEY
}

# --- Detect remote backend ---
detect_backend() {
  BORG_REPO="${BORG_REPO:-}"
  RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"

  if [ -n "$BORG_REPO" ]; then
    echo "borg"
  elif [ -n "$RESTIC_REPOSITORY" ]; then
    echo "restic"
  else
    echo "none"
  fi
}

# --- Subcommand: list ---
cmd_list() {
  local BACKEND
  BACKEND=$(detect_backend)

  case "$BACKEND" in
    borg)
      setup_borg_env
      log "Listing remote borg archives..."
      echo ""
      borg list
      ;;
    restic)
      setup_restic_env
      log "Listing remote restic snapshots..."
      echo ""
      restic snapshots --tag resiapp
      ;;
    *)
      die "No remote backup configured (set BORG_REPO or RESTIC_REPOSITORY in .env)"
      ;;
  esac
}

# --- Subcommand: borg <archive> ---
cmd_borg() {
  local ARCHIVE="${1:-}"
  if [ -z "$ARCHIVE" ]; then
    die "Usage: $0 borg <archive-name|latest>"
  fi

  setup_borg_env

  # Resolve "latest" to the most recent archive name
  if [ "$ARCHIVE" = "latest" ]; then
    log "Finding latest archive..."
    ARCHIVE=$(borg list --short --sort-by timestamp --last 1)
    if [ -z "$ARCHIVE" ]; then
      die "No archives found in borg repo"
    fi
    log "Latest archive: $ARCHIVE"
  fi

  # Extract to temp directory
  EXTRACT_DIR=$(mktemp -d "/tmp/borg-restore-XXXXXX")
  log "Extracting archive '$ARCHIVE' to $EXTRACT_DIR ..."

  cd "$EXTRACT_DIR"
  borg extract "::${ARCHIVE}"

  # Find the SQL dump
  SQL_FILE=$(find "$EXTRACT_DIR" -name "db_*.sql.gz" -type f | head -1)
  if [ -z "$SQL_FILE" ]; then
    log "Available files in archive:"
    find "$EXTRACT_DIR" -type f
    die "No database dump (db_*.sql.gz) found in archive"
  fi
  log "Found database dump: $SQL_FILE"

  # Check for uploads
  UPLOADS_FILE=$(find "$EXTRACT_DIR" -name "uploads_*.tar.gz" -type f | head -1)
  [ -n "$UPLOADS_FILE" ] && log "Found uploads archive: $UPLOADS_FILE"

  # Restore
  restore_sql_file "$SQL_FILE"
  restore_uploads_from_archive "${UPLOADS_FILE:-}"

  # Cleanup
  rm -rf "$EXTRACT_DIR"
  log "Temporary files cleaned up"
}

# --- Subcommand: restic <snapshot> ---
cmd_restic() {
  local SNAPSHOT="${1:-}"
  if [ -z "$SNAPSHOT" ]; then
    die "Usage: $0 restic <snapshot-id|latest>"
  fi

  setup_restic_env

  # Extract to temp directory
  EXTRACT_DIR=$(mktemp -d "/tmp/restic-restore-XXXXXX")
  log "Restoring snapshot '$SNAPSHOT' to $EXTRACT_DIR ..."

  restic restore "$SNAPSHOT" --target "$EXTRACT_DIR" --tag resiapp

  # Find the SQL dump
  SQL_FILE=$(find "$EXTRACT_DIR" -name "db_*.sql.gz" -type f | head -1)
  if [ -z "$SQL_FILE" ]; then
    log "Available files in snapshot:"
    find "$EXTRACT_DIR" -type f
    die "No database dump (db_*.sql.gz) found in snapshot"
  fi
  log "Found database dump: $SQL_FILE"

  # Check for uploads
  UPLOADS_FILE=$(find "$EXTRACT_DIR" -name "uploads_*.tar.gz" -type f | head -1)
  [ -n "$UPLOADS_FILE" ] && log "Found uploads archive: $UPLOADS_FILE"

  # Restore
  restore_sql_file "$SQL_FILE"
  restore_uploads_from_archive "${UPLOADS_FILE:-}"

  # Cleanup
  rm -rf "$EXTRACT_DIR"
  log "Temporary files cleaned up"
}

# --- Main ---
COMMAND="${1:-}"

case "$COMMAND" in
  list)
    cmd_list
    ;;
  borg)
    cmd_borg "${2:-}"
    ;;
  restic)
    cmd_restic "${2:-}"
    ;;
  "")
    die "Usage: $0 <backup-file.sql.gz> | list | borg <archive|latest> | restic <snapshot-id|latest>"
    ;;
  *)
    # Default: treat as local file restore (backward compatible)
    BACKUP_FILE="$COMMAND"
    if [ ! -f "$BACKUP_FILE" ]; then
      die "Backup file not found: $BACKUP_FILE"
    fi
    restore_sql_file "$BACKUP_FILE"
    ;;
esac
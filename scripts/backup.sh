#!/bin/bash
# OpenResiApp — Database & uploads backup script
# Usage: ./scripts/backup.sh
# Recommended: run daily via cron
#   0 3 * * * /path/to/open-resiapp/scripts/backup.sh >> /var/log/resiapp-backup.log 2>&1

set -euo pipefail

# --- Configuration ---
BACKUP_DIR="${BACKUP_DIR:-/backups/resiapp}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
DB_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q db 2>/dev/null || echo "")"
KEEP_DAILY=7
KEEP_WEEKLY=4
DATE=$(date +%F)
TIMESTAMP=$(date +%F_%H%M%S)

# --- Helpers ---
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

die() {
  log "ERROR: $*"
  exit 1
}

# --- Preflight ---
if [ -z "$DB_CONTAINER" ]; then
  die "Database container not found. Is docker compose running?"
fi

mkdir -p "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly"

# --- Database backup ---
log "Starting database backup..."
DUMP_FILE="$BACKUP_DIR/daily/db_${TIMESTAMP}.sql.gz"

docker exec "$DB_CONTAINER" pg_dump -U postgres --no-owner --clean resiapp \
  | gzip > "$DUMP_FILE"

DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
log "Database backup complete: $DUMP_FILE ($DUMP_SIZE)"

# --- Uploads backup ---
log "Starting uploads backup..."
UPLOADS_FILE="$BACKUP_DIR/daily/uploads_${TIMESTAMP}.tar.gz"

docker compose -f "$COMPOSE_FILE" cp app:/app/uploads - \
  | gzip > "$UPLOADS_FILE" 2>/dev/null || log "WARN: No uploads to backup or container not running"

log "Uploads backup complete: $UPLOADS_FILE"

# --- Weekly backup (keep one per Sunday) ---
if [ "$(date +%u)" -eq 7 ]; then
  log "Sunday — creating weekly backup copy..."
  cp "$DUMP_FILE" "$BACKUP_DIR/weekly/db_${TIMESTAMP}.sql.gz"
  [ -f "$UPLOADS_FILE" ] && cp "$UPLOADS_FILE" "$BACKUP_DIR/weekly/uploads_${TIMESTAMP}.tar.gz"
fi

# --- Cleanup old backups ---
log "Cleaning up old backups..."

# Remove daily backups older than KEEP_DAILY days
find "$BACKUP_DIR/daily" -name "*.gz" -mtime +${KEEP_DAILY} -delete 2>/dev/null || true

# Remove weekly backups older than KEEP_WEEKLY weeks
find "$BACKUP_DIR/weekly" -name "*.gz" -mtime +$((KEEP_WEEKLY * 7)) -delete 2>/dev/null || true

log "Local backup complete. Daily: $(ls "$BACKUP_DIR/daily"/*.gz 2>/dev/null | wc -l | tr -d ' ') files, Weekly: $(ls "$BACKUP_DIR/weekly"/*.gz 2>/dev/null | wc -l | tr -d ' ') files"

# --- Remote backup (optional) ---
# Supports: BorgBackup (BORG_REPO) or Restic (RESTIC_REPOSITORY)
BORG_REPO="${BORG_REPO:-}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"

if [ -n "$BORG_REPO" ] && [ -n "$RESTIC_REPOSITORY" ]; then
  log "ERROR: Both BORG_REPO and RESTIC_REPOSITORY are set. Pick one."
  log "  BORG_REPO → Hetzner Storage Box (backup-hetzner-setup.sh)"
  log "  RESTIC_REPOSITORY → AWS S3 / Azure Blob (backup-aws-setup.sh / backup-azure-setup.sh)"
elif [ -n "$BORG_REPO" ]; then
  # --- BorgBackup (Hetzner Storage Box) ---
  (
    set +e
    log "Starting remote backup via BorgBackup..."

    BORG_PASSPHRASE="${BORG_PASSPHRASE:-}"
    BORG_SSH_KEY="${BORG_SSH_KEY:-$HOME/.ssh/id_ed25519_borg}"

    if [ -z "$BORG_PASSPHRASE" ]; then
      log "ERROR: BORG_PASSPHRASE not set — skipping remote backup"
      exit 0
    fi

    export BORG_REPO
    export BORG_PASSPHRASE
    export BORG_RSH="ssh -i $BORG_SSH_KEY -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30"

    ARCHIVE_NAME="resiapp-${TIMESTAMP}"
    BORG_PATHS=("$DUMP_FILE")
    [ -f "$UPLOADS_FILE" ] && BORG_PATHS+=("$UPLOADS_FILE")

    log "Creating borg archive: $ARCHIVE_NAME"
    if borg create \
      --compression zstd,6 \
      --show-rc \
      "::${ARCHIVE_NAME}" \
      "${BORG_PATHS[@]}"; then
      log "Borg archive created successfully"
    else
      BORG_RC=$?
      if [ $BORG_RC -eq 1 ]; then
        log "WARN: Borg finished with warnings (rc=$BORG_RC)"
      else
        log "ERROR: Borg create failed (rc=$BORG_RC)"
      fi
    fi

    # Attempt prune — no-op in append-only mode, works in dev/test
    log "Attempting borg prune (skipped in append-only mode)..."
    borg prune \
      --keep-daily=30 \
      --keep-weekly=12 \
      --keep-monthly=12 \
      --show-rc 2>/dev/null || true

    log "Remote backup (borg) complete"
  ) || log "WARN: Borg remote backup failed — local backup is safe"

elif [ -n "$RESTIC_REPOSITORY" ]; then
  # --- Restic (AWS S3 / Azure Blob / any restic backend) ---
  (
    set +e
    log "Starting remote backup via restic..."

    RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"

    if [ -z "$RESTIC_PASSWORD" ]; then
      log "ERROR: RESTIC_PASSWORD not set — skipping remote backup"
      exit 0
    fi

    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD

    # Export cloud provider credentials if set
    [ -n "${AWS_ACCESS_KEY_ID:-}" ] && export AWS_ACCESS_KEY_ID
    [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && export AWS_SECRET_ACCESS_KEY
    [ -n "${AZURE_ACCOUNT_NAME:-}" ] && export AZURE_ACCOUNT_NAME
    [ -n "${AZURE_ACCOUNT_KEY:-}" ] && export AZURE_ACCOUNT_KEY

    RESTIC_PATHS=("$DUMP_FILE")
    [ -f "$UPLOADS_FILE" ] && RESTIC_PATHS+=("$UPLOADS_FILE")

    log "Creating restic snapshot..."
    if restic backup \
      --tag resiapp \
      --tag "daily-${DATE}" \
      "${RESTIC_PATHS[@]}"; then
      log "Restic snapshot created successfully"
    else
      log "ERROR: Restic backup failed (rc=$?)"
    fi

    # Attempt forget+prune — fails silently if IAM/immutability blocks deletes
    log "Attempting restic forget (skipped if delete denied by policy)..."
    restic forget \
      --keep-daily 30 \
      --keep-weekly 12 \
      --keep-monthly 12 \
      --prune \
      --tag resiapp 2>/dev/null || true

    log "Remote backup (restic) complete"
  ) || log "WARN: Restic remote backup failed — local backup is safe"

else
  log "No remote backup configured (set BORG_REPO or RESTIC_REPOSITORY in .env)"
fi

log "Backup finished."
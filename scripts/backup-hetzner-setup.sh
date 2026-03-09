#!/bin/bash
# OpenResiApp — One-time BorgBackup remote backup setup
# Initializes borg repo on Hetzner Storage Box and generates SSH key
# Usage: ./scripts/backup-hetzner-setup.sh
#
# Prerequisites:
#   - borgbackup installed (apt install borgbackup)
#   - BORG_REPO, BORG_PASSPHRASE, BORG_SSH_KEY set in .env

set -euo pipefail

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

# --- Validate prerequisites ---
if ! command -v borg &>/dev/null; then
  die "borgbackup not installed. Run: apt install borgbackup"
fi

BORG_VERSION=$(borg --version | awk '{print $2}')
log "Borg version: $BORG_VERSION"

# Warn about version mismatch with Hetzner (they run borg 1.x)
if [[ "$BORG_VERSION" == 2.* ]]; then
  log "WARNING: You have borg 2.x but Hetzner Storage Box runs borg 1.x"
  log "WARNING: Install borg 1.x for compatibility: pip install borgbackup==1.2.*"
  die "Version mismatch — borg 1.x required for Hetzner Storage Box"
fi

BORG_REPO="${BORG_REPO:-}"
BORG_PASSPHRASE="${BORG_PASSPHRASE:-}"
BORG_SSH_KEY="${BORG_SSH_KEY:-$HOME/.ssh/id_ed25519_borg}"

if [ -z "$BORG_REPO" ]; then
  die "BORG_REPO not set. Example: ssh://u123456@u123456.your-storagebox.de:23/./resiapp"
fi

if [ -z "$BORG_PASSPHRASE" ]; then
  die "BORG_PASSPHRASE not set. Generate one: openssl rand -base64 32"
fi

# --- Step 1: Generate SSH key ---
log "=== Step 1: SSH Key ==="
if [ -f "$BORG_SSH_KEY" ]; then
  log "SSH key already exists: $BORG_SSH_KEY"
else
  log "Generating SSH key: $BORG_SSH_KEY"
  ssh-keygen -t ed25519 -f "$BORG_SSH_KEY" -N "" -C "borg-backup-$(hostname)"
  log "SSH key generated"
fi

log ""
log "Public key (add this to Hetzner Storage Box):"
log "---"
cat "${BORG_SSH_KEY}.pub"
log "---"
log ""

# --- Step 2: Test SSH connection ---
log "=== Step 2: Testing SSH connection ==="

# Extract host and port from BORG_REPO (ssh://user@host:port/path)
BORG_HOST=$(echo "$BORG_REPO" | sed -E 's|ssh://([^@]+)@([^:/]+).*|\2|')
BORG_PORT=$(echo "$BORG_REPO" | sed -E 's|ssh://[^:]+:([0-9]+).*|\1|')
BORG_PORT="${BORG_PORT:-23}"

log "Testing SSH to $BORG_HOST:$BORG_PORT ..."
if ssh -i "$BORG_SSH_KEY" -p "$BORG_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
  "$(echo "$BORG_REPO" | sed -E 's|ssh://([^@]+@[^:/]+).*|\1|')" \
  "echo 'SSH connection OK'" 2>/dev/null; then
  log "SSH connection successful"
else
  log "WARNING: SSH connection failed. Make sure you've added the public key to Hetzner:"
  log "  1. Log in to Hetzner Robot panel"
  log "  2. Go to Storage Box → your box → SSH keys"
  log "  3. Add the public key shown above"
  log ""
  read -p "Continue anyway? (y/N): " CONTINUE
  if [ "$CONTINUE" != "y" ]; then
    exit 1
  fi
fi

# --- Step 3: Initialize borg repo ---
log "=== Step 3: Initializing borg repository ==="

export BORG_REPO
export BORG_PASSPHRASE
export BORG_RSH="ssh -i $BORG_SSH_KEY -o StrictHostKeyChecking=accept-new"

if borg info 2>/dev/null; then
  log "Borg repo already initialized at $BORG_REPO"
else
  log "Creating new borg repo with repokey encryption..."
  borg init --encryption=repokey
  log "Borg repo initialized"
fi

# --- Step 4: Export key ---
log "=== Step 4: Exporting borg key ==="
KEY_EXPORT_FILE="borg-key-export-$(date +%F).txt"

borg key export > "$KEY_EXPORT_FILE"
log "Key exported to: $KEY_EXPORT_FILE"
log ""
log "!!! CRITICAL: Save this key file AND your BORG_PASSPHRASE in a safe place !!!"
log "!!! Without both, your backups are UNRECOVERABLE !!!"
log ""

# --- Step 5: Test archive ---
log "=== Step 5: Creating test archive ==="
echo "OpenResiApp backup test $(date)" > /tmp/borg-test.txt
borg create --compression zstd,6 "::test-$(date +%F_%H%M%S)" /tmp/borg-test.txt
rm -f /tmp/borg-test.txt

log "Test archive created. Listing archives:"
borg list
log ""

# --- Step 6: Print append-only instructions ---
log "=== Setup complete ==="
log ""
log "========================================================"
log " IMPORTANT: Configure append-only mode on Hetzner"
log "========================================================"
log ""
log "This ensures an attacker with server access CANNOT delete backups."
log ""
log "1. Connect to your Storage Box via SFTP:"
log "   sftp -P 23 u123456@u123456.your-storagebox.de"
log ""
log "2. Create/edit .ssh/authorized_keys:"
log "   mkdir .ssh"
log "   get .ssh/authorized_keys"
log ""
log "3. Prefix your key with this restriction:"
log '   command="borg serve --append-only --restrict-to-path /home/backup/resiapp",restrict ssh-ed25519 AAAA...'
log ""
log "4. Upload the modified file:"
log "   put authorized_keys .ssh/authorized_keys"
log ""
log "5. Verify append-only works — from your server, try:"
log "   borg delete ::test-*"
log "   (should silently fail — archive still present)"
log ""
log "For manual pruning (from a DIFFERENT machine with unrestricted key):"
log "   borg prune --keep-daily=30 --keep-weekly=12 --keep-monthly=12"
log ""
log "Keys to save offline:"
log "  - $KEY_EXPORT_FILE"
log "  - BORG_PASSPHRASE value"
log "========================================================"

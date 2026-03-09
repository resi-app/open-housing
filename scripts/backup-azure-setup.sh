#!/bin/bash
# OpenResiApp — One-time restic backup setup for Azure Blob Storage
# Initializes restic repo on Azure with immutable storage for protection
# Usage: ./scripts/backup-azure-setup.sh
#
# Prerequisites:
#   - restic installed (apt install restic)
#   - RESTIC_REPOSITORY, RESTIC_PASSWORD, AZURE_ACCOUNT_NAME, AZURE_ACCOUNT_KEY in .env

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
if ! command -v restic &>/dev/null; then
  die "restic not installed. Run: apt install restic"
fi

log "Restic version: $(restic version)"

RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"
AZURE_ACCOUNT_NAME="${AZURE_ACCOUNT_NAME:-}"
AZURE_ACCOUNT_KEY="${AZURE_ACCOUNT_KEY:-}"

if [ -z "$RESTIC_REPOSITORY" ]; then
  die "RESTIC_REPOSITORY not set. Example: azure:resiapp-backups:/resiapp"
fi

if [ -z "$RESTIC_PASSWORD" ]; then
  die "RESTIC_PASSWORD not set. Generate one: openssl rand -base64 32"
fi

if [ -z "$AZURE_ACCOUNT_NAME" ] || [ -z "$AZURE_ACCOUNT_KEY" ]; then
  die "AZURE_ACCOUNT_NAME and AZURE_ACCOUNT_KEY must be set"
fi

export RESTIC_REPOSITORY
export RESTIC_PASSWORD
export AZURE_ACCOUNT_NAME
export AZURE_ACCOUNT_KEY

# --- Step 1: Test Azure access ---
log "=== Step 1: Testing Azure Blob Storage access ==="

# Extract container name from repository URL (azure:container:/path)
AZURE_CONTAINER=$(echo "$RESTIC_REPOSITORY" | sed -E 's|azure:([^:/]+).*|\1|')
log "Azure container: $AZURE_CONTAINER"

if command -v az &>/dev/null; then
  if az storage container show --name "$AZURE_CONTAINER" \
    --account-name "$AZURE_ACCOUNT_NAME" --account-key "$AZURE_ACCOUNT_KEY" &>/dev/null; then
    log "Azure Blob Storage access confirmed"
  else
    log "Container '$AZURE_CONTAINER' not found. Creating..."
    az storage container create --name "$AZURE_CONTAINER" \
      --account-name "$AZURE_ACCOUNT_NAME" --account-key "$AZURE_ACCOUNT_KEY"
    log "Container created"
  fi
else
  log "Azure CLI not installed — skipping access test (restic will test during init)"
fi

# --- Step 2: Initialize restic repo ---
log "=== Step 2: Initializing restic repository ==="

if restic cat config &>/dev/null 2>&1; then
  log "Restic repo already initialized at $RESTIC_REPOSITORY"
else
  log "Creating new restic repo..."
  restic init
  log "Restic repo initialized"
fi

# --- Step 3: Test backup ---
log "=== Step 3: Creating test snapshot ==="
echo "OpenResiApp backup test $(date)" > /tmp/restic-test.txt
restic backup /tmp/restic-test.txt --tag test
rm -f /tmp/restic-test.txt

log "Test snapshot created. Listing snapshots:"
restic snapshots
log ""

# --- Step 4: Print security instructions ---
log "=== Setup complete ==="
log ""
log "========================================================"
log " IMPORTANT: Configure immutable backups on Azure"
log "========================================================"
log ""
log "This ensures an attacker with server access CANNOT delete backups."
log ""
log "Option A: Immutable Blob Storage (recommended)"
log "  1. In Azure Portal → Storage Account → Container → $AZURE_CONTAINER"
log "  2. Go to 'Access policy' → Enable 'Immutable blob storage'"
log "  3. Add a time-based retention policy (e.g., 90 days)"
log "  4. Lock the policy (irreversible — blobs cannot be deleted for 90 days)"
log ""
log "Option B: RBAC with no delete (simpler)"
log "  1. Create a dedicated Service Principal for backups"
log "  2. Assign role: 'Storage Blob Data Contributor'"
log "  3. Add a deny assignment for 'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete'"
log "  4. Or use a custom role with only read/write (no delete) actions:"
log '     "actions": ['
log '       "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",'
log '       "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",'
log '       "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action"'
log '     ]'
log ""
log "  The server can upload but NEVER delete. Manual cleanup"
log "  requires a separate identity with full permissions."
log ""
log "Keys to save offline:"
log "  - RESTIC_PASSWORD value"
log "========================================================"
#!/bin/bash
# OpenResiApp — One-time restic backup setup for AWS S3
# Initializes restic repo on S3 with Object Lock for immutable backups
# Usage: ./scripts/backup-aws-setup.sh
#
# Prerequisites:
#   - restic installed (apt install restic)
#   - AWS CLI configured or env vars set
#   - RESTIC_REPOSITORY, RESTIC_PASSWORD, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY in .env

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
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"

if [ -z "$RESTIC_REPOSITORY" ]; then
  die "RESTIC_REPOSITORY not set. Example: s3:s3.eu-central-1.amazonaws.com/my-bucket/resiapp"
fi

if [ -z "$RESTIC_PASSWORD" ]; then
  die "RESTIC_PASSWORD not set. Generate one: openssl rand -base64 32"
fi

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  die "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set"
fi

export RESTIC_REPOSITORY
export RESTIC_PASSWORD
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

# --- Step 1: Test S3 access ---
log "=== Step 1: Testing S3 access ==="

# Extract bucket name from repository URL
S3_BUCKET=$(echo "$RESTIC_REPOSITORY" | sed -E 's|s3:[^/]+/([^/]+).*|\1|')
log "S3 bucket: $S3_BUCKET"

if command -v aws &>/dev/null; then
  if aws s3 ls "s3://${S3_BUCKET}" &>/dev/null; then
    log "S3 access confirmed"
  else
    log "WARNING: Cannot list S3 bucket. Check permissions and bucket name."
    read -p "Continue anyway? (y/N): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
      exit 1
    fi
  fi
else
  log "AWS CLI not installed — skipping S3 access test (restic will test during init)"
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
log " IMPORTANT: Configure immutable backups on AWS"
log "========================================================"
log ""
log "This ensures an attacker with server access CANNOT delete backups."
log ""
log "Option A: S3 Object Lock (recommended)"
log "  1. Enable Object Lock on the S3 bucket (must be set at creation)"
log "  2. Set a default retention policy:"
log "     aws s3api put-object-lock-configuration \\"
log "       --bucket $S3_BUCKET \\"
log "       --object-lock-configuration '{\"ObjectLockEnabled\":\"Enabled\",\"Rule\":{\"DefaultRetention\":{\"Mode\":\"COMPLIANCE\",\"Days\":90}}}'"
log ""
log "Option B: IAM policy (simpler, less strict)"
log "  Create a backup IAM user with this policy:"
log '  {'
log '    "Version": "2012-10-17",'
log '    "Statement": ['
log '      {'
log '        "Effect": "Allow",'
log '        "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],'
log "        \"Resource\": [\"arn:aws:s3:::${S3_BUCKET}\", \"arn:aws:s3:::${S3_BUCKET}/*\"]"
log '      },'
log '      {'
log '        "Effect": "Deny",'
log '        "Action": ["s3:DeleteObject", "s3:DeleteBucket"],'
log "        \"Resource\": [\"arn:aws:s3:::${S3_BUCKET}\", \"arn:aws:s3:::${S3_BUCKET}/*\"]"
log '      }'
log '    ]'
log '  }'
log ""
log "  The server can upload but NEVER delete. Manual cleanup"
log "  requires a separate IAM user with full permissions."
log ""
log "Keys to save offline:"
log "  - RESTIC_PASSWORD value"
log "========================================================"
#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Codyssey Akaunting: Deploy customizations to a server
#
# Run from the LOCAL workstation. No git required on any server.
# Pushes all Codyssey customizations via rsync, then triggers post-upgrade.sh.
#
# Usage:
#   bash scripts/deploy.sh               # default DEV server
#   SERVER=10.0.0.5 bash scripts/deploy.sh
# =============================================================================
set -Eeuo pipefail

SERVER="${SERVER:-192.168.143.130}"
SSH_USER="${SSH_USER:-igor}"
AKAUNTING_REMOTE="/var/www/html/akaunting"
MODULE_LOCAL="/home/igor/Documents/Projects/Codyssey/Akaunting/modules/AccountantReports"
MODULE_REMOTE="$AKAUNTING_REMOTE/modules/AccountantReports"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

info()    { echo "[INFO]  $*"; }
section() { echo; echo "=== $* ==="; }

# ---------------------------------------------------------------------------
# Step 1: Sync pure-new Codyssey files (safe to overwrite unconditionally)
# ---------------------------------------------------------------------------
section "Syncing new Codyssey files"

NEW_FILES=(
  app/View/Components/Documents/Template/Codyssey.php
  public/img/invoice_templates/codyssey.png
  resources/views/components/documents/template/codyssey.blade.php
  resources/views/sales/invoices/print_codyssey.blade.php
)

rsync -avz --relative --no-perms --no-owner --no-group \
  --rsync-path="sudo rsync" \
  "${NEW_FILES[@]}" \
  "$SSH_USER@$SERVER:$AKAUNTING_REMOTE/"

info "New files synced."

# ---------------------------------------------------------------------------
# Step 2: Sync patch files for modified core Akaunting files
# ---------------------------------------------------------------------------
section "Syncing patch files"

rsync -avz --relative --no-perms --no-owner --no-group \
  --rsync-path="sudo rsync" \
  scripts/patches/ \
  "$SSH_USER@$SERVER:$AKAUNTING_REMOTE/scripts/patches/"

info "Patch files synced."

# ---------------------------------------------------------------------------
# Step 3: Sync post-upgrade script
# ---------------------------------------------------------------------------
section "Syncing post-upgrade.sh"

rsync -avz --relative --no-perms --no-owner --no-group \
  --rsync-path="sudo rsync" \
  scripts/post-upgrade.sh \
  "$SSH_USER@$SERVER:$AKAUNTING_REMOTE/"

ssh "$SSH_USER@$SERVER" "sudo chmod +x $AKAUNTING_REMOTE/scripts/post-upgrade.sh"

# ---------------------------------------------------------------------------
# Step 4: Sync AccountantReports module
# ---------------------------------------------------------------------------
section "Syncing AccountantReports module"

if [[ ! -d "$MODULE_LOCAL" ]]; then
  echo "[WARN] $MODULE_LOCAL not found — skipping AccountantReports"
else
  rsync -avz --delete \
    --exclude='.git/' \
    --exclude='temp/' \
    --exclude='vendor/' \
    --rsync-path="sudo rsync" \
    "$MODULE_LOCAL/" \
    "$SSH_USER@$SERVER:$MODULE_REMOTE/"
  info "AccountantReports module synced."
fi

# ---------------------------------------------------------------------------
# Step 5: Run post-upgrade.sh on server
# ---------------------------------------------------------------------------
section "Running post-upgrade.sh on $SERVER"

ssh "$SSH_USER@$SERVER" "sudo bash $AKAUNTING_REMOTE/scripts/post-upgrade.sh"

echo
info "Deploy complete. Server: $SERVER"

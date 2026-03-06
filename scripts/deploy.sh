#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Codyssey Akaunting: Deploy customizations to a server
#
# Run from the LOCAL machine (workstation) after a git rebase/merge.
# Syncs all Codyssey-specific files to the server, then triggers
# post-upgrade.sh on the server side.
#
# Usage:
#   ./scripts/deploy.sh [SERVER]
#
# Examples:
#   ./scripts/deploy.sh                      # uses default DEV server
#   SERVER=192.168.1.50 ./scripts/deploy.sh  # override server
# =============================================================================
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SERVER="${SERVER:-192.168.143.130}"
SSH_USER="${SSH_USER:-igor}"
AKAUNTING_REMOTE="/var/www/html/akaunting"
MODULE_LOCAL="/home/igor/Documents/Projects/Codyssey/Akaunting/modules/AccountantReports"
MODULE_REMOTE="$AKAUNTING_REMOTE/modules/AccountantReports"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
section() { echo; echo "=== $* ==="; }

# ---------------------------------------------------------------------------
# Step 1: Sync Akaunting dev-branch files (git-tracked customizations)
# ---------------------------------------------------------------------------
section "Syncing Akaunting dev-branch files"

# Files tracked on the dev branch that differ from upstream master:
DEV_FILES=(
  app/Traits/Documents.php
  app/View/Components/Documents/Template/Codyssey.php
  public/img/invoice_templates/codyssey.png
  resources/lang/en-GB/settings.php
  resources/views/components/documents/show/template.blade.php
  resources/views/components/documents/template/codyssey.blade.php
  resources/views/sales/invoices/print_codyssey.blade.php
  resources/views/settings/invoice/edit.blade.php
)

rsync -avz --relative --no-perms --no-owner --no-group \
  --rsync-path="sudo rsync" \
  "${DEV_FILES[@]}" \
  "$SSH_USER@$SERVER:$AKAUNTING_REMOTE/"

info "Dev-branch files synced."

# ---------------------------------------------------------------------------
# Step 2: Sync post-upgrade script itself
# ---------------------------------------------------------------------------
section "Syncing scripts"

rsync -avz --relative --no-perms --no-owner --no-group \
  --rsync-path="sudo rsync" \
  scripts/post-upgrade.sh \
  "$SSH_USER@$SERVER:$AKAUNTING_REMOTE/"

# Make sure it's executable on the server
ssh "$SSH_USER@$SERVER" "sudo chmod +x $AKAUNTING_REMOTE/scripts/post-upgrade.sh"

# ---------------------------------------------------------------------------
# Step 3: Sync AccountantReports module
# ---------------------------------------------------------------------------
section "Syncing AccountantReports module"

if [[ ! -d "$MODULE_LOCAL" ]]; then
  echo "[WARN] AccountantReports module not found at $MODULE_LOCAL — skipping"
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
# Step 4: Run post-upgrade.sh on the server
# ---------------------------------------------------------------------------
section "Running post-upgrade.sh on $SERVER"

ssh "$SSH_USER@$SERVER" "sudo bash $AKAUNTING_REMOTE/scripts/post-upgrade.sh"

echo
info "Deploy complete. Server: $SERVER"

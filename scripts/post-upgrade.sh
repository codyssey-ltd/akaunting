#!/usr/bin/env bash
# =============================================================================
# post-upgrade.sh — Codyssey Akaunting: Server-side post-upgrade actions
#
# Run ON the server after Akaunting is upgraded and all custom files are synced.
# Handles all non-git customizations + AccountantReports module (re)installation.
#
# Usage (run as root or sudo):
#   sudo bash /var/www/html/akaunting/scripts/post-upgrade.sh
#
# Or remotely from the workstation:
#   ssh igor@192.168.143.130 "sudo bash /var/www/html/akaunting/scripts/post-upgrade.sh"
# =============================================================================
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_DIR="${REPO_DIR:-/var/www/html/akaunting}"
WEB_USER="${WEB_USER:-www-data}"
WEB_GROUP="${WEB_GROUP:-www-data}"

# Header background color for Default and Modern templates
THEAD_BG_COLOR="background-color: rgb(85, 88, 139) !important; -webkit-print-color-adjust: exact;"

# Logo
LOGO_SRC="${LOGO_SRC:-/var/backups/akaunting/public/img/akaunting-logo-green.svg}"
LOGO_DST_DIR="$REPO_DIR/public/img"

# AccountantReports module
MODULE_DIR="$REPO_DIR/modules/AccountantReports"
MODULE_REINSTALL_SCRIPT="$MODULE_DIR/scripts/clean_reinstall.sh"

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
DEFAULT_TPL="$REPO_DIR/resources/views/components/documents/template/default.blade.php"
MODERN_TPL="$REPO_DIR/resources/views/components/documents/template/modern.blade.php"
BANK_FEEDS="$REPO_DIR/resources/views/widgets/bank_feeds.blade.php"
PLANS_SRC="${PLANS_SRC:-/var/backups/akaunting/app/Traits/Plans.php}"
PLANS_DST="$REPO_DIR/app/Traits/Plans.php"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
warn()    { echo "[WARN]  $*"; }
section() { echo; echo "=== $* ==="; }

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || { warn "Skip backup (not found): $f"; return 0; }
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a "$f" "$f.bak.$ts"
  info "Backed up: $f.bak.$ts"
}

fix_ownership() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  chown "$WEB_USER:$WEB_GROUP" "$f"
}

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
section "Validating"

if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: Akaunting not found at $REPO_DIR"; exit 1
fi
cd "$REPO_DIR"

# ---------------------------------------------------------------------------
# Step 1: Fix thead background color — Default template
# ---------------------------------------------------------------------------
section "Fix thead background color (Default template)"

if [[ -f "$DEFAULT_TPL" ]]; then
  backup_file "$DEFAULT_TPL"
  sed -E -i \
    "s|<thead[^>]*style=\"[^\"]*\"|<thead style=\"${THEAD_BG_COLOR//|/\\|}\"  |g" \
    "$DEFAULT_TPL"
  fix_ownership "$DEFAULT_TPL"
  info "Default template thead fixed."
else
  warn "Default template not found: $DEFAULT_TPL"
fi

# ---------------------------------------------------------------------------
# Step 2: Fix thead background color — Modern template
# ---------------------------------------------------------------------------
section "Fix thead background color (Modern template)"

if [[ -f "$MODERN_TPL" ]]; then
  backup_file "$MODERN_TPL"
  sed -E -i \
    "s|<thead[^>]*style=\"[^\"]*\"|<thead style=\"${THEAD_BG_COLOR//|/\\|}\"  |g" \
    "$MODERN_TPL"
  fix_ownership "$MODERN_TPL"
  info "Modern template thead fixed."
else
  warn "Modern template not found: $MODERN_TPL"
fi

# ---------------------------------------------------------------------------
# Step 3: Remove Bank Feeds promo widget
# ---------------------------------------------------------------------------
section "Comment Bank Feeds promo widget"

if [[ -f "$BANK_FEEDS" ]]; then
  backup_file "$BANK_FEEDS"
  awk '
    BEGIN{inelse=0}
    /^[[:space:]]*@else[[:space:]]*$/ {
      print;
      print "    <!-- Promo block removed by post-upgrade.sh -->";
      inelse=1; next
    }
    inelse {
      if ($0 ~ /^[[:space:]]*@endif[[:space:]]*$/) { inelse=0; print; next }
      else if ($0 ~ /^[[:space:]]*<!--/) { print; }
      else if ($0 ~ /^[[:space:]]*$/)    { print; }
      else { gsub(/^[[:space:]]*/, "    <!-- "); print $0 " -->"; }
    }
    !inelse { print }
  ' "$BANK_FEEDS" > "$BANK_FEEDS.__tmp__" && mv "$BANK_FEEDS.__tmp__" "$BANK_FEEDS"
  fix_ownership "$BANK_FEEDS"
  info "Bank Feeds promo disabled."
else
  warn "bank_feeds.blade.php not found: $BANK_FEEDS"
fi

# ---------------------------------------------------------------------------
# Step 4: Copy logo asset
# ---------------------------------------------------------------------------
section "Copy logo asset"

if [[ -f "$LOGO_SRC" ]]; then
  cp -f "$LOGO_SRC" "$LOGO_DST_DIR/"
  local_dst="$LOGO_DST_DIR/$(basename "$LOGO_SRC")"
  chown "$WEB_USER:$WEB_GROUP" "$local_dst"
  chmod 644 "$local_dst"
  info "Logo copied: $local_dst"
else
  warn "Logo source not found: $LOGO_SRC — skipping"
fi

# ---------------------------------------------------------------------------
# Step 5: Restore Plans.php (unlimited plan limits)
# ---------------------------------------------------------------------------
section "Restore Plans.php (unlimited plan limits)"

if [[ -f "$PLANS_SRC" ]]; then
  backup_file "$PLANS_DST"
  cp -f "$PLANS_SRC" "$PLANS_DST"
  fix_ownership "$PLANS_DST"
  info "Plans.php restored from backup."
else
  warn "Plans.php backup not found: $PLANS_SRC — skipping. Verify app/Traits/Plans.php manually."
fi

# ---------------------------------------------------------------------------
# Step 6: Fix ownership of synced Codyssey template files
# ---------------------------------------------------------------------------
section "Fix ownership of Codyssey template files"

CODYSSEY_FILES=(
  "$REPO_DIR/app/Traits/Documents.php"
  "$REPO_DIR/app/View/Components/Documents/Template/Codyssey.php"
  "$REPO_DIR/public/img/invoice_templates/codyssey.png"
  "$REPO_DIR/resources/lang/en-GB/settings.php"
  "$REPO_DIR/resources/views/components/documents/show/template.blade.php"
  "$REPO_DIR/resources/views/components/documents/template/codyssey.blade.php"
  "$REPO_DIR/resources/views/sales/invoices/print_codyssey.blade.php"
  "$REPO_DIR/resources/views/settings/invoice/edit.blade.php"
)

for f in "${CODYSSEY_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    fix_ownership "$f"
  else
    warn "File not found (check rsync): $f"
  fi
done
info "Codyssey file ownership fixed."

# ---------------------------------------------------------------------------
# Step 7: Install / reinstall AccountantReports module
# ---------------------------------------------------------------------------
section "AccountantReports module install"

if [[ -d "$MODULE_DIR" ]] && [[ -f "$MODULE_REINSTALL_SCRIPT" ]]; then
  info "Running AccountantReports clean_reinstall.sh..."
  bash "$MODULE_REINSTALL_SCRIPT"
else
  if [[ ! -d "$MODULE_DIR" ]]; then
    warn "Module not found at $MODULE_DIR — skipping. Run deploy.sh first to sync."
  else
    warn "clean_reinstall.sh not found at $MODULE_REINSTALL_SCRIPT — skipping."
  fi
fi

# ---------------------------------------------------------------------------
# Step 8: Clear all caches
# ---------------------------------------------------------------------------
section "Clearing caches"

sudo -u "$WEB_USER" php artisan optimize:clear
sudo -u "$WEB_USER" php artisan view:clear
info "Caches cleared."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Post-upgrade actions complete"

echo ""
echo "Quick verify checklist:"
echo "  [ ] Print preview (Default/Modern) shows purple (#55588B) header background"
echo "  [ ] Dashboard: no Bank Feeds promo widget visible"
echo "  [ ] Logo displays correctly in the top nav"
echo "  [ ] Invoice creation: no plan limit warnings"
echo "  [ ] Settings > Invoices: 'Codyssey' template option visible"
echo "  [ ] AccountantReports module visible under Reports"
echo ""

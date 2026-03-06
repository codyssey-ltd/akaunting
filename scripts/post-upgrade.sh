#!/usr/bin/env bash
# =============================================================================
# post-upgrade.sh — Codyssey Akaunting: Server-side post-upgrade actions
#
# Run ON the server (as root or sudo) after Akaunting is upgraded.
# NO git required — uses rsync-synced files + standard Unix patch(1) command.
#
# Usage:
#   sudo bash /var/www/html/akaunting/scripts/post-upgrade.sh
#
# Or remotely triggered by deploy.sh:
#   ssh igor@192.168.143.130 "sudo bash /var/www/html/akaunting/scripts/post-upgrade.sh"
# =============================================================================
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_DIR="${REPO_DIR:-/var/www/html/akaunting}"
WEB_USER="${WEB_USER:-www-data}"
WEB_GROUP="${WEB_GROUP:-www-data}"
PATCHES_DIR="$REPO_DIR/scripts/patches"

THEAD_BG_COLOR="background-color: rgb(85, 88, 139) !important; -webkit-print-color-adjust: exact;"

LOGO_SRC="${LOGO_SRC:-/var/backups/akaunting/public/img/akaunting-logo-green.svg}"
LOGO_DST_DIR="$REPO_DIR/public/img"

PLANS_SRC="${PLANS_SRC:-/var/backups/akaunting/app/Traits/Plans.php}"
PLANS_DST="$REPO_DIR/app/Traits/Plans.php"

MODULE_DIR="$REPO_DIR/modules/AccountantReports"
MODULE_REINSTALL_SCRIPT="$MODULE_DIR/scripts/clean_reinstall.sh"

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
DEFAULT_TPL="$REPO_DIR/resources/views/components/documents/template/default.blade.php"
MODERN_TPL="$REPO_DIR/resources/views/components/documents/template/modern.blade.php"
BANK_FEEDS="$REPO_DIR/resources/views/widgets/bank_feeds.blade.php"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
warn()    { echo "[WARN]  $*"; }
section() { echo; echo "=== $* ==="; }

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || { warn "Skip backup (not found): $f"; return 0; }
  cp -a "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)"
  info "Backed up: $f"
}

fix_ownership() {
  [[ -e "$1" ]] && chown "$WEB_USER:$WEB_GROUP" "$1" || true
}

# Apply a patch file idempotently using the standard Unix patch(1) command.
# - Skips silently if already applied.
# - Exits with error if patch fails to apply (file changed too much after upgrade).
apply_patch() {
  local patchfile="$1"
  local label="$2"
  [[ -f "$patchfile" ]] || { warn "Patch not found: $patchfile — skipping $label"; return 0; }

  cd "$REPO_DIR"

  # Try dry-run forward apply
  if patch -p1 --dry-run --forward < "$patchfile" &>/dev/null; then
    backup_file "$(grep '^--- a/' "$patchfile" | head -1 | sed 's|--- a/||')" 2>/dev/null || true
    patch -p1 --forward < "$patchfile"
    info "Patch applied: $label"
  else
    # Check if it's already applied (reverse would succeed)
    if patch -p1 --dry-run --reverse < "$patchfile" &>/dev/null; then
      info "Already applied: $label (skipping)"
    else
      echo ""
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "  PATCH FAILED: $label"
      echo "  File likely changed in the Akaunting upgrade."
      echo "  Patch: $patchfile"
      echo "  Action required: manually apply changes, then regenerate the patch."
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo ""
      PATCH_FAILURES=$((PATCH_FAILURES + 1))
    fi
  fi
}

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: Akaunting not found at $REPO_DIR"; exit 1
fi
cd "$REPO_DIR"

PATCH_FAILURES=0

# ---------------------------------------------------------------------------
# Step 1: Apply patches to modified core Akaunting files
# ---------------------------------------------------------------------------
section "Applying patches to core files"

apply_patch "$PATCHES_DIR/Documents.patch"      "app/Traits/Documents.php (register Codyssey template)"
apply_patch "$PATCHES_DIR/settings-lang.patch"  "resources/lang/en-GB/settings.php (Codyssey label)"
apply_patch "$PATCHES_DIR/show-template.patch"  "resources/views/components/documents/show/template.blade.php (@case codyssey)"
apply_patch "$PATCHES_DIR/invoice-edit.patch"   "resources/views/settings/invoice/edit.blade.php (Codyssey settings card)"

# Fix ownership of patched files
for f in \
  "$REPO_DIR/app/Traits/Documents.php" \
  "$REPO_DIR/resources/lang/en-GB/settings.php" \
  "$REPO_DIR/resources/views/components/documents/show/template.blade.php" \
  "$REPO_DIR/resources/views/settings/invoice/edit.blade.php"; do
  fix_ownership "$f"
done

# ---------------------------------------------------------------------------
# Step 2: Fix ownership of new Codyssey-only files (rsynced by deploy.sh)
# ---------------------------------------------------------------------------
section "Fixing ownership of new Codyssey files"

for f in \
  "$REPO_DIR/app/View/Components/Documents/Template/Codyssey.php" \
  "$REPO_DIR/public/img/invoice_templates/codyssey.png" \
  "$REPO_DIR/resources/views/components/documents/template/codyssey.blade.php" \
  "$REPO_DIR/resources/views/sales/invoices/print_codyssey.blade.php"; do
  if [[ -f "$f" ]]; then
    fix_ownership "$f"
  else
    warn "File not found (check deploy.sh rsync ran first): $f"
  fi
done

# ---------------------------------------------------------------------------
# Step 3: Fix thead background color — Default template
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
  warn "Not found: $DEFAULT_TPL"
fi

# ---------------------------------------------------------------------------
# Step 4: Fix thead background color — Modern template
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
  warn "Not found: $MODERN_TPL"
fi

# ---------------------------------------------------------------------------
# Step 5: Disable Bank Feeds promo widget
# ---------------------------------------------------------------------------
section "Disable Bank Feeds promo widget"

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
  warn "Not found: $BANK_FEEDS"
fi

# ---------------------------------------------------------------------------
# Step 6: Copy logo asset
# ---------------------------------------------------------------------------
section "Copy logo asset"

if [[ -f "$LOGO_SRC" ]]; then
  cp -f "$LOGO_SRC" "$LOGO_DST_DIR/"
  dst="$LOGO_DST_DIR/$(basename "$LOGO_SRC")"
  chown "$WEB_USER:$WEB_GROUP" "$dst"
  chmod 644 "$dst"
  info "Logo copied: $dst"
else
  warn "Logo source not found: $LOGO_SRC — skipping. Copy manually to $LOGO_DST_DIR/"
fi

# ---------------------------------------------------------------------------
# Step 7: Restore Plans.php (unlimited plan limits)
# ---------------------------------------------------------------------------
section "Restore Plans.php (unlimited plan limits)"

if [[ -f "$PLANS_SRC" ]]; then
  backup_file "$PLANS_DST"
  cp -f "$PLANS_SRC" "$PLANS_DST"
  fix_ownership "$PLANS_DST"
  info "Plans.php restored."
else
  warn "Plans.php backup not found: $PLANS_SRC — skipping. Verify app/Traits/Plans.php manually."
fi

# ---------------------------------------------------------------------------
# Step 8: Install / reinstall AccountantReports module
# ---------------------------------------------------------------------------
section "AccountantReports module install"

if [[ -d "$MODULE_DIR" ]] && [[ -f "$MODULE_REINSTALL_SCRIPT" ]]; then
  bash "$MODULE_REINSTALL_SCRIPT"
else
  warn "Module or reinstall script not found — skipping."
  [[ -d "$MODULE_DIR" ]] || warn "Module dir: $MODULE_DIR"
  [[ -f "$MODULE_REINSTALL_SCRIPT" ]] || warn "Script: $MODULE_REINSTALL_SCRIPT"
fi

# ---------------------------------------------------------------------------
# Step 9: Clear all caches
# ---------------------------------------------------------------------------
section "Clearing caches"

sudo -u "$WEB_USER" php artisan optimize:clear
sudo -u "$WEB_USER" php artisan view:clear
info "Caches cleared."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Post-upgrade actions complete"

if [[ $PATCH_FAILURES -gt 0 ]]; then
  echo ""
  echo "WARNING: $PATCH_FAILURES patch(es) failed to apply."
  echo "These core files need manual review — see output above."
  echo "After fixing manually, regenerate the .patch files on your workstation:"
  echo "  See UPGRADE.md > 'Regenerating patches after a conflict'"
  echo ""
fi

echo ""
echo "Quick verify checklist:"
echo "  [ ] Print preview (Default/Modern): purple table header"
echo "  [ ] Dashboard: no Bank Feeds promo widget"
echo "  [ ] Logo visible in top nav"
echo "  [ ] Invoice creation: no plan limit warnings"
echo "  [ ] Settings > Invoices: 'Codyssey' template card present"
echo "  [ ] Reports menu: AccountantReports module visible"
echo ""

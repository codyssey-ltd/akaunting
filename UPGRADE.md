# Akaunting — Upgrade & Fresh Install Procedure

**No git required on any server.** All server-side work is pure rsync + `patch(1)`.

---

## The two-command workflow

After any Akaunting upgrade (regardless of how it was applied on the server):

```bash
# From your LOCAL workstation, in the akaunting repo directory:
bash scripts/deploy.sh
```

That's it. `deploy.sh` handles everything remotely.

To target a different server:
```bash
SERVER=10.0.0.5 bash scripts/deploy.sh
```

---

## What happens under the hood

### `scripts/deploy.sh` (runs locally, no git on server needed)

| Step | What |
|---|---|
| 1 | rsync 4 new Codyssey-only files to server |
| 2 | rsync `scripts/patches/*.patch` to server |
| 3 | rsync `scripts/post-upgrade.sh` to server |
| 4 | rsync `modules/AccountantReports/` to server |
| 5 | SSH → run `post-upgrade.sh` on server |

### `scripts/post-upgrade.sh` (runs on server, no git)

| Step | Action |
|---|---|
| 1 | Apply 4 `.patch` files to modified core files using `patch -p1` |
| 2 | Fix `www-data` ownership on all Codyssey files |
| 3–4 | Inject purple thead color into Default + Modern templates (sed) |
| 5 | Disable Bank Feeds promo widget (awk) |
| 6 | Copy logo from `/var/backups/akaunting/` |
| 7 | Restore `Plans.php` (unlimited plan limits) from backup |
| 8 | Reinstall AccountantReports module (`clean_reinstall.sh`) |
| 9 | `php artisan optimize:clear && view:clear` |

---

## Customization inventory

### Category A — New files (safe to rsync unconditionally)

| File | Description |
|---|---|
| `app/View/Components/Documents/Template/Codyssey.php` | PHP component class |
| `public/img/invoice_templates/codyssey.png` | Template thumbnail |
| `resources/views/components/documents/template/codyssey.blade.php` | Full template (font, taxable date row, VAT footer) |
| `resources/views/sales/invoices/print_codyssey.blade.php` | PDF print wrapper |

### Category B — Modified core files (applied via `.patch` files)

| Patch file | Target file | Change |
|---|---|---|
| `scripts/patches/Documents.patch` | `app/Traits/Documents.php` | Register Codyssey in template list |
| `scripts/patches/settings-lang.patch` | `resources/lang/en-GB/settings.php` | Add `'codyssey' => 'Codyssey'` label |
| `scripts/patches/show-template.patch` | `resources/views/components/documents/show/template.blade.php` | Add `@case('codyssey')` dispatch |
| `scripts/patches/invoice-edit.patch` | `resources/views/settings/invoice/edit.blade.php` | Add Codyssey settings UI card |

### Category C — Script-applied (sed/awk, no patch file needed)

| File | Change |
|---|---|
| `resources/views/components/documents/template/default.blade.php` | `<thead>` background color |
| `resources/views/components/documents/template/modern.blade.php` | `<thead>` background color |
| `resources/views/widgets/bank_feeds.blade.php` | Promo block disabled |
| `public/img/akaunting-logo-green.svg` | Logo restored from `/var/backups/akaunting/` |
| `app/Traits/Plans.php` | Unlimited plan limits |

### Category D — AccountantReports module

Source: `/home/igor/Documents/Projects/Codyssey/Akaunting/modules/AccountantReports`

Rsynced by `deploy.sh` → reinstalled by `modules/AccountantReports/scripts/clean_reinstall.sh`.

---

## Pre-requisites: backup locations on server

These two files must exist on the server before running `post-upgrade.sh`:

| File on server | Purpose |
|---|---|
| `/var/backups/akaunting/public/img/akaunting-logo-green.svg` | Company logo |
| `/var/backups/akaunting/app/Traits/Plans.php` | Unlimited plan limits |

To refresh the `Plans.php` backup after any manual changes:
```bash
sudo cp /var/www/html/akaunting/app/Traits/Plans.php \
        /var/backups/akaunting/app/Traits/Plans.php
```

---

## When a patch fails after an Akaunting upgrade

If `post-upgrade.sh` outputs `PATCH FAILED`, it means Akaunting changed one of
the modified core files significantly enough that the old patch no longer applies.

### Resolution steps (on LOCAL workstation)

1. **Download the new version of the failed file from the server:**
   ```bash
   scp igor@192.168.143.130:/var/www/html/akaunting/app/Traits/Documents.php \
       /tmp/Documents.php.new
   ```

2. **Manually apply the change** to the new file (same small addition as before).

3. **Upload the fixed file back:**
   ```bash
   rsync --rsync-path="sudo rsync" /tmp/Documents.php.fixed \
     igor@192.168.143.130:/var/www/html/akaunting/app/Traits/Documents.php
   ```

4. **Update the local file** in the repo to match the new version + our change:
   ```bash
   cp /tmp/Documents.php.fixed app/Traits/Documents.php
   ```

5. **Regenerate the patch file** (requires git locally — only on the workstation):
   ```bash
   # Get the new upstream version
   git fetch origin master
   git show origin/master:app/Traits/Documents.php > /tmp/Documents.upstream.php

   # Generate new patch
   diff -u /tmp/Documents.upstream.php app/Traits/Documents.php \
     | sed 's|/tmp/Documents.upstream.php|a/app/Traits/Documents.php|' \
     | sed 's|app/Traits/Documents.php|b/app/Traits/Documents.php|' \
     > scripts/patches/Documents.patch
   ```

   Or if you don't use git locally either, generate the patch manually:
   ```bash
   diff -u /tmp/Documents.php.new app/Traits/Documents.php > scripts/patches/Documents.patch
   # Then edit the patch file headers to match the format of the other .patch files
   ```

6. **Redeploy:**
   ```bash
   bash scripts/deploy.sh
   ```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `PATCH FAILED` in output | Core file changed in upgrade | See "When a patch fails" above |
| `Already applied` for all patches | Running post-upgrade.sh twice | Normal — idempotent, no action needed |
| `View [codyssey] not found` | New Codyssey files not rsynced | Run `deploy.sh` first, check rsync output |
| Grey table header in PDF | Thead sed not applied | Check `sed` output in post-upgrade.sh |
| Plan limit warnings | Plans.php not restored | Check `/var/backups/akaunting/app/Traits/Plans.php` exists |
| AccountantReports missing | Module rsync or reinstall failed | Check `MODULE_LOCAL` path in `deploy.sh` |
| 403 errors / wrong file owner | post-upgrade.sh not run as root | Use `sudo bash scripts/post-upgrade.sh` |

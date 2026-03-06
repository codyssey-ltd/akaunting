# Akaunting — Upgrade & Fresh Install Procedure

## Overview of customizations

All Codyssey modifications fall into three categories:

| Category | What | How applied |
|---|---|---|
| **A — Git** | Codyssey invoice template (8 files on `dev` branch) | `git rebase` after upgrade |
| **B — Script** | thead color, Bank Feeds promo, logo, Plans.php | `scripts/post-upgrade.sh` |
| **C — Module** | AccountantReports module | rsync + `clean_reinstall.sh` |

---

## Scenario 1: Akaunting version upgrade (in-place)

### Step 1 — Update upstream code (local)

```bash
cd /home/igor/Documents/Codyssey/akaunting

git checkout master
git pull origin master        # get new Akaunting version
git checkout dev
git rebase master             # apply our commits on top of new upstream
# If conflicts → fix manually → git add → git rebase --continue
```

Commits on `dev` that must survive the rebase:
- `Add new Codyssey document template and print view for invoices`
- `Enhance Codyssey template with new styling and title formatting`
- `Add issued date display and VAT exclusion note to Codyssey template`

### Step 2 — Deploy to server

```bash
# Sync all customized files + trigger server-side post-upgrade script
bash scripts/deploy.sh

# Override server if needed:
# SERVER=10.0.0.5 bash scripts/deploy.sh
```

`deploy.sh` does:
1. rsync Category A files (dev-branch) to server
2. rsync AccountantReports module to server
3. SSH → runs `post-upgrade.sh` on the server

### Step 3 — Verify (browser)

- Print preview (Default/Modern): purple `rgb(85,88,139)` table header
- Dashboard: no "Bank Feeds" promo widget
- Logo visible in top nav
- Settings > Invoices: "Codyssey" template card present
- Create invoice → no plan limit warnings
- Reports menu: AccountantReports module visible

---

## Scenario 2: Fresh installation

### Step 1 — Install Akaunting

Follow the standard Akaunting installation. At the end you should have:
- A working Akaunting instance at `/var/www/html/akaunting`
- Web server running as `www-data`

### Step 2 — Checkout Codyssey dev branch

```bash
cd /home/igor/Documents/Codyssey/akaunting
git checkout dev              # already has all Category A customizations
```

### Step 3 — Deploy all customizations

```bash
bash scripts/deploy.sh
```

### Step 4 — Restore database backup (if applicable)

```bash
# See: "Sync Akaunting DB and Files from Production to DEV" KB page
```

---

## Manual reference: what each script does

### `scripts/deploy.sh` (local machine)

| Step | Action |
|---|---|
| 1 | rsync 8 dev-branch files → server |
| 2 | rsync `scripts/post-upgrade.sh` → server |
| 3 | rsync AccountantReports module → server |
| 4 | SSH: run `post-upgrade.sh` on server |

### `scripts/post-upgrade.sh` (server)

| Step | File(s) | Action |
|---|---|---|
| 1 | `template/default.blade.php` | Fix `<thead>` background color |
| 2 | `template/modern.blade.php` | Fix `<thead>` background color |
| 3 | `widgets/bank_feeds.blade.php` | Comment out promo `@else` block |
| 4 | `public/img/akaunting-logo-green.svg` | Copy from `/var/backups/akaunting/` |
| 5 | `app/Traits/Plans.php` | Restore unlimited plan limits from backup |
| 6 | All 8 Codyssey template files | Fix `www-data` ownership |
| 7 | `modules/AccountantReports/` | Run `clean_reinstall.sh` (DB + migrate + events) |
| 8 | — | `php artisan optimize:clear && view:clear` |

---

## Pre-requisites / backup locations

The following files must exist on the server for the script to work:

| Backup file | Purpose |
|---|---|
| `/var/backups/akaunting/public/img/akaunting-logo-green.svg` | Company logo |
| `/var/backups/akaunting/app/Traits/Plans.php` | Unlimited plan limits |

To update the Plans.php backup after any changes:
```bash
sudo cp /var/www/html/akaunting/app/Traits/Plans.php \
        /var/backups/akaunting/app/Traits/Plans.php
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `View [codyssey] not found` | `show/template.blade.php` reverted | Check Category A files deployed |
| Grey table header in PDF | Thead fix not applied | Re-run `post-upgrade.sh` |
| Plan limit warnings | Plans.php reverted to upstream | Check backup path, re-run step 5 |
| AccountantReports missing | Module sync failed | Check `MODULE_LOCAL` in `deploy.sh` |
| Wrong file owner (403 errors) | rsync changed ownership | Step 6 of `post-upgrade.sh` fixes this |

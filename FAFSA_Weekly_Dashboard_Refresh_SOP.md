# FAFSA Completion Dashboard — Weekly Refresh & Deployment SOP

**Project:** `fafsa_template`  
**Use:** Weekly production refresh of the aggregated FAFSA completion dashboard (staff handoff)  
**Workflow:** SQL → dashboard CSV → QA → GitHub (Mac/RStudio) → DOE GitLab (Windows VM) → Jay deployment ticket → live-app verification  
**Last reviewed:** November 17, 2026

## Purpose and boundaries

This SOP is a repeatable, copy-and-paste-ready procedure for staff who maintain the FAFSA Completion Shiny dashboard. The **SQL query is run outside Shiny**; its summarized output CSV is the file read by the deployed app. GitHub is the publishing source; DOE GitLab is synchronized from GitHub on a VM with DOE network access. The live Shiny app does **not** necessarily refresh when GitLab changes—request redeployment separately.

**In scope (routine weekly refresh):**

- `prep/scripts/fafsa_completion.sql` — versioned production query; change only when necessary.
- `input_data/fafsa_completion.csv` — refreshed summarized dashboard input.
- `prep/scripts/fafsa_production_qa_qc.R` — run, do not edit as part of routine data refresh.
- GitHub `MatthewFaiello/fafsa_template`, branch `main`.
- DOE GitLab `DMG/fafsa_template`, branch `main`.
- Shiny app: https://twpt.doe.k12.de.us/doe/fafsa_template/

**Out of scope:** Biweekly email sending, recipient rosters, student-level data, private files, changing Shiny code/dependencies, and automatic deployments. Keep `prep/emailer/private/`, `prep/emailer/snapshots/`, and `prep/emailer/output/` local; do not stage or push these folders.

## Weekly checklist

- [ ] Confirm access to the SQL environment, GitHub, DOE VPN/GitLab, RStudio project, and ticket system.
- [ ] Run current production SQL; export the aggregate with the required column headers.
- [ ] Replace `input_data/fafsa_completion.csv` in `fafsa_template.Rproj`; update SQL file only if query logic changed.
- [ ] Run the production QA script and confirm **FINAL QA / QC STATUS: PASS** (not REVIEW).
- [ ] Push the two source files to GitHub `main`; retain its commit hash.
- [ ] On Windows VM, safely synchronize GitHub `main` to DOE GitLab `main`; verify exact commit match.
- [ ] Submit a Network/Engineering ticket assigned to `jayk.helgesen` requesting the Shiny redeployment.
- [ ] After deployment is confirmed, verify the live dashboard against the refreshed data.
- [ ] Record refresh date, Git commit, ticket number, and verification result.

## 1 — Refresh the SQL and CSV (SQL environment + Mac/RStudio)

1. Open the existing `fafsa_template.Rproj` on the Mac. For a shared handoff, **get the latest project changes before editing** (RStudio Terminal: `git pull --ff-only origin main`, while on `main`). If files were already changed locally, do not discard them; a conflicting pull should stop and be reviewed.
2. Open `prep/scripts/fafsa_completion.sql`, run the validated production query in the approved SQL environment, and export the full summarized result **with column headers**. Save the export as `input_data/fafsa_completion.csv`, replacing the prior aggregate. If the SQL was modified to generate the refresh, save that change to `prep/scripts/fafsa_completion.sql` too. Do not introduce student-level records into the repository.
3. Check that the CSV is not empty; `DataAsOf` reflects the intended refresh, the newest `SchoolYear` is present, and the expected `school`, `lea`, and `state` levels are included. Avoid opening and resaving the CSV in Excel, which can change codes/dates/formatting.
4. Run QA **before** publishing.

### RStudio Console — production QA

Paste into the **R Console**, not the Terminal:

```r
source("prep/scripts/fafsa_production_qa_qc.R")
if (!isTRUE(all_checks_pass)) {
  stop("STOP: FAFSA production QA did not PASS. Do not publish.")
}
```

At the end, locate `FINAL QA / QC STATUS`. **Proceed only if it says `PASS: Production FAFSA aggregate passed all structural and reconciliation checks.`** The script may complete without an R exception even when it prints `REVIEW`; `REVIEW` is a stop condition. Inspect the QA diagnostics in `prep/validation/`, correct the data or logic, and rerun QA before continuing.

### Mac/RStudio Terminal — publish ONLY the SQL and CSV to GitHub

Open the **Terminal tab inside the `fafsa_template.Rproj` project**. Paste this entire block (Mac bash/zsh syntax):

```bash
(
  set -e

  test -f 'fafsa_template.Rproj' || {
    echo 'ERROR: Open the Terminal inside fafsa_template.Rproj first.'
    exit 1
  }
  test "$(git branch --show-current)" = 'main' || {
    echo 'ERROR: Switch to the main branch first.'
    exit 1
  }

  # Update local Git history; stop rather than overwrite conflicting work.
  git pull --ff-only origin main

  # Stage exactly the two approved production files.
  git -c core.filemode=false add -- prep/scripts/fafsa_completion.sql input_data/fafsa_completion.csv
  git diff --cached --check -- prep/scripts/fafsa_completion.sql input_data/fafsa_completion.csv
  git diff --cached --stat -- prep/scripts/fafsa_completion.sql input_data/fafsa_completion.csv
  git diff --cached --summary -- prep/scripts/fafsa_completion.sql input_data/fafsa_completion.csv

  # Commit only these paths; other staged files are not included.
  if ! git diff --cached --quiet -- prep/scripts/fafsa_completion.sql input_data/fafsa_completion.csv; then
    git commit -m 'Refresh FAFSA SQL and completion data' -- \
      prep/scripts/fafsa_completion.sql input_data/fafsa_completion.csv
  else
    echo 'No new SQL/CSV changes to commit.'
  fi

  git push origin main
  printf 'GitHub main commit: %s\n' "$(git rev-parse HEAD)"
)
```

**Check before continuing:** `git push` succeeded, the displayed commit is recorded, and any unexpected file-permission change (e.g., `100644 → 100755`) was corrected. The staging command ignores macOS file-mode differences; the Mac previously used for this project also has `git config core.filemode false` set. Any `100644 → 100755` change still needs review. A `CRLF will be replaced by LF` message is typically an informational line-ending warning; still review the file/QA if its content unexpectedly changed.

## 2 — Windows VM: synchronize GitHub to DOE GitLab

Use **Windows PowerShell**, not the GitLab web/desktop-style app. Connect to the DOE VPN. **Git for Windows** must be available (`git --version`). The GitLab desktop-style window is a website/app shortcut; it is not the Git command-line tool.

The standard VM must already contain `$HOME\fafsa_template_gitlab_sync` with `origin` pointing to GitHub and `gitlab` pointing to DOE GitLab. This is a **one-time setup**; do not rerun `git clone` or `git remote add gitlab` if they already exist.

### PowerShell 5.1 — weekly sync; paste as ONE block

```powershell
& {
  $ErrorActionPreference = 'Stop'

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git for Windows is unavailable. Install Git or use a configured VM.'
  }

  $repo = Join-Path $HOME 'fafsa_template_gitlab_sync'
  if (-not (Test-Path (Join-Path $repo '.git'))) {
    throw 'Sync repository missing. Complete the one-time VM setup first.'
  }
  Set-Location $repo

  git fetch origin main
  if ($LASTEXITCODE -ne 0) { throw 'GitHub fetch failed. Stop.' }

  git fetch gitlab main
  if ($LASTEXITCODE -ne 0) { throw 'DOE GitLab fetch failed. Check VPN/access. Stop.' }

  # Never discard commits created only in GitLab.
  $gitlabOnly = @(git log --oneline origin/main..gitlab/main)
  if ($LASTEXITCODE -ne 0) { throw 'Branch comparison failed. Stop.' }
  if ($gitlabOnly.Count -gt 0) {
    $gitlabOnly
    throw 'STOP: GitLab contains commits absent from GitHub. Review before syncing.'
  }

  # Safe fast-forward push (no --force).
  git push gitlab origin/main:main
  if ($LASTEXITCODE -ne 0) { throw 'GitLab push failed. Do not force-push.' }

  # Verify both remote branch tips are exactly identical.
  $expected = (git rev-parse origin/main).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'Could not read GitHub commit.' }
  $actualLine = git ls-remote gitlab refs/heads/main
  if ($LASTEXITCODE -ne 0 -or -not $actualLine) {
    throw 'Could not read GitLab commit.'
  }
  $actual = (($actualLine -split '\s+')[0]).Trim()
  if ($expected -ne $actual) {
    throw 'STOP: GitLab commit does not match GitHub.'
  }

  Write-Host "SUCCESS: GitHub and DOE GitLab match: $actual"
}
```

**Expected:** `SUCCESS: GitHub and DOE GitLab match: <full commit hash>`. Do not submit a deployment ticket until the hashes match. No `--force`, `reset --hard`, or deletion of the sync folder is needed in an ordinary refresh.

### One-time Windows VM setup (only on a new VM)

After Git for Windows is installed, DOE VPN is connected, and user has repository permissions:

```powershell
Set-Location $HOME
git clone https://github.com/MatthewFaiello/fafsa_template.git fafsa_template_gitlab_sync
Set-Location "$HOME\fafsa_template_gitlab_sync"
git remote add gitlab https://gitlab.doe.k12.de.us/DMG/fafsa_template.git
git remote -v
```

If the folder or remote already exists, **do not recreate it**; inspect with `git remote -v` and use the weekly sync block above. Access/authentication failures should be addressed through normal organizational permissions; do not save credentials in the SOP or project files.

## 3 — Submit the Shiny redeployment ticket

**Submit a new ticket for each weekly refresh after GitHub/GitLab hashes match.** Use the internal service-request portal and choose the following fields:

| Field | What to choose / enter |
|---|---|
| Request pathway | **Network/Engineering → Ask any general Network/Engineering topic** |
| Title | **FAFSA Dashboard Redeployment Request** |
| Owner / assigned technician | **`jayk.helgesen`** (select Jay when assignment is available) |
| Priority | **High** — staff rely on timely refreshed FAFSA completion data |
| Category | **Servers::Deployment**, if available |
| Impact | Choose the **truthful** level of impact. Do not report an outage or select “Many people cannot work” unless that is actually occurring. |
| Summary/description | Copy the message below |

### Copy-ready ticket message

> Hi Jay!
>
> I just pushed this week's FAFSA dashboard update to `DMG/fafsa_template` in GitLab. Could you redeploy the app when you get a chance?
>
> GitLab repo: https://gitlab.doe.k12.de.us/DMG/fafsa_template  
> Current dashboard: https://twpt.doe.k12.de.us/doe/fafsa_template/
>
> Thank you!

**For the refresh record:** Retain the verified GitHub/GitLab commit hash, the CSV's `DataAsOf` refresh date, and the ticket ID. Add the commit and refresh date to the ticket's appropriate fields or an optional note if the portal allows. There is no need to change the short message above. **High** is the selected operational priority because the data are relied upon; it does not imply the app is down.

The screenshot of an earlier request showed a `Servers::Deployment` category and `Closed` status. For a **new** request, use the pathway above and assign Jay as the owner. Ticket submission or a `Closed` status alone is not proof that the newly refreshed dashboard is live; verify the app directly.

## 4 — Verify the live dashboard after Jay redeploys

1. Open https://twpt.doe.k12.de.us/doe/fafsa_template/ and refresh the page (use a hard refresh if necessary).
2. Confirm the app loads without errors and the newest reporting school year is selectable.
3. Verify at least one **state**, one **LEA**, and one **school** view against the refreshed aggregate CSV. Confirm the latest expected month, completion rate, and cumulative series. School-year/month filters should behave normally, including months with no new completions.
4. Confirm the observed updated results are actually live; a `Closed` ticket or successful Git push alone is not sufficient.
5. If the dashboard still displays older values, provide Jay the GitLab commit hash, data refresh date, URL, and a screenshot or specific example of the mismatch. Do **not** issue another Git push merely to trigger a redeploy unless the source files changed.

## 5 — Record the refresh and close out

Keep a simple shared record (ticket notes or internal tracker, **not** the public GitHub data repo):

| Field | Example / instruction |
|---|---|
| Reporting date | `[DataAsOf YYYY-MM-DD]` |
| Refreshed by | `[staff member]` |
| QA | `PASS` / `REVIEW` (do not deploy REVIEW) |
| GitHub/GitLab hash | `[identical 40-character hash]` |
| Deployment ticket | `[ticket ID/link]` |
| Redeployment confirmed | `[date/time or Jay confirmation]` |
| Live dashboard validation | `[PASS + checked school/LEA/state]` |

**Definition of complete:** QA passes, GitHub and DOE GitLab have identical `main` commit hashes, a deployment request has been completed, and the live Shiny dashboard reflects the refreshed aggregate.

## Troubleshooting — stop rather than force

- **`git: command not found` / PowerShell does not recognize `git`:** Install **Git for Windows** or use the configured VM. The GitLab app icon alone is insufficient.
- **`destination path already exists` / `remote gitlab already exists`:** The VM is already configured. Skip one-time setup, use the existing directory and weekly sync block.
- **Cannot access DOE GitLab:** Confirm VPN connection and GitLab permissions before retrying.
- **GitLab-only commits detected:** Stop; review and reconcile branch history with the maintainer. Never force-push by default.
- **QA shows `REVIEW`:** Do not push or request deployment; fix the underlying checks and rerun.
- **Permission-only change or huge unexpected CSV diff:** Inspect `git diff --cached --summary` and the aggregate data. SQL/CSV should not be executable. Avoid re-saving exported CSVs through spreadsheet software.
- **GitLab matches but dashboard is stale:** This is a deployment/hosting question for Jay, not a Git sync error.
- **Biweekly emailer:** It is **not** part of this SOP. Keep emailer in `MODE <- "preview"` unless a separate reviewed and approved test/send workflow is being run. Never use weekly deployment steps as authorization for bulk school mailing.

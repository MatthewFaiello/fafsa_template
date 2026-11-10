# Biweekly FAFSA emailer (inside `fafsa_template.Rproj`)

This folder contains the **email workflow**, not a separate Shiny app or RStudio project.
It uses the dashboard's validated `input_data/fafsa_completion.csv`, produced by
`prep/scripts/fafsa_completion.sql`. Do not run the retired `fafsaEdinsight.sql`
for this emailer.

## How to read the R code (for novice R users)

**Unlike Shiny, this is not reactive.** When you run
`source("prep/emailer/run_biweekly_email.R")`, R executes that script **once,
from top to bottom**. Nothing runs when an end user changes a dropdown.

```text
Dashboard CSV + reviewed Excel roster
                  |
                  v
1. Settings and input checks
                  |
                  v
2. School-level totals and completion rates
                  |
                  v
3. Previous archived refresh (if available)
                  |
                  v
4. Match schools to reviewed recipients
                  |
                  v
5. Build HTML and write local preview
                  |
                  v
6. MODE decides: preview / test / send
```

Start with **`run_biweekly_email.R`**. Each numbered section creates objects
used by the section below it. The important R ideas appear in context:

- `source()` loads the functions from `email_layout.R`.
- `group_by()` + `summarise()` reduce many monthly records to one school row.
- `left_join()` brings earlier snapshot rates onto current school rows.
- `anti_join()` identifies unmatched schools and schools not approved for emails.
- `inner_join()` limits the mailing to schools on the reviewed roster.
- `if` and `for` control the optional Outlook send step.

Then open **`email_layout.R`** to see how ordinary R functions and `paste0()`
turn school-specific values into HTML. It contains formatting only, similar
to how `R/plot.R` holds plotting functions in the Shiny app. **CSS and
Outlook HTML are not the focus of the R lesson.**

The essential distinction: in the dashboard, **reactive expressions** run
again when input selections change; in this emailer, **sequential statements**
run once when the script is sourced. They share the validated CSV but not
an execution model.

## Project locations

- `input_data/fafsa_completion.csv`: the SAME aggregated source used by Shiny
- `prep/scripts/fafsa_completion.sql`: shared production query; run in SQL Server
- `prep/scripts/fafsa_production_qa_qc.R`: QA on each refreshed CSV
- `prep/emailer/run_biweekly_email.R`: email preparation, preview, and optional sending
- `prep/emailer/email_layout.R`: original HTML email (dashboard button, snapshots,
  scholarships, EdInsight, Stand By Me, support link, signature, logo)
- `prep/emailer/private/roster_fafsaBiweekly.xlsx`: last year's pruned recipient roster
- `prep/emailer/snapshots/`: archived dashboard refreshes for biweekly comparisons
- `prep/emailer/output/`: contact review, rate review, HTML preview, and send logs
- `www/Website-Header.png`: shared DOE logo

The `private`, `snapshots`, and `output` directories are ignored by Git via
`prep/emailer/.gitignore`. Keep them **local only**. This matters because
`DMG/fafsa_template` is deployed as a web app. Check with `git status --short`
and `git check-ignore` before committing. Never include staff contact details
or email logs in the deployed app bundle.

## Initial setup in RStudio

Open `fafsa_template.Rproj`. In its Terminal, from the project root:

```sh
pwd
# Should show the directory containing fafsa_template.Rproj
unzip -n "$HOME/Downloads/FAFSA_Emailer_for_fafsa_template.zip" -d .
git check-ignore -v prep/emailer/private/roster_fafsaBiweekly.xlsx
```

The zip contains ONLY `prep/emailer/`, so it does not overwrite `global.R`,
`ui.R`, `server.R`, dashboard input data, or production SQL.

Use the R Console to install packages (once, if missing):

```r
install.packages(c("tidyverse", "readxl", "htmltools", "base64enc"))
# Only when planning an Outlook test or live send:
install.packages("Microsoft365R")
```

## Every two weeks

1. Run `prep/scripts/fafsa_completion.sql` in SQL Server and export its entire
   aggregated result to `input_data/fafsa_completion.csv`.
2. In the RStudio Console, run:

   ```r
   source("prep/scripts/fafsa_production_qa_qc.R")
   source("prep/emailer/run_biweekly_email.R")
   ```

   The emailer defaults to `MODE <- "preview"`. It writes files to
   `prep/emailer/output/`, never sends email, and archives the current CSV by
   its `DataAsOf` date. Run only after QA has passed.
3. Review `output/roster_review.csv` (the actual addresses),
   `output/recipient_review.csv` (rates and comparisons),
   `output/schools_without_roster.csv` (intentionally unmailed), and
   `output/preview_email.html` (open in browser).
4. Test an Outlook message by editing these lines at the top of the script:

   ```r
   MODE <- "test"
   TEST_EMAIL <- "your.email@organization.org"
   ```

   Rerun `source("prep/emailer/run_biweekly_email.R")`. The test goes only
   to `TEST_EMAIL`, not any school contacts.
5. **Only after confirming the reviewed roster is current** and testing the
   email, use `MODE <- "send"` and `SEND_APPROVED <- TRUE`. Source the script
   in the interactive RStudio Console. It prompts for the exact word `SEND`.
   The send log is kept locally, and reruns skip schools marked as sent for
   the same `DataAsOf` date.
6. Restore `MODE <- "preview"`, `TEST_EMAIL <- ""`, and
   `SEND_APPROVED <- FALSE` for safe future use. Commit/deploy the **dashboard
   CSV and public app files only**, not the private emailer outputs.

## Current vs. previous rates

The dashboard CSV groups completed FAFSAs by *receipt month*. It does **not**
contain biweekly historical snapshots. To compare two email dates, the emailer
saves each refreshed CSV in `snapshots/` and picks the latest earlier archived
extract containing the same school year. It calculates each school's rate from
that snapshot's senior denominator and cumulative completed count.

The first preview may have no earlier archived extract; in that case, the email
states that the prior comparison is unavailable (rather than inventing one).
As soon as the next biweekly CSV is archived, the script can show both rates.

## Mailing-list policy

This is the **pruned prior-year roster**, not an automatic import of newly
employed school staff. Schools missing from the roster remain excluded;
unmatched roster schools STOP the pipeline. The emailer matches school names,
not prior-year LEA names, so charter LEA changes don't break matching. Before
live sending, verify staff addresses, role changes, opt-outs and approvals.

## Packages

Preview: `tidyverse`, `readxl`, `htmltools`, `base64enc`.
Test/send additionally: `Microsoft365R`. These packages are for the **local
emailer**, not additional dependencies Jay needs to install for Shiny.

## Operational note

The emailer **does not automatically refresh SQL or deploy the app**. It reads
the validated CSV after you complete your usual biweekly dashboard refresh.
Its snapshot archive and sending require local RStudio execution; no scheduling
or unattended sending has been configured.

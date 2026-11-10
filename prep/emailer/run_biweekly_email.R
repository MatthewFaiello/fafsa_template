# =============================================================================
# BIWEEKLY FAFSA EMAILS — MAIN SCRIPT
# =============================================================================
# Learning goal: follow a reporting pipeline written in ordinary R.
# Unlike a Shiny server, this script executes TOP TO BOTTOM when sourced.
#
# Read the workflow in this order:
#   dashboard CSV -> school rates -> earlier refresh -> reviewed recipients
#                 -> email HTML -> preview / test / send
#
# The dashboard and emailer share ONE input_data/fafsa_completion.csv.
# Refresh that file with fafsa_completion.sql and run production QA first.
# This script never runs SQL or deploys the Shiny app.
#
# Read first: run_biweekly_email.R  (data, decisions, and execution)
# Read next:  email_layout.R        (functions that format the HTML)
#
# MODE = "preview": write files, send nothing (default).
# MODE = "test":    send ONE example to TEST_EMAIL only.
# MODE = "send":    send the reviewed roster after explicit approval.
# Run from the directory containing fafsa_template.Rproj.
# =============================================================================

library(tidyverse)
library(readxl)
library(htmltools)
library(base64enc)

# source() runs another R file, making its functions available below.
# Here it defines the HTML builders; it does NOT send email by itself.
source("prep/emailer/email_layout.R")

# ==== 1. SETTINGS ============================================================
# Edit the settings in this one place; the rest of the workflow reads them.
# All file paths are relative to the existing fafsa_template.Rproj root.
# The three private folders below must not be committed or deployed.
APP_CSV <- "input_data/fafsa_completion.csv"
ROSTER_XLSX <- "prep/emailer/private/roster_fafsaBiweekly.xlsx"
SNAPSHOT_DIR <- "prep/emailer/snapshots"
OUTPUT_DIR <- "prep/emailer/output"
LOGO_FILE <- "www/Website-Header.png"

DASHBOARD_URL <- "https://twpt.doe.k12.de.us/doe/fafsa_template/"
BOOKING_URL <- "https://app.acuityscheduling.com/schedule/04adeba3"
CONTACT_EMAIL <- "dheo@doe.k12.de.us"
EMAIL_SUBJECT <- "Biweekly FAFSA Completion Updates"

# Mode is a simple control variable used by the if/else block at the end.
# Keep this as "preview" while developing, refreshing, or checking recipients.
MODE <- "preview"              # "preview", "test", or "send"
TEST_EMAIL <- ""                # Set your own email address in test mode
PREVIEW_SCHOOL <- "Appoquinimink High School"
ALWAYS_CC <- ""                 # Optional; leave empty unless approved
SEND_APPROVED <- FALSE          # Must explicitly change to TRUE for live sending

# ==== 2. READ AND VALIDATE THE SHARED APP DATA ================================
# stop()/stopifnot() halt execution if required inputs are missing or invalid.
# Fail BEFORE creating or sending school-specific messages.
stopifnot(MODE %in% c("preview", "test", "send"))
if (!startsWith(DASHBOARD_URL, "https://")) {
  stop("DASHBOARD_URL must be the live HTTPS dashboard link.")
}
if (!file.exists(APP_CSV)) stop("App CSV not found: ", APP_CSV)
if (!file.exists(ROSTER_XLSX)) stop("Roster not found: ", ROSTER_XLSX)
if (!file.exists(LOGO_FILE)) stop("DOE logo not found: ", LOGO_FILE)

dir.create(SNAPSHOT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# A small reader function ensures current and archived CSVs use identical
# column types. "NULL" in the source means a missing receipt month, not a date.
read_app_csv <- function(path) {
  readr::read_csv(
    path,
    col_types = readr::cols(
      .default = readr::col_character(),
      DataAsOf = readr::col_date(),
      EnrollmentAsOf = readr::col_date(),
      ApplicationReceiptMonth = readr::col_date(),
      SchoolYear = readr::col_integer(),
      seniors = readr::col_integer(),
      completed_this_month = readr::col_integer()
    ),
    na = c("", "NA", "NULL"),
    show_col_types = FALSE
  )
}

# The file is read once. All subsequent objects are built from app_data.
app_data <- read_app_csv(APP_CSV)

# The input contract is the same one used by the production Shiny app.
required_columns <- c(
  "DataAsOf", "EnrollmentAsOf", "level", "SchoolYear", "DistrictCode",
  "DistrictName", "SchoolCode", "SchoolName", "ApplicationReceiptMonth",
  "seniors", "completed_this_month"
)
if (!all(required_columns %in% names(app_data))) {
  stop("App CSV is missing expected columns: ",
       paste(setdiff(required_columns, names(app_data)), collapse = ", "))
}
if (nrow(app_data) == 0 || n_distinct(app_data$DataAsOf) != 1 ||
    any(is.na(app_data$DataAsOf))) {
  stop("App CSV must contain exactly one non-missing DataAsOf value.")
}

# DataAsOf is the REFRESH date (not the month a FAFSA was received).
# The latest available SchoolYear determines which year receives the email.
as_of <- unique(app_data$DataAsOf)
school_year <- max(app_data$SchoolYear, na.rm = TRUE)

# This function converts monthly school rows into ONE row per school.
# group_by() defines the schools; summarise() collapses each group.
# The CSV's completed_this_month values are monthly counts, so sum() yields
# cumulative completions as of this extract. The senior denominator repeats
# on every month: first(seniors) is correct, sum(seniors) would be wrong.
# The same function works for the current CSV and an earlier archived CSV.
school_snapshot <- function(data, year) {
  result <- data %>%
    filter(level == "school", SchoolYear == year) %>%
    group_by(SchoolCode, SchoolName, DistrictCode, DistrictName) %>%
    summarise(
      DataAsOf = first(DataAsOf),
      n_denominators = n_distinct(seniors),
      seniors = first(seniors),
      completed = sum(completed_this_month),
      .groups = "drop"
    )

  if (nrow(result) == 0) stop("No school-level rows for SY", year)
  if (any(result$n_denominators != 1) || anyNA(result$seniors) ||
      anyNA(result$completed) || any(result$seniors <= 0) ||
      any(result$completed < 0) || any(result$completed > result$seniors)) {
    stop("Invalid school denominator or completion totals. Run dashboard QA.")
  }
  if (anyDuplicated(result$SchoolCode) || anyDuplicated(result$SchoolName)) {
    stop("School codes/names are not unique within the selected year.")
  }

  # mutate() adds the rate on a 0–100 scale, matching fmt_pct() in the email.
  result %>%
    mutate(completion_pct = 100 * completed / seniors) %>%
    select(-n_denominators)
}

# current now has one rate per school. Compare its totals with the state row
# as a second check before any school emails are prepared.
current <- school_snapshot(app_data, school_year)
state <- app_data %>%
  filter(level == "state", SchoolYear == school_year)
if (nrow(state) == 0 || n_distinct(state$seniors) != 1 ||
    sum(current$seniors) != first(state$seniors) ||
    sum(current$completed) != sum(state$completed_this_month)) {
  stop("School-level totals do not match the statewide totals. Run dashboard QA.")
}
if (sum(current$completed) == 0) {
  stop("Latest school year has no completed FAFSA receipts yet; nothing to email.")
}

# ==== 3. PREVIOUS REFRESH AND SNAPSHOT ARCHIVE ================================
# A receipt month (e.g., October) is NOT a previous biweekly reporting date.
# To compare "now" vs. "two weeks ago", use two separately archived CSVs.
# list.files() finds dated archives; the loop selects the latest EARLIER file
# that contains the SAME school year. On the first refresh, previous is empty.
# Each run also saves today's dashboard CSV for the next refresh.
archived_files <- list.files(
  SNAPSHOT_DIR,
  pattern = "^fafsa_completion_[0-9]{4}-[0-9]{2}-[0-9]{2}\\.csv$",
  full.names = TRUE
)
archived_dates <- as.Date(sub(
  "^fafsa_completion_([0-9]{4}-[0-9]{2}-[0-9]{2})\\.csv$", "\\1",
  basename(archived_files)
))
older_files <- archived_files[archived_dates < as_of]

# An empty tibble makes the initial (no-prior-refresh) case explicit.
previous <- tibble(SchoolCode = character(), previous_as_of = as.Date(character()),
                   previous_pct = double())

if (length(older_files) > 0) {
  # Find the newest earlier extract with data for this same school year.
  # An archive from a different SY must not be used as a comparison.
  candidates <- older_files[order(archived_dates[archived_dates < as_of], decreasing = TRUE)]

  for (candidate in candidates) {
    old_data <- read_app_csv(candidate)
    if (any(old_data$SchoolYear == school_year)) {
      if (n_distinct(old_data$DataAsOf) != 1 ||
          unique(old_data$DataAsOf) >= as_of) {
        stop("Invalid earlier archived refresh: ", candidate)
      }

      previous <- school_snapshot(old_data, school_year) %>%
        transmute(SchoolCode, previous_as_of = DataAsOf,
                  previous_pct = completion_pct)
      message("Prior refresh: ", basename(candidate))
      break
    }
  }
}
if (nrow(previous) == 0) {
  message("No earlier archived refresh with SY", school_year,
          ". Showing current snapshot only.")
}

# Archive the actual CSV bytes, without silently overwriting a changed file
# for the same DataAsOf date. This guards against ambiguous comparisons.
snapshot_file <- file.path(
  SNAPSHOT_DIR, paste0("fafsa_completion_", as_of, ".csv")
)
if (file.exists(snapshot_file)) {
  if (unname(tools::md5sum(snapshot_file)) != unname(tools::md5sum(APP_CSV))) {
    stop("An archive already exists for ", as_of,
         " but its contents differ. Investigate before continuing.")
  }
} else if (!file.copy(APP_CSV, snapshot_file)) {
  stop("Could not save a dated snapshot: ", snapshot_file)
}

# left_join() attaches each school's earlier rate to the CURRENT rows.
# If no earlier extract exists, previous_pct stays NA and the email explains
# that no comparison is available. Difference is in PERCENTAGE POINTS.
current <- current %>%
  left_join(previous, by = "SchoolCode") %>%
  mutate(change_pp = completion_pct - previous_pct)

# ==== 4. USE LAST YEAR'S REVIEWED EMAIL ROSTER ================================
# read_excel() loads the pruned roster; select only needed contact fields.
# distinct() removes duplicate SCHOOL + EMAIL pairs (case-insensitively).
# Only this roster decides who receives an email. Never auto-add schools.
# Match by SchoolName; the dashboard's DistrictName remains authoritative
# for reporting and can differ from last year's roster LEA name.
roster <- readxl::read_excel(ROSTER_XLSX) %>%
  transmute(
    SchoolName = stringr::str_trim(as.character(SchoolName)),
    WorkEmail = stringr::str_trim(as.character(WorkEmail)),
    FirstName = as.character(FirstName),
    LastName = as.character(LastName),
    PositionName = as.character(PositionName)
  ) %>%
  filter(!is.na(SchoolName), SchoolName != "",
         !is.na(WorkEmail), WorkEmail != "") %>%
  mutate(EmailKey = str_to_lower(WorkEmail)) %>%
  distinct(SchoolName, EmailKey, .keep_all = TRUE) %>%
  select(-EmailKey)

# anti_join() returns roster schools WITHOUT a match in the current data.
# A mismatch stops the workflow rather than silently losing a recipient.
unmatched_roster <- roster %>%
  distinct(SchoolName) %>%
  anti_join(current %>% select(SchoolName), by = "SchoolName")
readr::write_csv(unmatched_roster, file.path(OUTPUT_DIR, "unmatched_roster_schools.csv"))
if (nrow(unmatched_roster) > 0) {
  stop("Some roster schools do not match the current dashboard. See output/unmatched_roster_schools.csv")
}

# The reverse anti_join() lists dashboard schools with NO approved recipients.
# They are reported for review but remain excluded from emails.
unlisted_schools <- current %>%
  anti_join(roster %>% distinct(SchoolName), by = "SchoolName") %>%
  select(SchoolCode, SchoolName, DistrictName)
readr::write_csv(unlisted_schools, file.path(OUTPUT_DIR, "schools_without_roster.csv"))

# Check the actual recipients before turning on live sending. This output
# contains staff email addresses and MUST remain local/private.
readr::write_csv(
  roster %>% arrange(SchoolName, LastName, FirstName),
  file.path(OUTPUT_DIR, "roster_review.csv")
)

# inner_join() keeps only schools that appear in BOTH the data and roster.
# count() shows the number of recipients without duplicating a school's rate.
mailing <- current %>%
  inner_join(roster %>% count(SchoolName, name = "n_recipients"),
             by = "SchoolName") %>%
  arrange(DistrictName, SchoolName)

readr::write_csv(
  mailing %>%
    select(DataAsOf, SchoolCode, SchoolName, DistrictName, seniors, completed,
           completion_pct, previous_as_of, previous_pct, change_pp, n_recipients),
  file.path(OUTPUT_DIR, "recipient_review.csv")
)

message("Refresh date: ", as_of, " | School year: ", school_year)
message("Recipient schools: ", nrow(mailing), " | Recipient rows: ", nrow(roster))
message("Schools not on roster (excluded): ", nrow(unlisted_schools))
message("Review: ", file.path(OUTPUT_DIR, "recipient_review.csv"))
message("Review contacts: ", file.path(OUTPUT_DIR, "roster_review.csv"))

# ==== 5. BUILD AN EMAIL FROM THE APPROVED LAYOUT =============================
# This step converts one row of school data into a complete HTML email.
# make_email_html() is a regular R function, NOT a Shiny reactive expression.
# The layout details live in email_layout.R so the data steps stay readable.
logo_src <- base64enc::dataURI(file = LOGO_FILE, mime = "image/png")

make_email_html <- function(one_school) {
  # one_school is a one-row tibble; p holds that school's values.
  p <- one_school[1, ]
  previous_date <- if (is.na(p$previous_as_of)) "" else fmt_date(p$previous_as_of)
  previous_rate <- if (is.na(p$previous_pct)) "" else fmt_pct(p$previous_pct)

  snapshot <- build_snapshot_table(
    lea_name = p$SchoolName,
    as_of_current = fmt_date(p$DataAsOf),
    pct_current = fmt_pct(p$completion_pct),
    as_of_previous = previous_date,
    pct_previous = previous_rate
  )

  build_email_body(
    lea_name = p$SchoolName,
    snapshot_block = snapshot,
    logo_src = logo_src,
    dashboard_url = DASHBOARD_URL,
    support_booking_url = BOOKING_URL,
    contact_email = CONTACT_EMAIL
  )
}

# A preview uses the chosen school (or the first matched school if unavailable).
# writeLines() saves the HTML file; it does not send an Outlook message.
preview_row <- mailing %>% filter(SchoolName == PREVIEW_SCHOOL)
if (nrow(preview_row) == 0) preview_row <- mailing %>% slice(1)
preview_html <- paste0(
  "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'>",
  "<title>FAFSA Email Preview</title></head>",
  "<body style='background:white;padding:30px;font-family:Arial,sans-serif;'>",
  make_email_html(preview_row), "</body></html>"
)
writeLines(preview_html, file.path(OUTPUT_DIR, "preview_email.html"), useBytes = TRUE)
message("Preview: ", file.path(OUTPUT_DIR, "preview_email.html"))

# ==== 6. SEND ONLY WHEN REQUESTED ============================================
# Everything above runs in ALL modes; only this branch contacts Outlook.
# preview: return after writing local outputs (safe default).
# test: send one sample to TEST_EMAIL, never the school mailing list.
# send: require approval + a typed SEND confirmation before bulk delivery.
if (MODE == "preview") {
  message("PREVIEW ONLY. No emails were sent.")
} else {
  if (!requireNamespace("Microsoft365R", quietly = TRUE)) {
    stop("Install Microsoft365R before using test/send mode.")
  }
  if (MODE == "test" && !nzchar(TEST_EMAIL)) {
    stop("Set TEST_EMAIL to your own address before test mode.")
  }
  if (MODE == "send") {
    if (!SEND_APPROVED) {
      stop("Live sending is disabled. Review all recipients and set SEND_APPROVED <- TRUE.")
    }
    if (!interactive()) {
      stop("Bulk sending requires an interactive RStudio session.")
    }
    answer <- readline(paste0("Send ", nrow(mailing),
                             " school emails for SY", school_year, "? Type SEND: "))
    if (answer != "SEND") stop("Sending cancelled.")
  }

  outlook <- Microsoft365R::get_business_outlook()
  send_log_path <- file.path(OUTPUT_DIR, paste0("send_log_", as_of, ".csv"))
  if (file.exists(send_log_path)) {
    send_log <- readr::read_csv(send_log_path, show_col_types = FALSE)
  } else {
    send_log <- tibble(SchoolCode = character(), SchoolName = character(),
                       sent_at = character(), status = character())
  }

  # for() processes one school at a time; the school-specific addresses are
  # looked up from the reviewed roster immediately before each send.
  to_send <- if (MODE == "test") preview_row else mailing
  for (i in seq_len(nrow(to_send))) {
    school <- to_send[i, ]
    if (MODE == "send" && any(send_log$SchoolCode == school$SchoolCode &
                                send_log$status == "sent", na.rm = TRUE)) next

    addresses <- if (MODE == "test") {
      TEST_EMAIL
    } else {
      roster %>% filter(SchoolName == school$SchoolName) %>%
        pull(WorkEmail) %>% unique()
    }
    if (length(addresses) == 0) stop("No TO recipients for ", school$SchoolName)
    cc <- if (MODE == "test" || !nzchar(ALWAYS_CC)) NULL else ALWAYS_CC

    # tryCatch() records an Outlook error without ending the whole mailing.
    # The send log is written after EACH school, so a rerun can skip schools
    # already marked "sent" for this refresh. Review failures before retrying.
    status <- tryCatch({
      outlook$create_email(
        to = addresses,
        cc = cc,
        subject = EMAIL_SUBJECT,
        body = make_email_html(school),
        content_type = "html"
      )$send()
      if (MODE == "test") "test_sent" else "sent"
    }, error = function(e) {
      warning("Email failed for ", school$SchoolName, ": ", conditionMessage(e))
      "failed"
    })

    send_log <- bind_rows(send_log, tibble(
      SchoolCode = school$SchoolCode,
      SchoolName = school$SchoolName,
      sent_at = as.character(Sys.time()),
      status = status
    ))
    readr::write_csv(send_log, send_log_path)
  }
  message("Send log: ", send_log_path)
}

# =============================================================================
# FAFSA SHINY APP: SHARED SETUP
#
# Shiny loads global.R once when the app starts. Use it for objects that are
# shared by both ui.R and server.R: packages, data, startup checks, labels,
# choices, colors, and reusable functions.
#
# A helpful reading order for this project is:
#
# global.R -> ui.R -> server.R -> R/analysis.R -> R/plot.R
#
# The app's data flow is:
# summarized CSV -> user inputs -> filtered data -> analysis -> chart
# =============================================================================


# ==== PACKAGES ====

library(shiny)
library(bslib)
library(tidyverse)
library(scales)


# ==== APP LABELS AND TEXT (EDIT HERE) ====

# >>> EDIT HERE >>>
# Start here for simple wording changes that are reused across the app.
APP_TITLE <- "FAFSA Completion"

LABELS <- 
  list(
    year = "School year",
    lea = "LEA",
    school = "School"
  )
# <<< END EDIT <<<


# ==== DATA INPUT (EDIT HERE) ====

# >>> EDIT HERE >>>
# The deployed app reads one summarized, app-ready file.
# Create this file from the validated production FAFSA SQL workflow, then
# replace it here before redeploying the app.
APP_DATA_PATH <- file.path("input_data", "fafsa_completion.csv")

if (!file.exists(APP_DATA_PATH)) {
  stop(
    paste0(
      "Missing app input: ", APP_DATA_PATH, ". ",
      "Create the summarized FAFSA production extract, save it at this path, ",
      "and restart the app."
    )
  )
}

APP_DATA <- 
  read_csv(
    APP_DATA_PATH,
    na = c("", "NA", "NULL"),
    show_col_types = FALSE,
    col_types = cols(
      DataAsOf = col_date(),
      EnrollmentAsOf = col_date(),
      level = col_character(),
      SchoolYear = col_integer(),
      DistrictCode = col_character(),
      DistrictName = col_character(),
      SchoolCode = col_character(),
      SchoolName = col_character(),
      ApplicationReceiptMonth = col_date(),
      seniors = col_double(),
      completed_this_month = col_double()
    )
  )
# <<< END EDIT <<<


# ==== STARTUP CHECKS ====

# These checks protect the handoff from the production extract to Shiny.
# They are intentionally lightweight. Source-data QA/QC is handled outside the
# deployed app.
REQUIRED_COLUMNS <- 
  c(
    "DataAsOf",
    "EnrollmentAsOf",
    "level",
    "SchoolYear",
    "DistrictCode",
    "DistrictName",
    "SchoolCode",
    "SchoolName",
    "ApplicationReceiptMonth",
    "seniors",
    "completed_this_month"
  )

missing_columns <- setdiff(REQUIRED_COLUMNS, names(APP_DATA))

if (length(missing_columns) > 0) {
  stop(
    paste(
      "The FAFSA app input is missing required columns:",
      paste(missing_columns, collapse = ", ")
    )
  )
}

if (nrow(APP_DATA) == 0) {
  stop("The FAFSA app input contains no reporting rows.")
}

if (!setequal(unique(APP_DATA$level), c("school", "lea", "state"))) {
  stop("The FAFSA app input must contain school, lea, and state reporting rows.")
}

# The senior denominator should stay constant across monthly rows for the same
# reporting entity and school year.
entity_check <- 
  APP_DATA %>%
  group_by(level, SchoolYear, DistrictCode, SchoolCode) %>%
  summarise(
    denominators = n_distinct(seniors),
    .groups = "drop"
  )

if (any(entity_check$denominators != 1)) {
  stop("Each reporting entity must have one stable senior denominator.")
}

# The production extract contains only observed FAFSA receipt months. Within an
# entity/year, each observed month should appear at most once. A missing month
# is allowed only for a denominator-only entity with zero completions.
duplicate_month_check <- 
  APP_DATA %>%
  filter(!is.na(ApplicationReceiptMonth)) %>%
  count(
    level,
    SchoolYear,
    DistrictCode,
    SchoolCode,
    ApplicationReceiptMonth,
    name = "rows"
  ) %>%
  filter(rows > 1)

if (nrow(duplicate_month_check) > 0) {
  stop("The FAFSA app input has duplicate reporting-entity/month rows.")
}

invalid_null_month <- 
  APP_DATA %>%
  filter(
    is.na(ApplicationReceiptMonth),
    completed_this_month != 0
  )

if (nrow(invalid_null_month) > 0) {
  stop("Rows with a missing receipt month must have zero completions.")
}


# ==== OBSERVED MONTH SPANS ====

# SQL preserves the receipt months that actually occur in the source data.
# For each SchoolYear, store the statewide first and last observed months.
# R/analysis.R uses this to build a continuous sequence for the chart and to
# fill unobserved months with zero completions.
SCHOOL_YEAR_MONTH_SPANS <- 
  APP_DATA %>%
  filter(!is.na(ApplicationReceiptMonth)) %>%
  group_by(SchoolYear) %>%
  summarise(
    first_month = min(ApplicationReceiptMonth),
    last_month = max(ApplicationReceiptMonth),
    .groups = "drop"
  )


# ==== CURRENT-SCHOOL DISPLAY RULE ====

# APP_DATA keeps historical schools so historical LEA and State totals remain
# complete. The dropdowns, however, should offer only schools that exist in the
# latest included school year.
LATEST_SCHOOL_YEAR <- max(APP_DATA$SchoolYear, na.rm = TRUE)

CURRENT_SCHOOL_KEYS <- 
  APP_DATA %>%
  filter(
    level == "school",
    SchoolYear == LATEST_SCHOOL_YEAR
  ) %>%
  distinct(DistrictCode, SchoolCode)


# ==== ANALYSIS FUNCTIONS ====

# source() makes the functions in R/analysis.R available to global.R,
# server.R, and ui.R. Source this file before building the opening filter
# choices because current_school_rows() is defined there.
source(file.path("R", "analysis.R"))


# ==== OPENING FILTER CHOICES (EDIT HERE) ====

# >>> EDIT HERE >>>
# ui.R uses these values when it first draws the three dropdowns.
YEAR_CHOICES <- 
  APP_DATA %>%
  distinct(SchoolYear) %>%
  pull(SchoolYear) %>%
  sort()

LEA_CHOICES <- 
  current_school_rows(APP_DATA) %>%
  filter(SchoolYear == max(YEAR_CHOICES)) %>%
  distinct(DistrictName) %>%
  pull(DistrictName) %>%
  sort()

SCHOOL_CHOICES <- 
  current_school_rows(APP_DATA) %>%
  filter(
    SchoolYear == max(YEAR_CHOICES),
    DistrictName == LEA_CHOICES[[1]]
  ) %>%
  distinct(SchoolName) %>%
  pull(SchoolName) %>%
  sort()
# <<< END EDIT <<<


# ==== OPENING SELECTIONS (EDIT HERE) ====

# >>> EDIT HERE >>>
# These values control what the user sees when the app first opens.
DEFAULTS <- 
  list(
    year = max(YEAR_CHOICES),
    lea = LEA_CHOICES[[1]],
    school = SCHOOL_CHOICES[[1]]
  )
# <<< END EDIT <<<


# ==== THEME PALETTE (EDIT HERE) ====

# >>> EDIT HERE >>>
# Shared DDOE colors used by both ui.R and R/plot.R.
dde_blue <- "#194a78"
dde_blue_dark <- "#123758"
dde_orange <- "#d98b00"
dde_orange_soft <- "#fff7ea"
dde_bg <- "#f5f7fb"
dde_surface <- "#ffffff"
dde_surface_soft <- "#fbfcfe"
dde_border <- "#d8e2ec"
dde_border_strong <- "#c7d5e2"
dde_text <- "#1f2937"
dde_muted <- "#5b6875"
# <<< END EDIT <<<


# ==== PLOT FUNCTIONS ====

# The plotting functions depend on the shared colors above, so source plot.R
# after the palette is defined.
source(file.path("R", "plot.R"))

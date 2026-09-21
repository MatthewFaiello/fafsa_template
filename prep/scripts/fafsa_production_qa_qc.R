# =============================================================================
# FAFSA PRODUCTION QA / QC
#
# PURPOSE
# -------
# Validate the final single-query FAFSA production extract before it becomes the
# Shiny app source.
#
# This script checks the production aggregate itself. It does NOT use or depend
# on the temporary two-extract R bridge.
#
# EXPECTED INPUT
# --------------
# input_data/fafsa_completion.csv
#
# EXPECTED COLUMNS
# ----------------
# DataAsOf
# EnrollmentAsOf
# level
# SchoolYear
# DistrictCode
# DistrictName
# SchoolCode
# SchoolName
# ApplicationReceiptMonth
# seniors
# completed_this_month
#
# VALIDATION AREAS
# ----------------
# 1. Required columns and basic parsing
# 2. Duplicate reporting keys
# 3. Denominator stability
# 4. Completion bounds
# 5. School -> LEA rollup reconciliation
# 6. LEA -> State rollup reconciliation
# 7. Charter reporting hierarchy
# 8. Zero-completion entities retained
# 9. Observed FAFSA receipt-month structure
# 10. Historical year coverage
# 11. Enrollment snapshot review
# 12. Final PASS / REVIEW summary
#
# OUTPUTS
# -------
# prep/validation/production_qa_school_lea_differences.csv
# prep/validation/production_qa_lea_state_differences.csv
# prep/validation/production_qa_month_spans.csv
# prep/validation/production_qa_year_summary.csv
#
# IMPORTANT
# ---------
# This script uses aggregate data only. No student-level FAFSA records are
# written to disk.
# =============================================================================


library(tidyverse)
library(lubridate)


# ==== 1. FILE PATHS ==========================================================

INPUT_PATH <- file.path(
  "input_data",
  "fafsa_completion.csv"
)

VALIDATION_DIR <- file.path(
  "prep",
  "validation"
)

SCHOOL_LEA_DIFF_PATH <- file.path(
  VALIDATION_DIR,
  "production_qa_school_lea_differences.csv"
)

LEA_STATE_DIFF_PATH <- file.path(
  VALIDATION_DIR,
  "production_qa_lea_state_differences.csv"
)

MONTH_SPAN_PATH <- file.path(
  VALIDATION_DIR,
  "production_qa_month_spans.csv"
)

YEAR_SUMMARY_PATH <- file.path(
  VALIDATION_DIR,
  "production_qa_year_summary.csv"
)


# ==== 2. SMALL HELPERS =======================================================

if (!file.exists(INPUT_PATH)) {
  stop(
    "Missing production FAFSA file: ",
    INPUT_PATH,
    call. = FALSE
  )
}

dir.create(
  VALIDATION_DIR,
  recursive = TRUE,
  showWarnings = FALSE
)


parse_flexible_date <- function(x, field_name) {

  raw <- str_trim(as.character(x))
  raw[raw %in% c("", "NA", "NULL")] <- NA_character_

  parsed <- suppressWarnings(
    ymd(raw, quiet = TRUE)
  )

  remaining <- !is.na(raw) & is.na(parsed)

  if (any(remaining)) {
    parsed[remaining] <- suppressWarnings(
      mdy(raw[remaining], quiet = TRUE)
    )
  }

  bad <- !is.na(raw) & is.na(parsed)

  if (any(bad)) {

    examples <- paste(
      head(unique(raw[bad]), 10),
      collapse = ", "
    )

    stop(
      "Could not parse ",
      field_name,
      ". Example value(s): ",
      examples,
      call. = FALSE
    )
  }

  parsed
}


check_required_columns <- function(data, required) {

  missing <- setdiff(
    required,
    names(data)
  )

  if (length(missing) > 0) {

    stop(
      "Production file is missing required column(s): ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
}


# ==== 3. READ PRODUCTION OUTPUT ==============================================

raw <-
  read_csv(
    INPUT_PATH,
    na = c("", "NA", "NULL"),
    show_col_types = FALSE,
    col_types = cols(.default = col_character())
  )


required_columns <- c(
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


check_required_columns(
  raw,
  required_columns
)


fafsa <-
  raw %>%
  transmute(
    DataAsOf = parse_flexible_date(
      DataAsOf,
      "DataAsOf"
    ),
    EnrollmentAsOf = parse_flexible_date(
      EnrollmentAsOf,
      "EnrollmentAsOf"
    ),
    level = str_to_lower(
      str_trim(level)
    ),
    SchoolYear = parse_integer(
      SchoolYear
    ),
    DistrictCode = str_trim(
      DistrictCode
    ),
    DistrictName = str_squish(
      DistrictName
    ),
    SchoolCode = str_trim(
      SchoolCode
    ),
    SchoolName = str_squish(
      SchoolName
    ),
    ApplicationReceiptMonth = parse_flexible_date(
      ApplicationReceiptMonth,
      "ApplicationReceiptMonth"
    ),
    seniors = parse_integer(
      seniors
    ),
    completed_this_month = parse_integer(
      completed_this_month
    )
  )


# ==== 4. BASIC FILE QA =======================================================

cat("\nFAFSA PRODUCTION QA / QC\n")
cat("========================\n")

cat(
  "Rows: ",
  format(nrow(fafsa), big.mark = ","),
  "\n",
  sep = ""
)

cat(
  "School years: ",
  paste(
    sort(unique(fafsa$SchoolYear)),
    collapse = ", "
  ),
  "\n",
  sep = ""
)

cat(
  "DataAsOf value(s): ",
  paste(
    sort(unique(fafsa$DataAsOf)),
    collapse = ", "
  ),
  "\n",
  sep = ""
)


valid_levels <- c(
  "school",
  "lea",
  "state"
)

unexpected_levels <-
  fafsa %>%
  filter(
    !level %in% valid_levels |
      is.na(level)
  )

cat(
  "Rows with unexpected reporting level: ",
  nrow(unexpected_levels),
  "\n",
  sep = ""
)


# ==== 5. DUPLICATE REPORTING KEYS ===========================================

key <- c(
  "level",
  "SchoolYear",
  "DistrictCode",
  "SchoolCode",
  "ApplicationReceiptMonth"
)


duplicate_keys <-
  fafsa %>%
  count(
    across(all_of(key)),
    name = "rows"
  ) %>%
  filter(
    rows > 1
  )


cat(
  "Duplicate reporting keys: ",
  nrow(duplicate_keys),
  "\n",
  sep = ""
)


# ==== 6. DENOMINATOR STABILITY ==============================================

denominator_stability <-
  fafsa %>%
  group_by(
    level,
    SchoolYear,
    DistrictCode,
    SchoolCode
  ) %>%
  summarise(
    denominator_values = n_distinct(
      seniors
    ),
    .groups = "drop"
  )


unstable_denominators <-
  denominator_stability %>%
  filter(
    denominator_values > 1
  )


cat(
  "Entities with changing denominators across months: ",
  nrow(unstable_denominators),
  "\n",
  sep = ""
)


# ==== 7. COMPLETION BOUNDS ===================================================

entity_totals <-
  fafsa %>%
  group_by(
    level,
    SchoolYear,
    DistrictCode,
    DistrictName,
    SchoolCode,
    SchoolName
  ) %>%
  summarise(
    seniors = first(seniors),
    completed_fafsa = sum(
      completed_this_month,
      na.rm = TRUE
    ),
    .groups = "drop"
  )


completion_bound_problems <-
  entity_totals %>%
  filter(
    completed_fafsa > seniors |
      completed_fafsa < 0 |
      seniors < 0
  )


cat(
  "Entities with invalid completion bounds: ",
  nrow(completion_bound_problems),
  "\n",
  sep = ""
)


# ==== 8. SCHOOL -> LEA ROLLUP ================================================

# School rows are summed after the production query has already applied the
# reporting hierarchy. Therefore Charter School of Wilmington and Delaware
# Military Academy should naturally roll into their own LEAs here.

school_rollup <-
  entity_totals %>%
  filter(
    level == "school"
  ) %>%
  group_by(
    SchoolYear,
    DistrictCode,
    DistrictName
  ) %>%
  summarise(
    school_seniors = sum(
      seniors,
      na.rm = TRUE
    ),
    school_completed = sum(
      completed_fafsa,
      na.rm = TRUE
    ),
    .groups = "drop"
  )


lea_reported <-
  entity_totals %>%
  filter(
    level == "lea"
  ) %>%
  transmute(
    SchoolYear,
    DistrictCode,
    DistrictName,
    lea_seniors = seniors,
    lea_completed = completed_fafsa
  )


school_lea_check <-
  full_join(
    school_rollup,
    lea_reported,
    by = c(
      "SchoolYear",
      "DistrictCode",
      "DistrictName"
    )
  ) %>%
  mutate(
    seniors_difference =
      coalesce(school_seniors, 0L) -
      coalesce(lea_seniors, 0L),

    completed_difference =
      coalesce(school_completed, 0L) -
      coalesce(lea_completed, 0L),

    exact_match =
      seniors_difference == 0 &
      completed_difference == 0
  )


school_lea_differences <-
  school_lea_check %>%
  filter(
    !exact_match
  )


cat(
  "School -> LEA rollup differences: ",
  nrow(school_lea_differences),
  "\n",
  sep = ""
)


write_csv(
  school_lea_differences,
  SCHOOL_LEA_DIFF_PATH,
  na = ""
)


# ==== 9. LEA -> STATE ROLLUP =================================================

lea_rollup <-
  entity_totals %>%
  filter(
    level == "lea"
  ) %>%
  group_by(
    SchoolYear
  ) %>%
  summarise(
    lea_seniors = sum(
      seniors,
      na.rm = TRUE
    ),
    lea_completed = sum(
      completed_fafsa,
      na.rm = TRUE
    ),
    .groups = "drop"
  )


state_reported <-
  entity_totals %>%
  filter(
    level == "state"
  ) %>%
  transmute(
    SchoolYear,
    state_seniors = seniors,
    state_completed = completed_fafsa
  )


lea_state_check <-
  full_join(
    lea_rollup,
    state_reported,
    by = "SchoolYear"
  ) %>%
  mutate(
    seniors_difference =
      coalesce(lea_seniors, 0L) -
      coalesce(state_seniors, 0L),

    completed_difference =
      coalesce(lea_completed, 0L) -
      coalesce(state_completed, 0L),

    exact_match =
      seniors_difference == 0 &
      completed_difference == 0
  )


lea_state_differences <-
  lea_state_check %>%
  filter(
    !exact_match
  )


cat(
  "LEA -> State rollup differences: ",
  nrow(lea_state_differences),
  "\n",
  sep = ""
)


write_csv(
  lea_state_differences,
  LEA_STATE_DIFF_PATH,
  na = ""
)


# ==== 10. CHARTER REPORTING HIERARCHY =======================================

charter_expectations <-
  tribble(
    ~SchoolCode, ~ExpectedDistrictCode, ~ExpectedDistrictName,
    "295",       "70",                  "Charter School of Wilmington",
    "578",       "79",                  "Delaware Military Academy"
  )


charter_school_rows <-
  fafsa %>%
  filter(
    level == "school",
    SchoolCode %in% charter_expectations$SchoolCode
  ) %>%
  distinct(
    SchoolYear,
    DistrictCode,
    DistrictName,
    SchoolCode,
    SchoolName
  )


charter_problems <-
  charter_school_rows %>%
  inner_join(
    charter_expectations,
    by = "SchoolCode"
  ) %>%
  filter(
    DistrictCode != ExpectedDistrictCode |
      DistrictName != ExpectedDistrictName
  )


cat(
  "Charter reporting-hierarchy mismatches: ",
  nrow(charter_problems),
  "\n",
  sep = ""
)


# Confirm the old Red Clay assignment does not remain.

charter_red_clay_problems <-
  charter_school_rows %>%
  filter(
    DistrictCode == "32"
  )


cat(
  "CSoW / DMA rows still assigned to Red Clay: ",
  nrow(charter_red_clay_problems),
  "\n",
  sep = ""
)


# ==== 11. ZERO-COMPLETION ENTITIES ==========================================

# An entity with no completed FAFSA records should still appear with its
# denominator and a NULL receipt month / zero monthly completions row.

zero_completion_entities <-
  entity_totals %>%
  filter(
    completed_fafsa == 0
  )


zero_completion_structure <-
  zero_completion_entities %>%
  left_join(
    fafsa %>%
      group_by(
        level,
        SchoolYear,
        DistrictCode,
        SchoolCode
      ) %>%
      summarise(
        rows = n(),
        null_month_rows = sum(
          is.na(ApplicationReceiptMonth)
        ),
        nonzero_month_rows = sum(
          completed_this_month > 0,
          na.rm = TRUE
        ),
        .groups = "drop"
      ),
    by = c(
      "level",
      "SchoolYear",
      "DistrictCode",
      "SchoolCode"
    )
  )


zero_completion_problems <-
  zero_completion_structure %>%
  filter(
    rows != 1 |
      null_month_rows != 1 |
      nonzero_month_rows != 0
  )


cat(
  "Zero-completion entities: ",
  nrow(zero_completion_entities),
  "\n",
  sep = ""
)

cat(
  "Zero-completion entities with unexpected structure: ",
  nrow(zero_completion_problems),
  "\n",
  sep = ""
)


# ==== 12. NULL-MONTH ROWS WITH COMPLETIONS ==================================

null_month_completion_problems <-
  fafsa %>%
  filter(
    is.na(ApplicationReceiptMonth),
    completed_this_month != 0
  )


cat(
  "NULL receipt-month rows with nonzero completions: ",
  nrow(null_month_completion_problems),
  "\n",
  sep = ""
)


# ==== 13. OBSERVED FAFSA RECEIPT-MONTH STRUCTURE =============================

# This is intentionally descriptive rather than prescriptive.
#
# We do NOT require a fixed October-June or August-July FAFSA window.
# Instead we verify that each SchoolYear preserves its actual observed months.

month_spans <-
  fafsa %>%
  filter(
    level == "state"
  ) %>%
  group_by(
    SchoolYear
  ) %>%
  summarise(
    first_receipt_month = if (
      all(is.na(ApplicationReceiptMonth))
    ) {
      as.Date(NA)
    } else {
      min(
        ApplicationReceiptMonth,
        na.rm = TRUE
      )
    },

    last_receipt_month = if (
      all(is.na(ApplicationReceiptMonth))
    ) {
      as.Date(NA)
    } else {
      max(
        ApplicationReceiptMonth,
        na.rm = TRUE
      )
    },

    observed_receipt_months = n_distinct(
      ApplicationReceiptMonth[
        !is.na(ApplicationReceiptMonth)
      ]
    ),

    .groups = "drop"
  ) %>%
  arrange(
    SchoolYear
  )


write_csv(
  month_spans,
  MONTH_SPAN_PATH,
  na = ""
)


cat("\nOBSERVED STATEWIDE FAFSA MONTH SPANS\n")
cat("====================================\n")

print(
  month_spans,
  n = Inf
)


# ==== 14. MONTH TOTALS RECONCILE ACROSS LEVELS ===============================

# For every year/month:
#   sum of School completions
#   = sum of LEA completions
#   = State completions

monthly_level_totals <-
  fafsa %>%
  filter(
    !is.na(ApplicationReceiptMonth)
  ) %>%
  group_by(
    level,
    SchoolYear,
    ApplicationReceiptMonth
  ) %>%
  summarise(
    completed = sum(
      completed_this_month,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = level,
    values_from = completed,
    values_fill = 0
  ) %>%
  mutate(
    school_lea_match =
      school == lea,

    lea_state_match =
      lea == state
  )


monthly_rollup_problems <-
  monthly_level_totals %>%
  filter(
    !school_lea_match |
      !lea_state_match
  )


cat(
  "\nMonthly School / LEA / State completion rollup differences: ",
  nrow(monthly_rollup_problems),
  "\n",
  sep = ""
)


# ==== 15. HISTORICAL YEAR COVERAGE ==========================================

year_coverage <-
  fafsa %>%
  distinct(
    SchoolYear
  ) %>%
  arrange(
    SchoolYear
  )


expected_years <-
  seq(
    min(fafsa$SchoolYear, na.rm = TRUE),
    max(fafsa$SchoolYear, na.rm = TRUE)
  )


missing_years <-
  setdiff(
    expected_years,
    year_coverage$SchoolYear
  )


cat(
  "Missing SchoolYears within observed range: ",
  ifelse(
    length(missing_years) == 0,
    "none",
    paste(missing_years, collapse = ", ")
  ),
  "\n",
  sep = ""
)


# ==== 16. ENROLLMENT SNAPSHOT REVIEW ========================================

snapshot_review <-
  fafsa %>%
  distinct(
    SchoolYear,
    EnrollmentAsOf
  ) %>%
  arrange(
    SchoolYear,
    EnrollmentAsOf
  )


multiple_snapshots <-
  snapshot_review %>%
  count(
    SchoolYear,
    name = "snapshot_dates"
  ) %>%
  filter(
    snapshot_dates > 1
  )


cat(
  "SchoolYears with multiple EnrollmentAsOf values: ",
  nrow(multiple_snapshots),
  "\n",
  sep = ""
)


cat("\nENROLLMENT SNAPSHOTS\n")
cat("====================\n")

print(
  snapshot_review,
  n = Inf
)


# ==== 17. YEAR-LEVEL SUMMARY =================================================

year_summary <-
  entity_totals %>%
  filter(
    level == "state"
  ) %>%
  select(
    SchoolYear,
    seniors,
    completed_fafsa
  ) %>%
  left_join(
    month_spans,
    by = "SchoolYear"
  ) %>%
  mutate(
    completion_rate = if_else(
      seniors > 0,
      completed_fafsa / seniors,
      NA_real_
    )
  ) %>%
  select(
    SchoolYear,
    seniors,
    completed_fafsa,
    completion_rate,
    first_receipt_month,
    last_receipt_month,
    observed_receipt_months
  ) %>%
  arrange(
    SchoolYear
  )


write_csv(
  year_summary,
  YEAR_SUMMARY_PATH,
  na = ""
)


cat("\nSTATEWIDE YEAR SUMMARY\n")
cat("======================\n")

print(
  year_summary,
  n = Inf
)


# ==== 18. KNOWN SCHOOL-LEVEL BENCHMARKS ======================================

# These are aggregate benchmarks already validated directly against the existing
# FAFSA_Completers_SchoolLevel stored procedure.
#
# They are intentionally small spot checks rather than a second production data
# source.

known_benchmarks <-
  tribble(
    ~SchoolYear, ~SchoolCode, ~ExpectedSeniors, ~ExpectedCompleted,
    2026L,       "585",       94L,              59L,
    2023L,       "585",       71L,              48L
  )


benchmark_check <-
  entity_totals %>%
  filter(
    level == "school"
  ) %>%
  select(
    SchoolYear,
    SchoolCode,
    SchoolName,
    seniors,
    completed_fafsa
  ) %>%
  inner_join(
    known_benchmarks,
    by = c(
      "SchoolYear",
      "SchoolCode"
    )
  ) %>%
  mutate(
    seniors_match =
      seniors == ExpectedSeniors,

    completed_match =
      completed_fafsa == ExpectedCompleted,

    exact_match =
      seniors_match &
      completed_match
  )


benchmark_problems <-
  benchmark_check %>%
  filter(
    !exact_match
  )


cat(
  "\nKnown SchoolLevel benchmark differences: ",
  nrow(benchmark_problems),
  "\n",
  sep = ""
)


print(
  benchmark_check,
  n = Inf
)


# ==== 19. FINAL QA / QC STATUS ===============================================

all_checks_pass <-
  nrow(unexpected_levels) == 0 &&
  nrow(duplicate_keys) == 0 &&
  nrow(unstable_denominators) == 0 &&
  nrow(completion_bound_problems) == 0 &&
  nrow(school_lea_differences) == 0 &&
  nrow(lea_state_differences) == 0 &&
  nrow(charter_problems) == 0 &&
  nrow(charter_red_clay_problems) == 0 &&
  nrow(zero_completion_problems) == 0 &&
  nrow(null_month_completion_problems) == 0 &&
  nrow(monthly_rollup_problems) == 0 &&
  length(missing_years) == 0 &&
  nrow(multiple_snapshots) == 0 &&
  nrow(benchmark_problems) == 0


cat("\nFINAL QA / QC STATUS\n")
cat("====================\n")


if (all_checks_pass) {

  cat(
    "PASS: Production FAFSA aggregate passed all structural and reconciliation checks.\n"
  )

  cat(
    "The cross-database SQL output is ready to serve as the Shiny app source.\n"
  )

} else {

  cat(
    "REVIEW: One or more production QA / QC checks require review.\n"
  )

  cat("\nChecks requiring review:\n")

  review_flags <- tibble(
    check = c(
      "Unexpected reporting levels",
      "Duplicate reporting keys",
      "Unstable denominators",
      "Invalid completion bounds",
      "School -> LEA rollup",
      "LEA -> State rollup",
      "Charter hierarchy",
      "Charters still under Red Clay",
      "Zero-completion structure",
      "NULL month with completion",
      "Monthly rollup",
      "Missing SchoolYears",
      "Multiple EnrollmentAsOf values",
      "Known SchoolLevel benchmarks"
    ),
    problems = c(
      nrow(unexpected_levels),
      nrow(duplicate_keys),
      nrow(unstable_denominators),
      nrow(completion_bound_problems),
      nrow(school_lea_differences),
      nrow(lea_state_differences),
      nrow(charter_problems),
      nrow(charter_red_clay_problems),
      nrow(zero_completion_problems),
      nrow(null_month_completion_problems),
      nrow(monthly_rollup_problems),
      length(missing_years),
      nrow(multiple_snapshots),
      nrow(benchmark_problems)
    )
  ) %>%
    filter(
      problems > 0
    )

  print(
    review_flags,
    n = Inf
  )
}

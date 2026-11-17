# =============================================================================
# FAFSA APP: ANALYSIS FUNCTIONS
#
# These are ordinary R functions, not Shiny reactives. server.R decides *when*
# they run; this file defines *what the analysis does*.
#
# The main calculation is:
#
# selected School / LEA / State rows
#                 ↓
# continuous month sequence for the selected SchoolYear
#                 ↓
# fill missing monthly counts with zero
#                 ↓
# cumulative completed FAFSAs
#                 ↓
# cumulative completion rate
# =============================================================================


# ==== LABEL HELPERS ====

school_year_label <- 
  function(year) {
    paste0(year - 1, "\u2013", year - 2000)
  }


month_name <- 
  function(x) {
    format(x, "%B")
  }


# ==== MONTH-SEQUENCE HELPER ====

# The production extract contains only months that were actually observed.
# Use the statewide first/last month stored in global.R to build every month in
# between. This creates the continuous x-axis used by the chart.
month_sequence_for_year <- 
  function(year) {
    span <- 
      SCHOOL_YEAR_MONTH_SPANS %>%
      filter(SchoolYear == year)
    
    if (nrow(span) == 0) {
      return(as.Date(character()))
    }
    
    seq.Date(
      from = span$first_month[[1]],
      to = span$last_month[[1]],
      by = "month"
    )
  }


# ==== CURRENT-SCHOOL HELPER ====

# Historical schools remain in APP_DATA because they belong in historical LEA
# and State totals. This helper changes only which schools can appear in the UI
# dropdowns: the selectable list is limited to latest-year school keys.
current_school_rows <- 
  function(data) {
    data %>%
      filter(level == "school") %>%
      semi_join(
        CURRENT_SCHOOL_KEYS,
        by = c("DistrictCode", "SchoolCode")
      )
  }


# ==== FILTER THE SOURCE DATA ====

# Keep exactly three reporting entities for the selected view:
#   1. selected School
#   2. selected LEA
#   3. State
#
# server.R supplies year, lea, and school from the user's current inputs.
data_filtered <- 
  function(data,
           year,
           lea,
           school) {
    
    data %>%
      filter(
        SchoolYear == year,
        (level == "school" & DistrictName == lea & SchoolName == school) |
          (level == "lea" & DistrictName == lea) |
          level == "state"
      )
  }


# ==== BUILD CUMULATIVE ANALYSIS DATA ====

# This is the core analytical teaching function. It accepts already-filtered
# source rows and returns one list containing both the chart data and a few
# labels used by R/plot.R.
make_fafsa_analysis_data <- 
  function(data) {
    
    # Separate the three comparison levels so their names and denominators are
    # easy to read and use below.
    school_rows <- 
      data %>%
      filter(level == "school")
    
    lea_rows <- 
      data %>%
      filter(level == "lea")
    
    state_rows <- 
      data %>%
      filter(level == "state")
    
    # This function expects one valid School, LEA, and State selection. The
    # reactive checks in server.R make sure incomplete dropdown transitions do
    # not reach this point.
    if (nrow(school_rows) == 0 || nrow(lea_rows) == 0 || nrow(state_rows) == 0) {
      stop("Filtered data must contain School, LEA, and State reporting rows.")
    }
    
    # These values are stable across the monthly rows for each reporting entity.
    school_name <- first(school_rows$SchoolName)
    lea_name <- first(lea_rows$DistrictName)
    year <- first(data$SchoolYear)
    month_sequence <- month_sequence_for_year(year)
    
    # A current school year can exist before any FAFSA receipt months are
    # available. Return an explicit no-data analysis object for that case.
    if (length(month_sequence) == 0) {
      return(
        list(
          data = tibble(),
          school_name = school_name,
          lea_name = lea_name,
          year = year,
          first_month = as.Date(NA),
          last_month = as.Date(NA),
          has_data = FALSE,
          empty_reason = paste0(
            "No FAFSA receipt months are available yet for school year ",
            school_year_label(year),
            "."
          )
        )
      )
    }
    
    # One small lookup table gives each reporting level its display label,
    # display name, and senior denominator.
    comparison_lookup <- 
      tibble(
        level = c("school", "lea", "state"),
        comparison = c("School", "LEA", "State"),
        comparison_name = c(school_name, lea_name, "State"),
        seniors = c(
          first(school_rows$seniors),
          first(lea_rows$seniors),
          first(state_rows$seniors)
        )
      )
    
    # The source file contains observed completion months plus possible
    # denominator-only rows with a missing month. Missing-month rows are not
    # completion events, so exclude them from the monthly numerator table.
    monthly_completed <- 
      data %>%
      filter(!is.na(ApplicationReceiptMonth)) %>%
      group_by(level, ApplicationReceiptMonth) %>%
      summarise(
        completed_this_month = sum(completed_this_month, na.rm = TRUE),
        .groups = "drop"
      )
    
    # expand_grid() creates every School/LEA/State x month combination.
    # left_join() adds the observed counts, and replace_na(..., 0) turns an
    # unobserved month into zero new completions rather than dropping the month.
    analysis_data <- 
      expand_grid(
        level = c("school", "lea", "state"),
        ApplicationReceiptMonth = month_sequence
      ) %>%
      left_join(
        monthly_completed,
        by = c("level", "ApplicationReceiptMonth")
      ) %>%
      left_join(
        comparison_lookup,
        by = "level"
      ) %>%
      mutate(
        SchoolYear = year,
        completed_this_month = replace_na(completed_this_month, 0),
        comparison = factor(
          comparison,
          levels = c("School", "LEA", "State")
        ),
        month_label = factor(
          format(ApplicationReceiptMonth, "%b"),
          levels = format(month_sequence, "%b"),
          ordered = TRUE
        )
      ) %>%
      arrange(comparison, ApplicationReceiptMonth) %>%
      group_by(comparison) %>%
      mutate(
        # cumsum() converts the monthly counts into the cumulative numerator.
        cumulative_completed = cumsum(completed_this_month),
        
        # Divide by the stable senior denominator for that comparison group.
        cumulative_completion_rate = if_else(
          seniors > 0,
          cumulative_completed / seniors,
          NA_real_
        ),
        
        # Pre-format the values once so plot.R can focus on presentation.
        label = if_else(
          is.na(cumulative_completion_rate),
          "",
          percent(cumulative_completion_rate, accuracy = 0.1)
        )
      ) %>%
      ungroup() %>%
      select(
        SchoolYear,
        comparison,
        comparison_name,
        ApplicationReceiptMonth,
        month_label,
        completed_this_month,
        cumulative_completed,
        seniors,
        cumulative_completion_rate,
        label
      )
    
    # Return one named list. server.R stores this as analysis_data(), and the
    # plot/text functions all read from the same shared result.
    list(
      data = analysis_data,
      school_name = school_name,
      lea_name = lea_name,
      year = year,
      first_month = min(month_sequence),
      last_month = max(month_sequence),
      has_data = TRUE,
      empty_reason = NA_character_
    )
  }

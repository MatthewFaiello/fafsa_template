# --------------------------- global.R -----------------------------------------
# PURPOSE:
# - load packages used across the app
# - load the main app data
# - define labels, defaults, and helper functions
# - keep app logic in one easy-to-find place


# -----------------------------------------------------------------------------
# 1) Packages
# -----------------------------------------------------------------------------
library(shiny)
library(bslib)
library(DT)
library(tidyverse)
library(scales)
library(ggrepel)


# -----------------------------------------------------------------------------
# 2) App title and labels
# -----------------------------------------------------------------------------
APP_TITLE <- "FAFSA Completion"

LABELS <- 
  list(year = "School year range",
       scope_1 = "District",
       scope_2 = "School",
       option_1 = "Gender",
       option_2 = "Race",
       tab_plot = "FAFSA completion trend",
       tab_data = "Underlying data")

# -----------------------------------------------------------------------------
# 3) Main data object
# -----------------------------------------------------------------------------
APP_DATA = readRDS(file.path("input_data", "APP_DATA.rds"))


# -----------------------------------------------------------------------------
# 4) Choices used in ui.R
# -----------------------------------------------------------------------------
YEAR_RANGE <- 
  APP_DATA %>%
  distinct(SchoolYear) %>%
  pull(SchoolYear) %>%
  sort()

SCOPE_1_CHOICES <- 
  APP_DATA %>%
  filter(level == "school") %>%
  distinct(DistrictName) %>%
  pull(DistrictName) %>%
  sort()

SCOPE_2_CHOICES <- 
  APP_DATA %>%
  filter(level == "school") %>%
  distinct(SchoolName) %>%
  pull(SchoolName) %>%
  sort()

OPTION_1_CHOICES <- 
  APP_DATA %>%
  filter(!is.na(gender)) %>%
  distinct(gender) %>%
  pull(gender) %>%
  sort()

OPTION_2_CHOICES <- 
  APP_DATA %>%
  filter(!is.na(RaceReportTitle), RaceReportTitle != "NA") %>%
  distinct(RaceReportTitle) %>%
  pull(RaceReportTitle) %>%
  sort()


# -----------------------------------------------------------------------------
# 5) Defaults
# -----------------------------------------------------------------------------
DEFAULTS <- 
  list(year_range = c(max(YEAR_RANGE), max(YEAR_RANGE)),
       scope_1 = SCOPE_1_CHOICES[[1]],
       scope_2 = SCOPE_2_CHOICES[[1]],
       option_1 = OPTION_1_CHOICES[[1]],
       option_2 = OPTION_2_CHOICES[[1]])


# -----------------------------------------------------------------------------
# 6) Theme palette (special DDOE theme!)
# -----------------------------------------------------------------------------
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


# -----------------------------------------------------------------------------
# 7) Helper: filter data to selected scope
# -----------------------------------------------------------------------------
data_filtered <- 
  function(data = APP_DATA,
           scope_1 = DEFAULTS$scope_1,
           scope_2 = DEFAULTS$scope_2,
           year_range = DEFAULTS$year_range,
           option_1 = DEFAULTS$option_1,
           option_2 = DEFAULTS$option_2) {
    
    data %>%
      filter(SchoolYear >= min(year_range),
             SchoolYear <= max(year_range),
             DistrictName %in% c(scope_1, "All LEAs"),
             SchoolName %in% c(scope_2, "All Schools"),
             gender %in% option_1,
             RaceReportTitle %in% option_2)
  }


# -----------------------------------------------------------------------------
# 8) Helper: create plot-ready data
# -----------------------------------------------------------------------------
make_fafsa_plot_data <- 
  function(data = data_filtered()) {
    
    month_levels <-
      c("October", "November", "December", 
        "January", "February", "March",
        "April", "May", "June")
    
    school_meta <- 
      data %>%
      filter(level == "school") %>%
      distinct(SchoolName, DistrictCode, DistrictName) %>%
      slice_head(n = 1)
    
    school_name <- school_meta$SchoolName[[1]]
    district_name <- school_meta$DistrictName[[1]]
    
    plot_dat0 <- 
      data %>%
      filter(completedFAFSA == "Complete",
             RaceReportTitle != "NA",
             as.character(ApplicationReceiptMonth) %in% month_levels) %>%
      mutate(ApplicationReceiptMonth = factor(as.character(ApplicationReceiptMonth),
                                              levels = month_levels,
                                              ordered = T),
             group = case_when(level == "school" ~ school_name,
                               level == "lea" ~ district_name,
                               level == "state" ~ "State",
                               .default = NA))
    
    seniors <- 
      plot_dat0 %>%
      distinct(SchoolYear, group, gender, RaceReportTitle, seniors) %>%
      group_by(group, gender, RaceReportTitle) %>%
      summarise(seniors = sum(seniors, na.rm = T),
                .groups = "drop")
    
    plot_dat1 <- 
      plot_dat0 %>%
      group_by(group, gender, RaceReportTitle, ApplicationReceiptMonth) %>%
      summarise(completed = sum(n, na.rm = T),
                .groups = "drop") %>%
      left_join(seniors) %>%
      group_by(group, gender, RaceReportTitle) %>%
      complete(ApplicationReceiptMonth = factor(month_levels,
                                                levels = month_levels,
                                                ordered = T),
               fill = list(completed = 0)) %>%
      fill(seniors, .direction = "downup") %>%
      arrange(ApplicationReceiptMonth, .by_group = T) %>%
      mutate(cum_completed = cumsum(completed),
             completion_rate = if_else(seniors > 0, cum_completed / seniors, NA)) %>%
      ungroup() %>%
      mutate(group = factor(group, levels = c(school_name, district_name, "State")))
    
    list(data = plot_dat1,
         school_name = school_name,
         district_name = district_name)
  }


# -----------------------------------------------------------------------------
# 9) Helper: build main plot
# -----------------------------------------------------------------------------
plot_fafsa_completion <- 
  function(data = data_filtered()) {
    
    plot_obj <- make_fafsa_plot_data(data)
    
    plot_dat <- plot_obj$data
    school_name <- plot_obj$school_name
    district_name <- plot_obj$district_name
    
    ggplot(plot_dat,
           aes(x = ApplicationReceiptMonth,
               y = completion_rate,
               color = group,
               group = group,
               label = percent(completion_rate, accuracy = 1))) +
      #geom_label_repel(show.legend = F, size = 3, fontface = "bold", direction = "y") +
      geom_line() +
      geom_point(size = 1.5) +
      facet_grid(RaceReportTitle ~ gender) +
      scale_color_manual(values = setNames(c(dde_orange, dde_blue, dde_muted),
                                           c(school_name, district_name, "State"))) +
      scale_y_continuous(labels = percent_format(accuracy = 1)) +
      scale_x_discrete(labels = c(January = "Jan",
                                  February = "Feb",
                                  March = "Mar",
                                  April = "Apr",
                                  May = "May",
                                  June = "Jun",
                                  July = "Jul",
                                  August = "Aug",
                                  September = "Sep",
                                  October = "Oct",
                                  November = "Nov",
                                  December = "Dec")) +
      labs(title = NULL,
           x = NULL,
           y = NULL,
           color = NULL) +
      theme_minimal(base_size = 12) +
      theme(plot.background = element_rect(fill = dde_bg, color = NA),
            panel.background = element_rect(fill = dde_surface, color = NA),
            strip.background = element_rect(fill = dde_orange_soft, color = dde_border),
            strip.text = element_text(color = dde_text, face = "bold"),
            panel.grid.major.x = element_blank(),
            panel.grid.major.y = element_line(color = dde_border),
            panel.grid.minor = element_blank(),
            axis.text.x = element_text(angle = 45, hjust = 1, color = dde_muted),
            axis.text.y = element_text(hjust = 1, color = dde_muted),
            axis.title = element_text(color = dde_text),
            plot.title = element_text(color = dde_blue_dark, face = "bold", size = 16),
            plot.subtitle = element_text(color = dde_muted),
            legend.position = "bottom",
            legend.text = element_text(color = dde_text),
            plot.margin = margin(12, 12, 12, 12))
  }


# -----------------------------------------------------------------------------
# 10) Helper: create table-ready data
# -----------------------------------------------------------------------------
underlying_data <- 
  function(data = data_filtered()) {
    
    data %>%
      mutate(Percent = round(if_else(seniors > 0, n / seniors * 100, NA), 1)) %>%
      select(`School Year` = SchoolYear,
             `District Name` = DistrictName,
             `School Name` = SchoolName,
             Grade,
             Gender = gender,
             Race = RaceReportTitle,
             `Application Receipt Month` = ApplicationReceiptMonth,
             Status = completedFAFSA,
             Count = n,
             Seniors = seniors,
             Percent)
  }


# -----------------------------------------------------------------------------
# 11) Helper: create summary text for the details card
# -----------------------------------------------------------------------------
make_scope_note <- 
  function(data = data_filtered()) {
    
    school_meta <- 
      data %>%
      filter(level == "school") %>%
      distinct(SchoolName, DistrictName) %>%
      slice_head(n = 1)
    
    years <- sort(unique(data$SchoolYear))
    year_label <- 
      if (length(years) == 1) {
        as.character(years)
      } else {
        paste0(min(years), "\u2013", max(years))
      }
    
    paste0("Showing ", school_meta$SchoolName[[1]],
           " compared with ", school_meta$DistrictName[[1]],
           " and the state for school year ", year_label,
           ". Rates are subgroup-specific within the selected gender and race filters.")
  }

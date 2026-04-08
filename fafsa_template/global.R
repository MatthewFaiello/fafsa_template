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


# -----------------------------------------------------------------------------
# 2) App title and labels
# -----------------------------------------------------------------------------
APP_TITLE <- "FAFSA Completion"

LABELS <- 
  list(year = "School year",
       scope_1 = "District",
       scope_2 = "School",
       tab_plot = "FAFSA completion by month",
       tab_data = "Underlying data")

# -----------------------------------------------------------------------------
# 3) Main data object
# -----------------------------------------------------------------------------
APP_DATA = readRDS(file.path("input_data", "APP_DATA.rds"))


# -----------------------------------------------------------------------------
# 4) Choices used in ui.R
# -----------------------------------------------------------------------------
YEAR <- 
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


# -----------------------------------------------------------------------------
# 5) Defaults
# -----------------------------------------------------------------------------
DEFAULTS <- 
  list(year = max(YEAR),
       scope_1 = "Christina School District", #SCOPE_1_CHOICES[[1]],
       scope_2 = "Shue-Medill Middle School" #SCOPE_2_CHOICES[[1]]
       )


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
           year = DEFAULTS$year,
           scope_1 = DEFAULTS$scope_1,
           scope_2 = DEFAULTS$scope_2) {
    
    data %>%
      filter(SchoolYear == year,
             DistrictName %in% c(scope_1, "All LEAs"),
             SchoolName %in% c(scope_2, "All Schools"))
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
      distinct(level, SchoolName, DistrictName, seniors)
    
    school <- school_meta %>% filter(level == "school") %>% distinct(SchoolName, seniors)
    district <- school_meta %>% filter(level == "lea") %>% distinct(DistrictName, seniors)
    state <- school_meta %>% filter(level == "state") %>% distinct(DistrictName, seniors)
    
    plot_dat0 <- 
      data %>%
      filter(completedFAFSA == "Complete",
             as.character(ApplicationReceiptMonth) %in% month_levels)
    
    school_rows <- plot_dat0 %>% filter(SchoolName == school$SchoolName)
    district_rows <- plot_dat0 %>% filter(DistrictName == district$DistrictName)
    state_rows <- plot_dat0 %>% filter(level == "state")
    
    if (nrow(school_rows) == 0) {
      school_blank <- 
        tibble(group = school$SchoolName, 
               ApplicationReceiptMonth = "October",
               completed = 0,
               seniors = school$seniors)} else {school_blank <- NULL}
    
    if (nrow(district_rows) == 0) {
      district_blank <- 
        tibble(group = district$DistrictName, 
               ApplicationReceiptMonth = "October",
               completed = 0,
               seniors = district$seniors)} else {district_blank <- NULL}
    
    if (nrow(state_rows) == 0) {
      state_blank <- 
        tibble(group = "State", 
               ApplicationReceiptMonth = "October",
               completed = 0,
               seniors = state$seniors)} else {state_blank <- NULL}
    
    plot_dat1 <-
      plot_dat0 %>%
      mutate(ApplicationReceiptMonth = factor(as.character(ApplicationReceiptMonth),
                                              levels = month_levels,
                                              ordered = T),
             group = case_when(level == "school" ~ school$SchoolName,
                               level == "lea" ~ district$DistrictName,
                               level == "state" ~ "State",
                               .default = NA)) %>%
      select(group, 
             ApplicationReceiptMonth, 
             completed = n, 
             seniors) %>%
      bind_rows(school_blank, 
                district_blank,
                state_blank) %>% 
      group_by(group) %>%
      complete(ApplicationReceiptMonth = factor(month_levels,
                                                levels = month_levels,
                                                ordered = T),
               fill = list(completed = 0)) %>%
      fill(seniors, 
           .direction = "downup") %>%
      arrange(ApplicationReceiptMonth, 
              .by_group = T) %>%
      mutate(group = factor(group, 
                            levels = c(school$SchoolName, 
                                       district$DistrictName, 
                                       "State")),
             completion_rate = completed / seniors)
    
    list(data = plot_dat1,
         school_name = school$SchoolName,
         district_name = district$DistrictName)
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
               fill = group,
               label = percent(completion_rate, accuracy = 1))) +
      geom_col(position = position_dodge(width = 0.9)) +
      geom_label(show.legend = F, 
                 size = 3, 
                 fontface = "bold", 
                 color = dde_surface,
                 position = position_dodge(width = 0.9),
                 vjust = -0.3) +
      coord_cartesian(clip = "off") +
      scale_fill_manual(values = setNames(c(dde_orange, dde_blue, dde_muted),
                                          c(school_name, district_name, "State"))) +
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
            axis.text.y = element_blank(),
            axis.title = element_text(color = dde_text),
            plot.title = element_text(color = dde_blue_dark, face = "bold", size = 16),
            plot.subtitle = element_text(color = dde_muted),
            legend.position = "top",
            legend.text = element_text(color = dde_text),
            legend.title = element_blank(),
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
      distinct(SchoolYear, SchoolName, DistrictName) %>%
      slice_head(n = 1)
    
    year <- school_meta$SchoolYear[[1]]
    school_name <- school_meta$SchoolName[[1]]
    district_name <- school_meta$DistrictName[[1]]
    
    year_label <- paste0(year - 1, "\u2013", year - 2000)
    
    paste0("Showing monthly FAFSA completion percentages for ",
           school_name, 
           ", compared with ",
           district_name,
           " and the state for school year ",
           year_label,
           ".")
  }

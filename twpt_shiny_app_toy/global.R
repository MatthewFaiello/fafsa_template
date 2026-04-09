# ==== STEP 2: global.R ====
# This file holds the shared app setup.
#
# This is the second step in the full app flow:
# - load APP_DATA created by organize.R
# - create dropdown choices and defaults
# - define helper functions used by ui.R and server.R
#
# Main idea to remember:
# global.R is where the shared app objects live.
# That includes the data, labels, defaults, and reusable helper functions.

# ==== SETUP ====

library(shiny)
library(bslib)
library(DT)
library(tidyverse)
library(scales)
library(ggthemes)

# ==== APP LABELS ====

# These labels control the text shown in the UI.
APP_TITLE <- "Staffing Trend"

LABELS <-
  list(scope_1 = "County",
       scope_2 = "LEA",
       tab_plot = "Trend plot",
       tab_data = "Underlying data")

# ==== DATA INPUT ====

# Load the app-ready dataset created in organize.R.
APP_DATA <- readRDS(file.path("input_data", "APP_DATA.rds"))

# ==== CHOICES USED IN UI ====

# These vectors feed the dropdowns in ui.R.
# scope_1 = county
# scope_2 = LEA
SCOPE_1_CHOICES <-
  APP_DATA %>%
  distinct(County_Name) %>%
  pull(County_Name) %>%
  sort()

SCOPE_2_CHOICES <-
  APP_DATA %>%
  distinct(lea) %>%
  pull(lea) %>%
  sort()

# ==== DEFAULTS ====

# These define the opening view of the app.
# They set the initial county and LEA shown when the app starts.
DEFAULTS <-
  list(scope_1 = "New Castle",
       scope_2 = "Appoquinimink School District")

# ==== HELPER FUNCTIONS ====

# These helpers keep repeated logic out of ui.R and server.R.
# The server calls them when it needs to:
# - filter the data
# - prepare the plot data
# - build the chart
# - format the data table
# - create the scope note

# ==== DATA FILTERING ====

# data_filtered() is the base filter helper.
# It returns only the rows for the selected county and LEA.
# This is the core dataset used throughout the app.
data_filtered <-
  function(data = APP_DATA,
           scope_1 = DEFAULTS$scope_1,
           scope_2 = DEFAULTS$scope_2) {
    
    data %>%
      filter(County_Name == scope_1,
             lea == scope_2) %>%
      arrange(SchoolYear)
  }

# ==== PLOT PREP ====

# make_plot_data() prepares the filtered data for plotting.
# In this app, the main metric is StudentsPerTeacher,
# so this helper keeps only the fields needed for the time series chart.
make_plot_data <-
  function(data = data_filtered()) {
    
    data %>%
      select(SchoolYear,
             County_Name,
             leaType,
             lea,
             StudentsPerTeacher)
  }

# ==== PLOT HELPER ====

# plot_staffing_trend() is the presentation layer for the chart.
# It takes the plot-ready data and builds a single longitudinal line plot
# showing StudentsPerTeacher across school years for the selected LEA.
plot_staffing_trend <-
  function(data = data_filtered()) {
    
    plot_dat <- make_plot_data(data)
    
    lea_meta <-
      plot_dat %>%
      distinct(County_Name,
               leaType,
               lea)
    
    plot_dat %>%
      ggplot(aes(x = SchoolYear,
                 y = StudentsPerTeacher)) +
      geom_line(linewidth = 1) +
      geom_point(size = 2) +
      scale_x_continuous(breaks = sort(unique(plot_dat$SchoolYear))) +
      labs(title = paste0(lea_meta$lea,
                          " (",
                          lea_meta$leaType,
                          " - ",
                          lea_meta$County_Name,
                          ")"),
           subtitle = "\nStudents per teacher over time",
           x = "\nSchool Year",
           y = "Students / Teacher\n") +
      theme_economist_white()
  }

# ==== TABLE HELPER ====

# underlying_data() formats the filtered data for display in the table tab.
# It selects readable column names and keeps the fields a user might want
# to inspect after viewing the chart.
underlying_data <-
  function(data = data_filtered()) {
    
    data %>%
      transmute(`School Year` = SchoolYear,
                County = County_Name,
                `LEA Type` = leaType,
                LEA = lea,
                `District Code` = DistrictCode,
                `Grade Level` = gradeLevel,
                `General Teachers` = teacher_General,
                `Special Ed Teachers` = teacher_SpecEd,
                `Teacher Total` = teacherTotal,
                `General Students` = student_General,
                `Special Ed Students` = student_SpecEd,
                `Student Total` = studentTotal,
                Population = population,
                `Students per Teacher` = round(StudentsPerTeacher, 1))
  }

# ==== SCOPE NOTE HELPER ====

# make_scope_note() creates the sentence shown above the plot.
# Its job is to remind the user which county and LEA they are looking at,
# and what the chart is measuring.
make_scope_note <-
  function(data = data_filtered()) {
    
    county <- unique(data$County_Name)
    lea <- unique(data$lea)
    lea_type <- unique(data$leaType)
    
    begin <- min(data$SchoolYear)
    end <- max(data$SchoolYear)
    
    valley <- min(data$StudentsPerTeacher) %>% round(1)
    peak <- max(data$StudentsPerTeacher) %>% round(1)
    
    paste0("Showing ",
           lea,
           " in ",
           county,
           " County from ",
           begin,
           " to ",
           end,
           ". The line plot shows students per teacher over time. Across these years, the value ranges from ",
           valley,
           " to ",
           peak,
           ".")
  }


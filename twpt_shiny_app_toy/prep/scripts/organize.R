# ==== STEP 1: organize.R ====
# This script builds the app-ready dataset used by the Shiny app.
#
# This is the first step in the full app flow:
# - read the raw source file
# - clean and keep the fields the app needs
# - compute the main metric used in the plot
# - create APP_DATA
# - save APP_DATA so global.R can load it later
#
# Important note:
# the source file is LEA-level, not school-level.
# That means each row represents a county / LEA / year combination.
#
# Main idea to remember:
# organize.R does the data prep once so the app does not have to repeat
# those steps every time a user changes a filter.

# ==== SETUP ====

# These are the packages needed for this prep script.
# The code below:
# - checks which packages are installed
# - installs any missing ones
# - loads them into the session
needed_packages <- 
  c("tidyverse",
    "scales",
    "ggthemes",
    "shiny",
    "bslib",
    "DT")

missing_packages <- 
  needed_packages[!vapply(needed_packages,
                          requireNamespace,
                          logical(1))]

if (length(missing_packages)) {install.packages(missing_packages)}

invisible(lapply(needed_packages, library, character.only = T))

# ==== DATA INPUT ====

# Read the raw TWPT file.
# This is the starting point for the app data pipeline.
twpt0 = read_csv(file.path("prep", "data", "twpt.csv"))

# ==== DATA CLEANUP ====

# Build the final app-ready dataset.
#
# What this step does:
# - keeps only usable LEA rows
# - standardizes a few fields
# - computes StudentsPerTeacher, which is the main metric in the app
# - sorts the data so the line plot runs in time order
APP_DATA <-
  twpt0 %>%
  filter(!is.na(lea)) %>%
  transmute(SchoolYear,
            County_Name = factor(County_Name,
                                 levels = c("New Castle", "Kent", "Sussex")),
            leaType = str_remove(leaType, "s$"),
            lea,
            DistrictCode,
            gradeLevel,
            teacher_General,
            teacher_SpecEd,
            teacherTotal,
            student_General,
            student_SpecEd,
            studentTotal,
            population,
            StudentsPerTeacher = studentTotal / teacherTotal) %>%
  arrange(County_Name, lea, SchoolYear)

# ==== QA CHECKS ====

# This check looks for duplicate year / county / LEA combinations.
# For this app, we expect one row per SchoolYear x County_Name x lea.
APP_DATA %>%
  count(SchoolYear, County_Name, lea) %>%
  filter(n > 1)

# This is a quick sanity check on the plotted metric.
summary(APP_DATA$StudentsPerTeacher)

# ==== EXPORT ====

# Save the finished APP_DATA object where global.R expects to find it.
# Keeping the object name APP_DATA makes the rest of the app simpler,
# because ui.R and server.R can stay focused on the app logic.
dir.create("input_data")
write_rds(APP_DATA, file.path("input_data", "APP_DATA.rds"))



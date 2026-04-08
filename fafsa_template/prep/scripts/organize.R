# ==== TEMPLATE OVERVIEW ====
# This script builds the app-ready dataset and writes it out for the app to use.
#
# If you're reusing this project, this is where you:
# - point to your raw data
# - do the prep work
# - build the final APP_DATA object
#
# Main thing to keep the same:
# the final saved object should still be called APP_DATA unless you also go
# update global.R.


# ==== SETUP ====

# Add or remove packages here if your prep script needs something different.
needed_packages <- c("tidyverse")


missing_packages <- 
  needed_packages[!vapply(needed_packages, 
                          requireNamespace, 
                          logical(1), 
                          quietly = T)]
if (length(missing_packages)) {install.packages(missing_packages)}
invisible(lapply(needed_packages, library, character.only = T))


# ==== DATA INPUT (EDIT HERE) ====

# Point this to the raw file you want to use.
fafsa0 = read_csv(file.path("prep", "data", "fafsa_completion.csv"), na = c("", "NA", "NULL"))


# ==== DATA TRANSFORMATION ====

# Use the most recent year in the file instead of hard-coding one.
latest_year <- max(fafsa0$SchoolYear, na.rm = T)

# Schools to keep in the app.
# Right now the app keeps schools that exist in the latest year, then uses that
# list to filter the rest.
currentSchools <- 
  fafsa0 %>%
  filter(SchoolYear == latest_year) %>%
  distinct(DistrictCode,
           DistrictName,
           SchoolCode,
           SchoolName)


# ==== QA CHECKS ====

# These are quick spot checks.
# They do not change the data. They are just here so you can catch weirdness
fafsa0 %>%
  count(SchoolYear, DistrictCode, SchoolCode, StudentID) %>%
  filter(n > 1)

fafsa0 %>%
  distinct(SchoolYear, StudentID, DistrictCode, SchoolCode) %>%
  count(SchoolYear, StudentID) %>%
  filter(n > 1)

table(fafsa0$SchoolYear, fafsa0$CompletedFAFSA, useNA = "always")


# ==== DATA CLEANUP ====

# Keep only schools that still exist, then restore names. Otherwise old schools 
# can hang around in the app
fafsa1 <- 
  fafsa0 %>%
  select(-DistrictName, 
         -SchoolName) %>%
  inner_join(currentSchools) %>%
  select(SchoolYear,
         StudentID,
         DistrictCode,
         DistrictName,
         SchoolCode,
         SchoolName,
         Geography,
         ZipCode,
         Grade,
         Gender,
         RaceReportTitle,
         LowIncome,
         Medicaid,
         SpEdDefinition,
         CD504,
         ELL,
         Migrant,
         Homeless,
         FosterCare,
         MilitaryDep,
         Immersion,
         YearInHS,
         GradeRepeater,
         GradeSkipper,
         ApplicationReceiptDate,
         CompletedFAFSA)


# ==== APP DATA BUILD (EDIT HERE) ====

# This is the main prep block for the app-ready data.
fafsa2 <- 
  fafsa1 %>%
  filter(SchoolYear >= 2015) %>%
  mutate(DistrictCode = as.character(DistrictCode),
         SchoolCode = as.character(SchoolCode),
         completedFAFSA = case_when(
           CompletedFAFSA == "Y" ~ "Complete",
           CompletedFAFSA == "N" ~ "Incomplete",
           .default = NA),
    ApplicationReceiptMonth = case_when(is.na(ApplicationReceiptDate) ~ "No Receipt",
                                        .default = format(ApplicationReceiptDate, "%B")),
    ApplicationReceiptMonth = factor(ApplicationReceiptMonth,
                                     levels = c("October", "November", "December",
                                                "January", "February", "March",
                                                "April", "May", "June",
                                                "July", "August", "September",
                                                "No Receipt"),
                                     ordered = T)
    )



# ==== SUBGROUP DENOMINATORS ====

# These are the denominators used later for rates.

school_denoms <- 
  fafsa2 %>%
  distinct(SchoolYear,
           DistrictCode,
           DistrictName,
           SchoolCode,
           SchoolName,
           Grade,
           StudentID) %>%
  group_by(SchoolYear,
           DistrictCode,
           DistrictName,
           SchoolCode,
           SchoolName,
           Grade) %>%
  summarise(seniors = n(),
            .groups = "drop")

lea_denoms <- 
  fafsa2 %>%
  distinct(SchoolYear,
           DistrictCode,
           DistrictName,
           Grade,
           StudentID) %>%
  group_by(SchoolYear,
           DistrictCode,
           DistrictName,
           Grade) %>%
  summarise(seniors = n(),
            .groups = "drop")

state_denoms <- 
  fafsa2 %>%
  distinct(SchoolYear,
           Grade,
           StudentID) %>%
  group_by(SchoolYear,
           Grade) %>%
  summarise(seniors = n(),
            .groups = "drop")


# ==== SUMMARY TABLES ====

# These build the school-, LEA-, and state-level app data.
fafsa2_school <- 
  fafsa2 %>%
  group_by(level = "school",
           SchoolYear,
           DistrictCode,
           DistrictName,
           SchoolCode,
           SchoolName,
           Grade,
           ApplicationReceiptMonth,
           completedFAFSA) %>%
  summarise(n = n_distinct(StudentID),
            .groups = "drop") %>%
  left_join(school_denoms)

fafsa2_lea <- 
  fafsa2 %>%
  group_by(level = "lea",
           SchoolYear,
           DistrictCode,
           DistrictName,
           Grade,
           ApplicationReceiptMonth,
           completedFAFSA) %>%
  summarise(n = n_distinct(StudentID),
            .groups = "drop") %>%
  left_join(lea_denoms) %>%
  mutate(SchoolCode = "All Schools",
         SchoolName = "All Schools")

fafsa2_state <- 
  fafsa2 %>%
  group_by(level = "state",
           SchoolYear,
           Grade,
           ApplicationReceiptMonth,
           completedFAFSA) %>%
  summarise(n = n_distinct(StudentID),
            .groups = "drop") %>%
  left_join(state_denoms) %>%
  mutate(DistrictCode = "All LEAs",
         DistrictName = "All LEAs",
         SchoolCode = "All Schools",
         SchoolName = "All Schools")


# ==== FINAL APP DATA OBJECT ====

APP_DATA <- 
  bind_rows(fafsa2_school,
            fafsa2_lea,
            fafsa2_state) %>%
  mutate(level = factor(level, levels = c("school", "lea", "state"))) %>%
  arrange(level,
          SchoolYear,
          DistrictCode,
          SchoolCode,
          ApplicationReceiptMonth,
          completedFAFSA)


# ==== QA CHECKS ====

coverage_check <- 
  APP_DATA %>%
  group_by(level,
           SchoolYear,
           DistrictCode,
           DistrictName,
           SchoolCode,
           SchoolName,
           Grade) %>%
  summarise(seniors = first(seniors),
            total_n = sum(n, na.rm = T),
            .groups = "drop") %>%
  mutate(diff = total_n - seniors)


# ==== EXPORT (EDIT HERE) ====

# Keep this path lined up with global.R.
dir.create("input_data")
write_rds(APP_DATA, file.path("input_data", "APP_DATA.rds"))

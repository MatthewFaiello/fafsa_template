#---------------------------packages------------------------------------------#
###############################################################################
needed <- c("tidyverse")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = T)]
if (length(missing)) {install.packages(missing)}
invisible(lapply(needed, library, character.only = T))

#-----------------------load files--------------------------------------------#
###############################################################################
fafsa0 <- read_csv(file.path("prep", "data", "fafsa_completion.csv"), na = c("", "NA", "NULL"))

#-----------------------prep the data-----------------------------------------#
###############################################################################
# Use the most recent year in the file instead of hard-coding a value
latest_year <- max(fafsa0$SchoolYear, na.rm = T)

# Schools to keep in the app
currentSchools <- 
  fafsa0 %>%
  filter(SchoolYear == latest_year) %>%
  distinct(DistrictCode,
           DistrictName,
           SchoolCode,
           SchoolName)

# QA spot checks
fafsa0 %>%
  count(SchoolYear, DistrictCode, SchoolCode, StudentID) %>%
  filter(n > 1)

fafsa0 %>%
  distinct(SchoolYear, StudentID, DistrictCode, SchoolCode) %>%
  count(SchoolYear, StudentID) %>%
  filter(n > 1)

table(fafsa0$SchoolYear, fafsa0$CompletedFAFSA, useNA = "always")

# Keep only schools that still exist, then restore names
fafsa1 <- 
  fafsa0 %>%
  select(-DistrictName, -SchoolName) %>%
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

#-------------------------define app data-------------------------------------#
###############################################################################
fafsa2 <- 
  fafsa1 %>%
  filter(SchoolYear >= 2015) %>%
  mutate(DistrictCode = as.character(DistrictCode),
         SchoolCode = as.character(SchoolCode),
         completedFAFSA = case_when(CompletedFAFSA == "Y" ~ "Complete",
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
                                          ordered = T))

#-------------------------subgroup denominators-------------------------------#
###############################################################################
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

#-------------------------school summary--------------------------------------#
###############################################################################
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

#-------------------------LEA summary-----------------------------------------#
###############################################################################
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

#-------------------------state summary---------------------------------------#
###############################################################################
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

#-------------------------combine for app-------------------------------------#
###############################################################################
APP_DATA <- 
  bind_rows(fafsa2_school,
            fafsa2_lea,
            fafsa2_state) %>%
  mutate(level = factor(level, levels = c("school","lea", "state"))) %>% 
  arrange(level,
          SchoolYear,
          DistrictCode,
          SchoolCode,
          ApplicationReceiptMonth,
          completedFAFSA)

#-------------------------QA checks-------------------------------------------#
###############################################################################
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
            total_n = sum(n, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(diff = total_n - seniors)

#-------------------------write output----------------------------------------#
###############################################################################
write_rds(APP_DATA, file.path("input_data", "APP_DATA.rds"))






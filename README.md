# FAFSA Shiny training app

This is a deliberately simple production Shiny app that is also meant to be readable as a teaching example.

The intended learner already knows basic R syntax and common tidyverse verbs, but may be new to Shiny and reactive programming.

The main teaching goal is:

> A reader should be able to open `global.R`, `ui.R`, `server.R`, `R/analysis.R`, and `R/plot.R` and understand how user inputs flow through a Shiny app into reactive analysis and rendered outputs.

---

# 1. Recommended reading order

Read the R files in this order:

```text
global.R
   ↓
ui.R
   ↓
server.R
   ↓
R/analysis.R
   ↓
R/plot.R
```

Each file has one main job:

| File | Main job |
| --- | --- |
| `global.R` | Load packages/data and define objects/functions shared by the app |
| `ui.R` | Define what the user sees and create input/output placeholders |
| `server.R` | Connect inputs to reactives and reactives to outputs |
| `R/analysis.R` | Filter the summarized source data and calculate cumulative FAFSA measures |
| `R/plot.R` | Turn the analysis result into chart text and a ggplot |
| `www/styles.css` | Control visual styling in the browser |

The CSS is intentionally separate from the R/Shiny teaching sequence.

---

# 2. The Shiny mental model

The most important coding idea in this app is the reactive flow:

```text
input$year / input$lea / input$school
                ↓
         filtered_data()
                ↓
         analysis_data()
                ↓
   renderText() / renderPlot()
                ↓
 textOutput() / plotOutput()
```

A useful way to think about the pieces is:

- `selectizeInput()` in `ui.R` creates an input such as `input$year`.
- `reactive()` in `server.R` creates a value that automatically recalculates when an input it uses changes.
- `observeEvent()` watches for an input change and performs an action, such as updating another dropdown.
- `renderText()` and `renderPlot()` create output values in `server.R`.
- `textOutput()` and `plotOutput()` reserve places for those outputs in `ui.R`.

That input → reactive → output pattern is the core Shiny lesson in this project.

---

# 3. Production data path

The deployed app contains only summarized reporting data.

```text
production FAFSA SQL workflow
        ↓
input_data/fafsa_completion.csv
        ↓
global.R reads APP_DATA
        ↓
server.R filters the selected School / LEA / State rows
        ↓
R/analysis.R builds cumulative monthly measures
        ↓
R/plot.R formats the chart
        ↓
ui.R displays the result
```

There is no student-level file and no student-level preparation step inside the deployed Shiny project.

The routine refresh is intentionally simple:

1. run the validated production SQL workflow
2. export the summarized result with column headers
3. replace `input_data/fafsa_completion.csv`
4. run the external production QA/QC
5. redeploy the app

---

# 4. What the source CSV contains

The summarized input contract is:

| Field | Meaning |
| --- | --- |
| `DataAsOf` | Date the production extract was run |
| `EnrollmentAsOf` | Enrollment snapshot used for that school year |
| `level` | `school`, `lea`, or `state` |
| `SchoolYear` | Reporting school year |
| `DistrictCode` | LEA code, or `All LEAs` for State rows |
| `DistrictName` | LEA name, or `All LEAs` for State rows |
| `SchoolCode` | School code, or `All Schools` for LEA/State rows |
| `SchoolName` | School name, or `All Schools` for LEA/State rows |
| `ApplicationReceiptMonth` | Month of the selected FAFSA receipt date |
| `seniors` | Senior denominator for the reporting entity |
| `completed_this_month` | Students whose selected FAFSA receipt date falls in that month |

The SQL preserves actual observed receipt months. It does **not** impose a fixed FAFSA month window.

Entities with no FAFSA completions are retained with their senior denominator and a missing receipt month.

---

# 5. What R adds

The CSV contains observed monthly completion counts. The analytical work in `R/analysis.R` is deliberately visible.

For the selected School, LEA, and State:

```text
observed monthly counts
        ↓
build continuous statewide month sequence for that SchoolYear
        ↓
expand School / LEA / State × month
        ↓
fill missing monthly counts with 0
        ↓
cumsum(completed_this_month)
        ↓
cumulative_completed / seniors
```

This separation is intentional:

```text
SQL = reporting population + FAFSA match + monthly aggregate
R   = visualization-ready month grid + cumulative calculation
```

That makes the cumulative calculation easy for a learner to find and inspect.

---

# 6. Current schools versus historical totals

Historical schools remain in `APP_DATA` so historical LEA and State totals remain complete.

The app limits only the **selectable School list** to schools present in the latest included school year.

That rule is implemented in R through:

```text
CURRENT_SCHOOL_KEYS
        ↓
current_school_rows()
        ↓
Year / LEA / School dropdown choices
```

So the distinction is:

```text
historical reporting data
    stays in APP_DATA and contributes to LEA/State totals

current-school display rule
    controls which schools appear in the dropdowns
```

---

# 7. File-by-file walkthrough

## `global.R`

Shiny loads `global.R` once when the app starts.

It:

1. loads packages
2. reads `input_data/fafsa_completion.csv`
3. checks the input contract
4. derives observed month spans
5. identifies current-school keys
6. sources `R/analysis.R`
7. builds the opening filter choices/defaults
8. defines the shared color palette
9. sources `R/plot.R`

Objects defined here are available to both `ui.R` and `server.R`.

## `ui.R`

`ui.R` defines the browser interface.

The three `selectizeInput()` calls create:

```text
input$year
input$lea
input$school
```

The output placeholders include:

```text
textOutput("chart_title")
textOutput("chart_subtitle")
plotOutput("main_plot")
```

`conditionalPanel()` switches between the chart and the intentional no-data state.

## `server.R`

`server.R` is where the reactive programming happens.

The first reactives calculate valid LEA and School choices. `observeEvent()` then updates the dependent dropdowns when Year or LEA changes.

The main analytical path is:

```text
filtered_data()
    filters APP_DATA from the current inputs

analysis_data()
    calls make_fafsa_analysis_data(filtered_data())

output$chart_title
output$main_plot
output$chart_subtitle
    render the shared analysis object
```

The small `req()` checks prevent incomplete Year/LEA/School transitions from being treated as real analytical states.

## `R/analysis.R`

This file contains ordinary R functions rather than Shiny reactives.

The key function is:

```r
make_fafsa_analysis_data(data)
```

Its main teaching steps are intentionally explicit:

- split the selected data into School / LEA / State
- create the full month sequence
- summarize observed monthly completions
- `expand_grid()` the full comparison × month structure
- `left_join()` the observed counts
- `replace_na(..., 0)` for months with no new completions
- use `cumsum()` to calculate cumulative completions
- divide by `seniors` for the cumulative completion rate

## `R/plot.R`

This file separates presentation from calculation.

It contains ordinary functions that accept the shared analysis object:

```r
plot_fafsa_completion(analysis)
make_chart_title(analysis)
make_chart_subtitle(analysis)
```

`server.R` decides when these functions run. `plot.R` only decides how the already-calculated result is presented.

---

# 8. Privacy boundary

Student-level data are used upstream in the controlled SQL environment to construct the reporting population and FAFSA match.

The deployed Shiny project does **not** contain:

- StudentID
- student names
- date of birth
- individual FAFSA receipt dates
- demographic records
- individual complete/incomplete records

The deployed CSV contains only reporting dimensions, denominators, and aggregated monthly completion counts.

---

# 9. Project structure

The deployment project is intentionally small:

```text
fafsa_app/
├── README.md
├── global.R
├── ui.R
├── server.R
├── R/
│   ├── analysis.R
│   └── plot.R
├── input_data/
│   └── fafsa_completion.csv
└── www/
    ├── styles.css
    └── Website-Header.png
```

The structure mirrors the teaching sequence:

```text
setup -> interface -> reactivity -> analysis -> presentation
```

---

# 10. QA/QC boundary

The app contains lightweight startup checks that protect the summarized input contract.

The more complete production QA/QC is intentionally kept outside the deployed Shiny application. That includes checks such as:

- School → LEA reconciliation
- LEA → State reconciliation
- monthly rollup reconciliation
- stable denominators
- zero-completion entities
- charter reporting hierarchy
- historical year coverage
- comparison with the existing SchoolLevel FAFSA report

Keeping those checks external lets the production app remain small enough to teach.

---

# 11. Troubleshooting order

When something looks wrong, debug in the same order as the data flow:

```text
1. production SQL result
2. input_data/fafsa_completion.csv
3. global.R startup objects
4. inputs in ui.R / server.R
5. filtered_data()
6. analysis_data()
7. plot/text outputs
```

That keeps debugging tied to the actual architecture of the app.

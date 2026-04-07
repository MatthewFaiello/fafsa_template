# FAFSA Completion Rates Shiny App

A Shiny application for exploring cumulative FAFSA completion rates by month at the **school**, **district**, and **state** levels. The app lets users filter by school year, district, school, gender, and race, then view both a trend chart and the underlying filtered data. The filtered table can also be downloaded as a CSV file.

## What the app does

This app is designed to help users compare FAFSA completion progress across multiple reporting levels over time. The main view shows a completion trend chart, while a second tab exposes the supporting table used for the analysis. In the current app structure, users can:

- select a school year range
- choose a district and school
- filter by gender and race
- compare the selected school with its district and the state
- download the filtered data

## Project structure

```text
fafsa_example/
├── fafsa_example.Rproj
├── README.md
├── global.R
├── ui.R
├── server.R
├── input_data/
│   └── APP_DATA.RDS
├── prep/
│   ├── data/
│   └── scripts/
│       ├── organize.R
│       └── fafsa_completion.sql
└── www/
    ├── styles.css
    └── Website-Header.png
```

## File guide

### `global.R`
Loads packages, defines shared app constants and defaults, loads the main application data from `input_data/APP_DATA.rds`, and stores helper functions used by both `ui.R` and `server.R`.

### `ui.R`
Defines the user interface, including the sidebar filters, download button, trend tab, and underlying-data tab. It also links the app stylesheet in `www/styles.css`.

### `server.R`
Handles the reactive logic for updating available filter choices, filtering the data, rendering the plot, rendering the scope note, rendering the detail table, and downloading the filtered data.

### `www/`
Stores static assets used by the app, including the custom stylesheet and the header image.

### `input_data/`
Stores the main input file used by the app.

### `prep/`
Contains supporting preparation assets, including a `data/` folder and scripts used to organize or query source data.

## App layout

The app uses a sidebar-plus-main-panel layout:

- **Sidebar**: year range, district, school, gender, race, and download control
- **FAFSA completion trend** tab: main plot plus a short scope note describing the current selection
- **Underlying data** tab: filterable detail table

## Data assumptions

The current app logic assumes the source data contains values needed to support:

- school, district, and state comparison levels
- school year filtering
- gender and race subgroup filtering
- monthly FAFSA completion counts
- a seniors denominator for completion-rate calculation

## Running the app

Open the project in RStudio and run the app from the project root so the relative paths to `input_data/` and `www/` resolve correctly.

Typical options:

```r
shiny::runApp()
```

or, if you are already in the project directory:

```r
source("global.R")
source("ui.R")
source("server.R")
shinyApp(ui, server)
```

## Packages used

The current project loads:

- `shiny`
- `bslib`
- `DT`
- `tidyverse`
- `scales`
- `ggrepel`

## Notes

This repository appears to include both the app itself and supporting preparation scripts. A good workflow is:

1. prepare or refresh the source data in `prep/`
2. save the app-ready data object to `input_data/APP_DATA.rds`
3. run the Shiny app from the project root


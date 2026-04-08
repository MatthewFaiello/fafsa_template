# Shiny app template for people who do not want to reinvent the wheel every time :)

This app framework is meant to be reused, but not in a giant framework, enterprise, “please enjoy this 14-page onboarding guide” kind of way. Maybe we’ll get there someday but today is definitely not that day.

The goal here is to give you a practical example you can actually work from: swap in your own data, update a few labels, filters, and helper functions, and keep moving.

## What lives where

- `organize.R` builds the app-ready dataset
- `global.R` loads shared stuff used across the app
- `ui.R` controls what people see
- `server.R` controls what the app does when people click things
- `styles.css` handles the visual side of life

## Directory layout

Here is the basic file structure for this app:

```text
fafsa_template/
├── README.md
├── fafsa_template.Rproj
├── global.R
├── server.R
├── ui.R
├── input_data/
│   └── APP_DATA.RDS
├── prep/
│   ├── data/
│   │   └── fafsa_completion.csv
│   └── scripts/
│       ├── organize.R
│       └── fafsa_completion.sql
└── www/
    ├── styles.css
    └── Website-Header.png
```

### What goes where

- `README.md` explains how to use the template
- `fafsa_template.Rproj` is the RStudio project file
- `global.R`, `ui.R`, and `server.R` are the main app files
- `input_data/` holds the app-ready data file the app actually reads
- `prep/data/` holds the raw input data
- `prep/scripts/` holds the prep scripts used to build the app-ready data
- `www/` holds static files like CSS and images used by the app

### How the data flows

The basic flow is:

`prep/data/` → `prep/scripts/organize.R` → `input_data/APP_DATA.RDS` → app

So if you are updating the underlying data, that usually starts in `prep/`, not in the app files themselves.

One small but important note:
- files in `www/` need to stay in `www/` if you want the app to actually find them
- the app-ready data file needs to stay where `global.R` expects it, unless you update that path there too

## Start here if you're making this your own

### 1) `organize.R`
This is usually the first file to change.

Come here to:
- point to your raw file
- update prep steps
- change project-specific filtering or recodes

Main thing to keep the same:
- the final saved object should still be called `APP_DATA`

### 2) `global.R`
This is the app’s shared setup file.

Change this if you need to:
- rename the app
- change labels
- update defaults
- swap helper text
- update helper functions for your own columns or categories

### 3) `ui.R`
This is the layout.

Change this if you want to:
- update the sidebar text
- change branding
- rename tabs
- move outputs around
- add or remove controls

One small but important thing:
- input and output IDs in `ui.R` need to match what shows up in `server.R`

### 4) `server.R`
This is the reactive wiring.

Come here when you need to:
- update how filters depend on each other
- change what gets filtered
- connect outputs
- debug anything that suddenly forgot how to react

### 5) `styles.css`
This is where the app gets to look like it has its life together.

Use this file to:
- change colors
- tweak spacing
- resize the logo
- adjust plot/table sizing
- honestly, ask an LLM for help in this file

## How to use this template without creating extra chaos

Anything marked with:

`# >>> EDIT HERE >>>`

is meant to be the plug-and-play area.

And that doesn't mean you should never touch anything else. It just means those are the places I would check first before messing with anything more structural.

## Several things to double-check when reusing this

### Data and file issues
- If the app opens and immediately complains, make sure `APP_DATA.rds` got written where `global.R` expects it
- If your column names change, check both `organize.R` and `global.R`
- If a helper function stops working, check whether it still matches the structure of your current data
- If a file path works for you and for literally no one else, it is probably too local and needs to be cleaned up
- If your app works on one machine but not another, check package versions and file paths before doing anything dramatic

### UI and naming issues
- If you rename an input in `ui.R`, update it in `server.R`
- If you rename an output in `server.R`, update it in `ui.R`
- If you change object names in `global.R`, make sure the same names are still being used in `ui.R` and `server.R`
- If the app starts throwing `object not found`, there is a good chance something got renamed in one file but not the others

### Reactive and filtering issues
- If the app runs but the dropdowns get weird, check the reactive logic in `server.R`
- If one filter is supposed to depend on another, make sure the `observeEvent()` or reactive update is pointing to the right input
- If a dropdown is blank, check whether the filtered data is actually returning any rows
- If something reactive is firing when it should not, look at your `req()` statements and reactive dependencies
- If something is not updating when it should, there is a decent chance the reactive dependency is missing
- If a plot or table is blank, check the filtered dataset first before assuming the plot/table code is broken

### Output and download issues
- If downloads stop working, check both the object being written and the `filename` / `content` functions in `downloadHandler()`
- If a table looks wrong, check the data going into it before blaming `DT`
- If a plot looks wrong, check the data going into it before blaming `ggplot`

### Styling and layout issues
- If the app works but looks off, that is probably a `styles.css` problem
- If styling changes are not showing up, make sure the CSS file is in the right place (`www/`) and that the app is actually loading it
- If spacing or sizing gets weird, check `styles.css` before trying to fix layout problems in the `ui.R`

### When all else fails
- Test the app in this order: data load, helper functions, filtered data, outputs, then styling
- If you are truly stuck, strip it back to the smallest broken piece and test that first
- If the “small fix” turns into two hours of nonsense, that is normal and not a personal failure

## The whole idea

This template is not trying to fit every dataset known to humankind. It is not even trying to fit every DDOE dataset.

It is just trying to make a decent Shiny app structure easier to work with and easier to pick up.

The main things it should help with are:
- where the data comes from
- what to edit first
- how the UI connects to the server
- where to swap in your own project-specific logic

Teams me if the “self-guided” part stops being very self-guided...

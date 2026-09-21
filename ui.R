# =============================================================================
# FAFSA SHINY APP: USER INTERFACE
#
# ui.R describes what appears in the browser. It does not calculate the FAFSA
# measures. It creates:
#
#   inputs  -> values the user can change, such as input$year
#   outputs -> placeholders that server.R fills, such as output$main_plot
#
# If an inputId or output id changes here, update the matching name in server.R.
# =============================================================================


# ==== UI LAYOUT ====

ui <-
  fluidPage(
    title = APP_TITLE,
    theme = bs_theme(
      version = 5,
      primary = dde_orange,
      bg = dde_bg,
      fg = dde_blue_dark
    ),

    # ==== STYLESHEET ====
    # Files inside www/ are automatically available to the browser.
    tags$head(
      tags$link(
        rel = "stylesheet",
        type = "text/css",
        href = "styles.css"
      )
    ),

    div(
      class = "app-shell",

      # ==== APP HEADER (EDIT HERE) ====
      # >>> EDIT HERE >>>
      div(
        class = "app-header",

        div(
          class = "brand-wrap",
          img(
            src = "Website-Header.png",
            class = "brand-logo",
            alt = APP_TITLE
          )
        ),

        div(
          class = "header-copy",
          h2(APP_TITLE, class = "app-title"),
          p(
            class = "app-intro",
            "Track cumulative FAFSA completion by month for a school, its LEA, and the state."
          )
        )
      ),
      # <<< END EDIT <<<


      # ==== INPUTS: YEAR -> LEA -> SCHOOL ====
      # selectizeInput() creates reactive input values. For example, choosing a
      # year here creates input$year in server.R. The LEA and School choices are
      # updated by server.R because they depend on earlier selections.
      div(
        class = "filter-row",

        selectizeInput(
          inputId = "year",
          label = LABELS$year,
          choices = YEAR_CHOICES,
          selected = DEFAULTS$year,
          multiple = FALSE
        ),

        selectizeInput(
          inputId = "lea",
          label = LABELS$lea,
          choices = LEA_CHOICES,
          selected = DEFAULTS$lea,
          multiple = FALSE
        ),

        selectizeInput(
          inputId = "school",
          label = LABELS$school,
          choices = SCHOOL_CHOICES,
          selected = DEFAULTS$school,
          multiple = FALSE
        )
      ),


      # ==== OUTPUTS: TITLE + CHART ====
      # textOutput() and plotOutput() are placeholders. server.R supplies their
      # values through output$chart_title, output$chart_subtitle, and
      # output$main_plot.
      card(
        class = "plot-card",

        card_header(
          h3(
            textOutput("chart_title", inline = TRUE),
            class = "chart-title"
          ),
          p(
            textOutput("chart_subtitle", inline = TRUE),
            class = "chart-subtitle"
          )
        ),

        card_body(
          class = "chart-body",

          # conditionalPanel() shows one of two UI states based on the
          # TRUE/FALSE output$has_data value created in server.R.
          conditionalPanel(
            condition = "output.has_data",

            div(
              class = "chart-legend",

              div(
                class = "legend-item",
                span(class = "legend-swatch legend-school"),
                span("School")
              ),

              div(
                class = "legend-item",
                span(class = "legend-swatch legend-lea"),
                span("LEA")
              ),

              div(
                class = "legend-item",
                span(class = "legend-swatch legend-state"),
                span("State")
              )
            ),

            div(
              class = "plot-panel",
              plotOutput("main_plot")
            )
          ),

          conditionalPanel(
            condition = "!output.has_data",
            div(
              class = "empty-state-panel",
              h4("No FAFSA receipt months are available yet."),
              p("Completion results will appear here as FAFSA records become available.")
            )
          )
        )
      ),


      # ==== EXPLANATION (EDIT HERE) ====
      # >>> EDIT HERE >>>
      conditionalPanel(
        condition = "output.has_data",
        card(
          class = "reading-note-card",
          card_body(
            h4("How to read this chart"),
            p(
              "Each bar shows the cumulative share of seniors with a completed FAFSA by that month. Compare the school with its LEA and the state."
            )
          )
        )
      )
      # <<< END EDIT <<<
    )
  )

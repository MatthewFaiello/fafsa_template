# =============================================================================
# FAFSA SHINY APP: SERVER LOGIC
#
# server.R connects the UI inputs to the analysis and then sends results back to
# the UI outputs.
#
# The main reactive path is intentionally simple:
#
# input$year / input$lea / input$school
#                 ↓
#          filtered_data()
#                 ↓
#          analysis_data()
#                 ↓
#      renderText() / renderPlot()
#
# Two Shiny ideas are especially important here:
#
# reactive()     returns a value and recalculates when its dependencies change.
# observeEvent() performs an action when an input changes. Here, that action is
#                updating a dependent dropdown.
# =============================================================================


# ==== SERVER FUNCTION ====

server <- 
  function(input, output, session) {
    
    # ==== REACTIVE LEA CHOICES ====
    # Because this reactive reads input$year, it recalculates whenever the user
    # changes the school year.
    lea_choices <- 
      reactive({
        req(input$year)

        current_school_rows(APP_DATA) %>%
          filter(
            SchoolYear == input$year
          ) %>%
          distinct(DistrictName) %>%
          pull(DistrictName) %>%
          sort()
      })


    # ==== REACTIVE SCHOOL CHOICES ====
    # This reactive depends on both input$year and input$lea.
    school_choices <- 
      reactive({
        req(input$year, input$lea)

        current_school_rows(APP_DATA) %>%
          filter(
            SchoolYear == input$year,
            DistrictName == input$lea
          ) %>%
          distinct(SchoolName) %>%
          pull(SchoolName) %>%
          sort()
      })


    # ==== WHEN YEAR CHANGES: UPDATE LEA + SCHOOL ====
    # observeEvent() is useful when an input change should trigger an action
    # rather than return a reusable value. A new year can change both downstream
    # dropdowns, so update LEA and School together.
    observeEvent(input$year, {
      lea_options <- lea_choices()

      req(length(lea_options) > 0)

      # Keep the existing LEA if it is valid in the new year. Otherwise choose
      # the first valid LEA.
      selected_lea <- 
        if (!is.null(input$lea) && input$lea %in% lea_options) {
          input$lea
        } else {
          lea_options[[1]]
        }

      # Build the School choices from the LEA that will be selected.
      school_options <-
        current_school_rows(APP_DATA) %>%
        filter(
          SchoolYear == input$year,
          DistrictName == selected_lea
        ) %>%
        distinct(SchoolName) %>%
        pull(SchoolName) %>%
        sort()

      # Keep the existing School when possible. Otherwise choose the first
      # valid School for the selected year and LEA.
      selected_school <- 
        if (
          length(school_options) > 0 &&
          !is.null(input$school) &&
          input$school %in% school_options
        ) {
          input$school
        } else if (length(school_options) > 0) {
          school_options[[1]]
        } else {
          character(0)
        }

      updateSelectizeInput(
        session = session,
        inputId = "lea",
        choices = lea_options,
        selected = selected_lea,
        server = FALSE
      )

      updateSelectizeInput(
        session = session,
        inputId = "school",
        choices = school_options,
        selected = selected_school,
        server = FALSE
      )
    }, ignoreInit = FALSE)


    # ==== WHEN LEA CHANGES: UPDATE SCHOOL ====
    # A manual LEA change only affects the School dropdown.
    observeEvent(input$lea, {
      req(input$year, input$lea)

      choices <- school_choices()

      if (length(choices) == 0) {
        updateSelectizeInput(
          session = session,
          inputId = "school",
          choices = character(0),
          selected = character(0),
          server = FALSE
        )

        return(invisible(NULL))
      }

      selected <- 
        if (!is.null(input$school) && input$school %in% choices) {
          input$school
        } else {
          choices[[1]]
        }

      updateSelectizeInput(
        session = session,
        inputId = "school",
        choices = choices,
        selected = selected,
        server = FALSE
      )
    }, ignoreInit = TRUE)


    # ==== REACTIVE 1: FILTER THE SOURCE DATA ====
    # req() pauses this reactive until the needed inputs exist. The last two
    # req() calls also keep the previous chart visible during the brief moment
    # when dependent dropdowns are updating to a new valid combination.
    filtered_data <- 
      reactive({
        req(input$year, input$lea, input$school)
        req(input$lea %in% lea_choices(), cancelOutput = TRUE)
        req(input$school %in% school_choices(), cancelOutput = TRUE)

        data_filtered(
          data = APP_DATA,
          year = input$year,
          lea = input$lea,
          school = input$school
        )
      })
    
    
    # ==== REACTIVE 2: CALCULATE THE CHART DATA ====
    # Calling filtered_data() creates a reactive dependency. Whenever the
    # filtered rows change, this calculation reruns automatically.
    analysis_data <- 
      reactive({
        data <- filtered_data()

        req(nrow(data) > 0, cancelOutput = TRUE)

        make_fafsa_analysis_data(data)
      })


    # ==== OUTPUT STATE FOR conditionalPanel() ====
    # ui.R uses this TRUE/FALSE output to decide whether to show the chart or
    # the intentional no-data message. This is based on the selected year, so a
    # temporary LEA/School transition does not flash the empty state.
    output$has_data <-
      reactive({
        req(input$year)

        APP_DATA %>%
          filter(
            SchoolYear == input$year,
            !is.na(ApplicationReceiptMonth)
          ) %>%
          nrow() > 0
      })

    # conditionalPanel() lives in the browser, so keep this output available
    # even when one of its panels is hidden.
    outputOptions(
      output,
      "has_data",
      suspendWhenHidden = FALSE
    )


    # ==== TEXT OUTPUT ====
    # renderText() turns a reactive value into text for textOutput() in ui.R.
    output$chart_title <-
      renderText({
        make_chart_title(analysis_data())
      })
    
    
    # ==== PLOT OUTPUT ====
    # renderPlot() reruns whenever analysis_data() changes and sends the new
    # ggplot to plotOutput("main_plot") in ui.R.
    output$main_plot <- 
      renderPlot({
        plot_fafsa_completion(analysis_data())
      }, res = 100)
    
    
    # ==== TEXT OUTPUT ====
    output$chart_subtitle <- 
      renderText({
        make_chart_subtitle(analysis_data())
      })
    
    
  }

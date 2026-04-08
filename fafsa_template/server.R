# ==== TEMPLATE OVERVIEW ====
# This file is the reactive wiring for the app.
#
# This is where you come when you need to:
# - keep inputs in sync
# - connect outputs to the data
#
# The main rule here:
# keep input ids aligned with ui.R and keep helper function names aligned with global.R.


# ==== SERVER LOGIC ====

server <- 
  function(input, output, session) {
    
    # ==== DYNAMIC INPUT UPDATES (EDIT HERE) ====
    # >>> EDIT HERE >>>
    # These observers keep the dropdowns synced up.
    # In this app, district depends on year and school depends on district.
    
    # District choices from year
    lea_choices <- 
      reactive({req(input$year)
        
        APP_DATA %>%
          filter(level == "lea",
                 SchoolYear == input$year) %>%
          distinct(DistrictName) %>%
          pull(DistrictName) %>%
          sort()
      })
    
    observeEvent(input$year, {
      choices <- lea_choices()
      
      updateSelectizeInput(inputId = "scope_1",
                           choices = choices,
                           selected = choices[1],
                           server = T)
    })
    
    # School choices from district
    school_choices <- 
      reactive({req(input$year, input$scope_1)
        
        APP_DATA %>%
          filter(level == "school",
                 SchoolYear == input$year,
                 DistrictName == input$scope_1) %>%
          distinct(SchoolName) %>%
          pull(SchoolName) %>%
          sort()
      })
    
    observeEvent(input$scope_1, {
      choices <- school_choices()
      
      updateSelectizeInput(inputId = "scope_2",
                           choices = choices,
                           selected = choices[1],
                           server = T)
    })
    # <<< END EDIT <<<
    
    
    # ==== MAIN FILTERED DATASET (EDIT HERE) ====
    # >>> EDIT HERE >>>
    # This is the main reactive dataset used by the outputs below.
    # If you change the filters in ui.R, come back here and make the same update.
    filtered_data <- 
      reactive({req(input$year, input$scope_1, input$scope_2)
        
        data_filtered(data = APP_DATA,
                      year = input$year,
                      scope_1 = input$scope_1,
                      scope_2 = input$scope_2)
      })
    # <<< END EDIT <<<
    
    
    # ==== TABLE-READY DATA ====
    table_data <- 
      reactive({dat <- filtered_data(); underlying_data(dat)})
    
    
    # ==== PLOT OUTPUT ====
    output$main_plot <- 
      renderPlot({dat <- filtered_data(); plot_fafsa_completion(dat)}, res = 100)
    
    
    # ==== SCOPE NOTE OUTPUT ====
    output$scope_note <- 
      renderText({dat <- filtered_data(); make_scope_note(dat)})
    
    
    # ==== TABLE OUTPUT ====
    output$detail_table <- 
      renderDT({
        dat <- table_data()
        
        datatable(dat,
                  rownames = F,
                  filter = "top",
                  options = list(pageLength = nrow(dat),
                                 autoWidth = T,
                                 scrollX = T,
                                 dom = "ti"))
      })
    
    
    # ==== DOWNLOAD HANDLER (EDIT HERE) ====
    # >>> EDIT HERE >>>
    # Change the file name pattern here if the app gets reused for a different topic.
    output$download_data <- 
      downloadHandler(filename = function() {paste0("fafsa_completion_", Sys.Date(), ".csv")},
                      content = function(file) {write_csv(table_data(), file)})}
    # <<< END EDIT <<<









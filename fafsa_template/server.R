# --------------------------- server.R -----------------------------------------
# PURPOSE:
# - define server-side reactive logic
# - filter and summarize data based on user selections
# - render the main plot, scope note, and detail table
# - provide filtered data for download

server <- function(input, output, session) {
  
  # ---------------------------------------------------------------------------
  # 1) Dynamic input updates
  # ---------------------------------------------------------------------------
  
  # 1a) District choices from year
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
  
  # 1b) School choices from district
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
  
  
  # ---------------------------------------------------------------------------
  # 2) Main filtered dataset
  # ---------------------------------------------------------------------------
  filtered_data <- 
    reactive({req(input$year,
                  input$scope_1, 
                  input$scope_2)
      
      data_filtered(data = APP_DATA,
                    year = input$year,
                    scope_1 = input$scope_1,
                    scope_2 = input$scope_2)
    })
  
  # ---------------------------------------------------------------------------
  # 3) Table-ready data
  # ---------------------------------------------------------------------------
  table_data <- 
    reactive({
      dat <- filtered_data()
      underlying_data(dat)
    })
  
  # ---------------------------------------------------------------------------
  # 4) Main plot output
  # ---------------------------------------------------------------------------
  output$main_plot <- 
    renderPlot({
      dat <- filtered_data()
      plot_fafsa_completion(dat)
    }, res = 125)
  
  # ---------------------------------------------------------------------------
  # 5) Scope note output
  # ---------------------------------------------------------------------------
  output$scope_note <- 
    renderText({
      dat <- filtered_data()
      make_scope_note(dat)
    })
  
  # ---------------------------------------------------------------------------
  # 6) Table output
  # ---------------------------------------------------------------------------
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
  
  # ---------------------------------------------------------------------------
  # 7) Download filtered data
  # ---------------------------------------------------------------------------
  output$download_data <- 
    downloadHandler(filename = function() {paste0("fafsa_completion_", Sys.Date(), ".csv")},
                    content = function(file) {write_csv(table_data(), file)})
  
}


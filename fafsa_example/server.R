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
  
  # 1a) District choices from year range
  lea_choices <- 
    reactive({req(input$year_range)
      
      APP_DATA %>%
        filter(level == "lea", 
               SchoolYear %in% input$year_range) %>%
        distinct(DistrictName) %>%
        pull(DistrictName) %>%
        sort()
    })
  
  observeEvent(input$year_range, {
    choices <- lea_choices()
    
    updateSelectizeInput(inputId = "scope_1",
                         choices = choices,
                         selected = choices[1],
                         server = T)
  })
  
  # 1b) School choices from district
  school_choices <- 
    reactive({req(input$year_range, input$scope_1)
      
      APP_DATA %>%
        filter(level == "school", 
               SchoolYear %in% input$year_range,
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
  
  # 1c) Subgroup choices from school
  option_choices <- 
    reactive({req(input$year_range, 
                  input$scope_1, 
                  input$scope_2)
      
      fltr <-
        APP_DATA %>%
        filter(level == "school", 
               SchoolYear %in% input$year_range,
               DistrictName == input$scope_1,
               SchoolName %in% input$scope_2)
      
      gndr <-
        fltr %>% 
        distinct(gender) %>% 
        pull(gender) %>% 
        sort()
      
      rc <-
        fltr %>% 
        distinct(RaceReportTitle) %>% 
        pull(RaceReportTitle) %>% 
        sort()
      
      list("gender" = gndr, 
           "race" = rc)
    })
  
  
  observeEvent(input$scope_2, {
    choices <- option_choices()
    
    updateSelectizeInput(inputId = "option_1",
                         choices = choices$gender,
                         selected = choices$gender[1],
                         server = T)
    
    updateSelectizeInput(inputId = "option_2",
                         choices = choices$race,
                         selected = choices$race[1],
                         server = T)
  })
  
  # ---------------------------------------------------------------------------
  # 2) Main filtered dataset
  # ---------------------------------------------------------------------------
  filtered_data <- 
    reactive({req(input$scope_1, 
                  input$scope_2, 
                  input$year_range, 
                  input$option_1, 
                  input$option_2)
      
      data_filtered(data = APP_DATA,
                    scope_1 = input$scope_1,
                    scope_2 = input$scope_2,
                    year_range = input$year_range,
                    option_1 = input$option_1,
                    option_2 = input$option_2)
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


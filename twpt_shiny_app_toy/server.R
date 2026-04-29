# ==== STEP 3: server.R ====
# This file is the reactive wiring for the app.
#
# This is where the app connects:
# - input values coming from ui.R
# - output objects going back to ui.R
#
# In this app:
# - input$scope_1 = the selected county
# - input$scope_2 = the selected LEA
#
# And the outputs sent back to the UI are:
# - output$main_plot
# - output$scope_note
# - output$detail_table
# - output$download_data
#
# The easiest way to remember this file:
# - req() waits until some value is available
# - reactive() computes live values that should update automatically
# - observeEvent() takes an action when something changes
# - render*() turns reactive values into visible outputs

server <-
  function(input, output, session) {
    
    # ==== reactive(): live LEA-choice generator ====
    # This reactive expression builds the valid LEA list for the selected county.
    #
    # What it does:
    # - waits until the county input exists
    # - filters APP_DATA to that county
    # - pulls the distinct LEA names
    # - returns the sorted set of valid choices
    #
    # So lea_choices() is a reusable "county -> LEA list" calculator.
    lea_choices <-
      reactive({req(input$scope_1)
        
        APP_DATA %>%
          filter(County_Name == input$scope_1) %>%
          distinct(lea) %>%
          pull(lea) %>%
          sort()
      })
    
    # ==== observeEvent(): when county changes, update LEA dropdown ====
    # This observer does not return a value for reuse.
    # Instead, it performs an action in the interface.
    #
    # Meaning:
    # - when the county changes
    # - recompute the valid LEA choices
    # - push those new choices into the scope_2 dropdown
    # - default to the first LEA in the updated list
    #
    # Memory trick:
    # - lea_choices() computes
    # - observeEvent(input$scope_1, ...) acts
    observeEvent(input$scope_1, {
      choices <- lea_choices()
      
      updateSelectizeInput(session = session,
                           inputId = "scope_2",
                           choices = choices,
                           selected = choices[1],
                           server = T)
    })
    
    # ==== reactive(): the central filtered dataset ====
    # This is the main reactive object in the app.
    #
    # It waits until both sidebar filters exist, then calls data_filtered()
    # from global.R to return only the rows for the selected:
    # - county
    # - LEA
    #
    # This matters because several outputs all depend on the same filtered data.
    # Instead of rewriting the filtering logic in multiple places, the app
    # computes it once here and reuses it everywhere else.
    filtered_data <-
      reactive({req(input$scope_1, input$scope_2)
        
        data_filtered(data = APP_DATA,
                      scope_1 = input$scope_1,
                      scope_2 = input$scope_2)
      })
    
    # ==== reactive(): table-ready version of the filtered data ====
    # This is a small helper reactive used by both:
    # - the DT table
    # - the download button
    #
    # It takes the filtered rows and passes them to underlying_data() in global.R,
    # which formats the columns for display.
    table_data <-
      reactive({
        dat <- filtered_data()
        underlying_data(dat)
      })
    
    # ==== output$main_plot + renderPlot() ====
    # This sends the main plot back to plotOutput("main_plot") in ui.R.
    #
    # The plotting code itself lives in global.R inside plot_staffing_trend().
    # So server.R is not building the chart directly. It is handing the filtered
    # data to a helper function and returning the finished plot.
    #
    # In this app, the plot is a longitudinal line chart of StudentsPerTeacher
    # across school years for the selected LEA.
    output$main_plot <-
      renderPlot({
        dat <- filtered_data()
        plot_staffing_trend(dat)
      }, res = 125)
    
    # ==== output$scope_note + renderText() ====
    # This sends a text summary back to textOutput("scope_note") in ui.R.
    #
    # The text is created by make_scope_note() in global.R.
    # Its job is to remind the user which LEA and county they are viewing.
    output$scope_note <-
      renderText({
        dat <- filtered_data()
        make_scope_note(dat)
      })
    
    # ==== output$detail_table + renderDT() ====
    # This sends the formatted data table back to DTOutput("detail_table") in ui.R.
    #
    # It uses:
    # - table_data() for the prepared dataset
    # - datatable() from DT for the interactive display
    #
    # So this is the app's table-rendering step.
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
    
    # ==== output$download_data + downloadHandler() ====
    # This creates the downloadable CSV tied to the current filters.
    #
    # Important idea:
    # the download uses the same reactive table_data() object as the table tab.
    # That keeps the displayed data and the downloaded data in sync.
    output$download_data <-
      downloadHandler(
        filename = function() {paste0("twpt_filtered_data_", Sys.Date(), ".csv")},
        content = function(file) {write_csv(table_data(), file)})
  }




# ==== STEP 4: ui.R ====
# This file controls what people see.
#
# This is the last step in the full app flow:
# - display the sidebar controls
# - display the output placeholders
# - arrange the app into a sidebar + tabbed main panel layout
#
# Main idea to remember:
# ui.R defines the visible structure of the app.
# If you rename an input or output id here, you must rename it in server.R too.

ui <-
  page_sidebar(window_title = APP_TITLE,
               theme = bs_theme(),
               
               # ==== SIDEBAR ====
               # The sidebar is the control center for the app.
               # It contains:
               # - the app title
               # - a short description
               # - the filters
               # - the download button
               sidebar = sidebar(open = "always",
                                 
                                 # App title and intro text
                                 h3(APP_TITLE),
                                 p("A simple instructional app built from twpt.csv."),
                                 
                                 # scope_1 = County
                                 # This input sends the selected county to server.R as input$scope_1.
                                 selectizeInput(inputId = "scope_1",
                                                label = LABELS$scope_1,
                                                choices = SCOPE_1_CHOICES,
                                                selected = DEFAULTS$scope_1,
                                                multiple = F),
                                 
                                 # scope_2 = LEA
                                 # This input sends the selected LEA to server.R as input$scope_2.
                                 # Its choices are updated dynamically when the county changes.
                                 selectizeInput(inputId = "scope_2",
                                                label = LABELS$scope_2,
                                                choices = SCOPE_2_CHOICES,
                                                selected = DEFAULTS$scope_2,
                                                multiple = F),
                                 
                                 hr(),
                                 
                                 # This button downloads the same filtered data shown in the table tab.
                                 downloadButton(outputId = "download_data",
                                                label = "Download filtered data")),
               
               # ==== MAIN BODY ====
               # The main body uses tabbed panels so the user can switch between:
               # - a visual summary
               # - the underlying data
               #
               # This design allows the filters to stay fixed in the sidebar
               # while the user changes views in the main panel.
               navset_card_tab(
                 
                 # Plot tab:
                 # - textOutput("scope_note") shows the context sentence
                 # - plotOutput("main_plot") shows the longitudinal line chart
                 nav_panel(LABELS$tab_plot,
                           textOutput("scope_note"),
                           plotOutput("main_plot")),
                 
                 # Data tab:
                 # - DTOutput("detail_table") shows the interactive filtered table
                 nav_panel(LABELS$tab_data,
                           DTOutput("detail_table"))))




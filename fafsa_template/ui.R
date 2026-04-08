# ----------------------------- ui.R -------------------------------------------
# PURPOSE:
# - define the app user interface
# - configure the page layout, theme, and sidebar controls
# - display the main plot and supporting outputs
# - apply shared styling from styles.css

ui <-
  page_sidebar(window_title = APP_TITLE,
               
               fillable = F,
               
               theme = bs_theme(version = 5,
                                primary = dde_orange,
                                bg = dde_bg,
                                fg = dde_blue_dark),
               
               # -------------------------------------------------------------------------
               # 1) Load the custom CSS file from the www folder
               # -------------------------------------------------------------------------
               tags$head(tags$link(rel = "stylesheet", type = "text/css", href = "styles.css")),
               
               # -------------------------------------------------------------------------
               # 2) Sidebar controls
               # -------------------------------------------------------------------------
               sidebar = sidebar(width = 300,
                                 open = "always",
                                 
                                 # 2a) Branding and intro
                                 title = div(class = "brand-wrap",
                                             img(src = "Website-Header.png",
                                                 class = "brand-logo",
                                                 alt = APP_TITLE)),
                                 
                                 hr(class = "tight-hr"),
                                 
                                 h4(APP_TITLE, class = "app-title"),
                                 
                                 p(class = "sidebar-intro",
                                   "Track monthly FAFSA completion rates by month for a school, its district, and the state."),
                                 
                                 # 2b) Download
                                 div(class = "download-wrap",
                                     downloadButton(outputId = "download_data",
                                                    label = "Download filtered data")),
                                 
                                 hr(class = "tight-hr"),
                                 
                                 # 2c) Filters
                                 selectizeInput(inputId = "year",
                                                label = LABELS$year,
                                                choices = YEAR,
                                                selected = DEFAULTS$year,
                                                multiple = F),
                                 
                                 selectizeInput(inputId = "scope_1",
                                                label = LABELS$scope_1,
                                                choices = SCOPE_1_CHOICES,
                                                selected = DEFAULTS$scope_1,
                                                multiple = F),
                                 
                                 selectizeInput(inputId = "scope_2",
                                                label = LABELS$scope_2,
                                                choices = SCOPE_2_CHOICES,
                                                selected = DEFAULTS$scope_2,
                                                multiple = F)
                                 ),
               
               # -------------------------------------------------------------------------
               # 3) Main content
               # -------------------------------------------------------------------------
               navset_card_tab(full_screen = T,
                               
                               nav_panel(LABELS$tab_plot,
                                         
                                         card(class = "scope-note-card",
                                              card_body(textOutput("scope_note", inline = T))),
                                         
                                         card(class = "plot-card",
                                              card_body(plotOutput("main_plot")))
                                         ),
                               
                               nav_panel(LABELS$tab_data,
                                 card(class = "table-card",
                                      min_height = "760px",
                                      card_body(DTOutput("detail_table"))))
                               )
               )

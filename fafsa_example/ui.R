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
               # 1) Shared assets
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
                                   "Track cumulative FAFSA completion rates by month for a school, its district, and the state."),
                                 
                                 # 2b) Download
                                 div(class = "download-wrap",
                                     downloadButton(outputId = "download_data",
                                                    label = "Download filtered data")),
                                 
                                 hr(class = "tight-hr"),
                                 
                                 sliderInput(inputId = "year_range",
                                             label = "School year range",
                                             min = min(YEAR_RANGE),
                                             max = max(YEAR_RANGE),
                                             value = DEFAULTS$year_range,
                                             step = 1,
                                             sep = ""),
                                 
                                 # 2c) Filters
                                 selectizeInput(inputId = "scope_1",
                                                label = "District",
                                                choices = SCOPE_1_CHOICES,
                                                selected = DEFAULTS$scope_1,
                                                multiple = F),
                                 
                                 selectizeInput(inputId = "scope_2",
                                                label = "School",
                                                choices = SCOPE_2_CHOICES,
                                                selected = DEFAULTS$scope_2,
                                                multiple = F),
                                 
                                 selectizeInput(inputId = "option_1",
                                                label = "Gender",
                                                choices = OPTION_1_CHOICES,
                                                selected = DEFAULTS$option_1,
                                                multiple = T,
                                                options = list(plugins = list("remove_button"))),
                                 
                                 selectizeInput(inputId = "option_2",
                                                label = "Race",
                                                choices = OPTION_2_CHOICES,
                                                selected = DEFAULTS$option_2,
                                                multiple = T,
                                                options = list(plugins = list("remove_button")))
                                 ),
               
               # -------------------------------------------------------------------------
               # 3) Main content
               # -------------------------------------------------------------------------
               navset_card_tab(full_screen = T,
                               
                               nav_panel("FAFSA completion trend",
                                         
                                         card(class = "scope-note-card",
                                              card_body(textOutput("scope_note", inline = T))),
                                         
                                         card(class = "plot-card",
                                              card_body(plotOutput("main_plot")))
                                         ),
                               
                               nav_panel("Underlying data",
                                 card(class = "table-card",
                                      min_height = "760px",
                                      card_body(DTOutput("detail_table"))))
                               )
               )

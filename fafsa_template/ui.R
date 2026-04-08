# ==== TEMPLATE OVERVIEW ====
# This file controls what people see.
#
# This is where to change:
# - the layout
# - sidebar text
# - branding
# - tab names
# - where outputs show up
#
# One small but important thing:
# if you rename an input or output id here, go rename it in server.R too


# ==== UI LAYOUT ====

ui <- 
  page_sidebar(window_title = APP_TITLE,
               
               fillable = F,
               
               theme = bs_theme(version = 5,
                                primary = dde_orange,
                                bg = dde_bg,
                                fg = dde_blue_dark),
               
               # ==== STYLESHEET ====
               # Keep visual tweaks in styles.css instead of all over the UI (LLMs are really good at editing css).
               tags$head(tags$link(rel = "stylesheet",
                                   type = "text/css",
                                   href = "styles.css")),
               
               # ==== SIDEBAR ====
               sidebar = sidebar(width = 300,
                                 open = "always",
                                 
                                 # ==== BRANDING AND INTRO (EDIT HERE) ====
                                 # >>> EDIT HERE >>>
                                 # Swap the logo, title, and intro text here when you reuse the app shell.
                                 title = div(class = "brand-wrap",
                                             img(src = "Website-Header.png",
                                                 class = "brand-logo",
                                                 alt = APP_TITLE)),
                                 
                                 hr(class = "tight-hr"),
                                 
                                 h4(APP_TITLE, class = "app-title"),
                                 
                                 p(class = "sidebar-intro",
                                   "Track monthly FAFSA completion rates by month for a school, its district, and the state."),
                                 # <<< END EDIT <<<
                                 
                                 # ==== DOWNLOAD DATA BUTTON====
                                 div(class = "download-wrap",
                                     downloadButton(outputId = "download_data",
                                                    label = "Download filtered data")),
                                 
                                 hr(class = "tight-hr"),
                                 
                                 # ==== FILTERS (EDIT HERE) ====
                                 # >>> EDIT HERE >>>
                                 # These controls drive the filtering in server.R.
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
                                                multiple = F)),
               # <<< END EDIT <<<
               
               # ==== MAIN CONTENT ====
               navset_card_tab(full_screen = T,
                               
                               # ==== PLOT TAB (EDIT HERE) ====
                               # >>> EDIT HERE >>>
                               nav_panel(LABELS$tab_plot,
                                         
                                         card(class = "scope-note-card",
                                              card_body(textOutput("scope_note", inline = T))),
                                         
                                         card(class = "plot-card", 
                                              card_body(plotOutput("main_plot")))),
                               # <<< END EDIT <<<
                               
                               # ==== DATA TAB (EDIT HERE) ====
                               # >>> EDIT HERE >>>
                               nav_panel(LABELS$tab_data,
                                         card(class = "table-card",
                                              min_height = "760px",
                                              card_body(DTOutput("detail_table")))))
               
               # <<< END EDIT <<<
               )









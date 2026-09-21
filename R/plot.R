# =============================================================================
# FAFSA APP: PLOT AND CHART-TEXT FUNCTIONS
#
# These are ordinary R functions. They do not read Shiny inputs directly.
# server.R passes the shared analysis_data() object into them and then uses
# renderPlot() / renderText() to send their results to ui.R.
#
# Keeping this file separate makes the distinction clear:
#
# R/analysis.R = calculate the measure
# R/plot.R     = present the measure
# =============================================================================


# ==== PLOT ====

plot_fafsa_completion <- 
  function(analysis) {
    
    # ui.R normally hides the plot when no receipt months exist, but returning
    # a simple fallback plot keeps this function safe to use on its own too.
    if (!isTRUE(analysis$has_data)) {
      return(
        ggplot() +
          annotate(
            "text",
            x = 0,
            y = 0,
            label = analysis$empty_reason
          ) +
          theme_void()
      )
    }
    
    plot_data <- analysis$data
    
    ggplot(
      plot_data,
      aes(
        x = month_label,
        y = cumulative_completion_rate,
        fill = comparison,
        label = label
      )
    ) +
      geom_col(
        position = position_dodge(width = 0.9),
        width = 0.8,
        na.rm = TRUE
      ) +
      geom_label(
        show.legend = FALSE,
        size = 3,
        fontface = "bold",
        color = dde_surface,
        position = position_dodge(width = 0.9),
        vjust = -0.25,
        na.rm = TRUE
      ) +
      coord_cartesian(clip = "off") +
      scale_y_continuous(
        labels = percent_format(accuracy = 1),
        limits = c(0, 1),
        expand = expansion(mult = c(0, 0.06))
      ) +
      scale_fill_manual(
        values = c(
          School = dde_orange,
          LEA = dde_blue,
          State = dde_muted
        ),
        labels = c(
          School = "School",
          LEA = "LEA",
          State = "State"
        ),
        drop = FALSE
      ) +
      labs(
        title = NULL,
        x = NULL,
        y = NULL,
        fill = NULL
      ) +
      theme_minimal(base_size = 12) +
      theme(
        # CSS supplies the surrounding gray chart area. Keep the ggplot itself
        # white so it reads as a separate plotting surface.
        plot.background = element_rect(fill = dde_surface, color = NA),
        panel.background = element_rect(fill = dde_surface, color = NA),

        # Light horizontal guides keep attention on the bars and labels.
        panel.grid.major.x = element_blank(),
        panel.grid.major.y = element_line(
          color = "#e4eaf0",
          linewidth = 0.45
        ),
        panel.grid.minor = element_blank(),

        axis.text.x = element_text(
          color = dde_muted,
          size = 10
        ),
        axis.text.y = element_text(
          color = dde_muted,
          size = 10
        ),

        # The legend is drawn in ui.R so CSS can position it independently of
        # the ggplot panel.
        legend.position = "none",

        plot.margin = margin(4, 12, 10, 12)
      )
  }


# ==== CHART TITLE ====

make_chart_title <-
  function(analysis) {
    analysis$school_name
  }


# ==== CHART SUBTITLE ====

make_chart_subtitle <- 
  function(analysis) {
    
    if (!isTRUE(analysis$has_data)) {
      return(analysis$empty_reason)
    }
    
    first_year <- format(analysis$first_month, "%Y")
    last_year  <- format(analysis$last_month, "%Y")

    # Include calendar years in the month span only where they help orient the
    # reader. Examples:
    #   January-August 2024
    #   August 2025-May 2026
    month_span <-
      if (first_year == last_year) {
        paste0(
          month_name(analysis$first_month),
          "\u2013",
          month_name(analysis$last_month),
          " ",
          last_year
        )
      } else {
        paste0(
          month_name(analysis$first_month),
          " ",
          first_year,
          "\u2013",
          month_name(analysis$last_month),
          " ",
          last_year
        )
      }

    paste0(
      "Cumulative FAFSA completion \u2022 ",
      month_span,
      " \u2022 SY",
      school_year_label(analysis$year)
    )
  }

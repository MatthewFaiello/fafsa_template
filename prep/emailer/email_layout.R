# =============================================================================
# BIWEEKLY FAFSA EMAILS — HTML LAYOUT
# =============================================================================
# Read this AFTER run_biweekly_email.R to see how the email is assembled.
#
# These are ORDINARY R functions that return character strings containing HTML.
# The main script passes school-specific values into them.
# No data files are read and no emails are sent from this file.
#
#   make_email_html() [main script]
#       -> build_snapshot_table() + build_email_body() [this file]
#       -> build_button() and formatting helpers [this file]
#
# Layout HTML is intentionally left explicit so that the approved email's
# appearance and Outlook compatibility remain unchanged.
# =============================================================================

# ==== 1. FORMAT DATA FOR EMAIL TEXT ==========================================
# Missing values display as blanks; htmlEscape() protects dynamic values
# such as school names from being interpreted as HTML markup.

nb <- function(x) {
  ifelse(is.na(x), "", x)
}

safe <- function(x) {
  htmltools::htmlEscape(nb(x), attribute = FALSE)
}

# Completion rates are already on a 0–100 scale (e.g., 22.0, not 0.22).
fmt_pct <- function(x) {
  if (length(x) == 0 || is.na(x)[1]) {
    return("")
  }
  
  paste0(formatC(x[1], format = "f", digits = 1), "%")
}

fmt_date <- function(x) {
  if (length(x) == 0 || is.na(x)[1]) {
    return("")
  }
  
  format(x[1], "%B %d, %Y")
}

# ==== 2. REUSABLE HTML COMPONENTS ===========================================
# paste0() joins HTML snippets with R values into a single string.
# The Outlook-specific markup is formatting only; no extra R logic is hidden.

# One function creates both blue dashboard and green FAFSA-help buttons.
build_button <- function(url,
                         label,
                         background = "#2ECC40",
                         width = 220) {
  
  paste0(
    "<table role='presentation' cellpadding='0' cellspacing='0' border='0' ",
    "style='margin:0 0 20px;'>",
    "<tr>",
    "<td style='font-family:Arial,sans-serif;'>",
    
    # Some Outlook desktop versions need VML for clickable rounded buttons.
    "<!--[if mso]>",
    "<v:roundrect xmlns:v='urn:schemas-microsoft-com:vml' ",
    "xmlns:w='urn:schemas-microsoft-com:office:word' ",
    "href='", safe(url), "' ",
    "style='height:44px;v-text-anchor:middle;width:", width, "px;' ",
    "arcsize='12%' stroke='f' fillcolor='", background, "'>",
    "<w:anchorlock/>",
    "<center style='color:#ffffff;font-family:Arial,sans-serif;",
    "font-size:15px;font-weight:bold;'>",
    safe(label),
    "</center>",
    "</v:roundrect>",
    "<![endif]>",
    
    # Other email clients get a regular HTML link styled as a button.
    "<!--[if !mso]><!-- -->",
    "<table role='presentation' cellpadding='0' cellspacing='0' border='0'>",
    "<tr>",
    "<td bgcolor='", background, "' ",
    "style='background:", background, ";border-radius:6px;'>",
    "<a href='", safe(url), "' target='_blank' ",
    "style='display:inline-block;padding:12px 20px;",
    "font-family:Arial,sans-serif;font-size:15px;font-weight:bold;",
    "line-height:20px;text-decoration:none;color:#ffffff;",
    "mso-line-height-rule:exactly;'>",
    safe(label),
    "</a>",
    "</td>",
    "</tr>",
    "</table>",
    "<!--<![endif]-->",
    
    "</td>",
    "</tr>",
    "</table>"
  )
}


# Build a two-date comparison table. With no archived prior refresh, show
# an explanation rather than a made-up prior value.
build_snapshot_table <- function(lea_name, as_of_current, pct_current,
                                 as_of_previous, pct_previous) {
  previous_row <-
    if (!is.na(as_of_previous) && nzchar(as_of_previous)) {
      paste0(
        "<tr><td style='padding:10px 12px;border-bottom:1px solid #e5e7eb;'>",
        safe(as_of_previous), "</td>",
        "<td style='padding:10px 12px;text-align:right;border-bottom:1px solid #e5e7eb;'>",
        "<strong>", safe(pct_previous), "</strong></td></tr>"
      )
    } else {
      "<tr><td colspan='2' style='padding:10px 12px;color:#6b7280;'>An earlier archived refresh is not available yet.</td></tr>"
    }

  paste0(
    "<table role='presentation' width='80%' cellpadding='0' cellspacing='0' ",
    "style='margin:22px 0 18px;background:#f7f9fc;border:1px solid #e5e7eb;border-radius:10px;'>",
    "<tr><td style='padding:18px;font-family:Arial,sans-serif;color:#111827;font-size:14px;'>",
    "<p style='font-size:18px;font-weight:bold;margin:0 0 12px;'>FAFSA Snapshot</p>",
    "<p style='margin:0 0 14px;'>For <strong>", safe(lea_name), "</strong>:</p>",
    "<table role='presentation' width='100%' cellpadding='0' cellspacing='0' style='border-collapse:collapse;'>",
    "<tr bgcolor='#eef2f7'>",
    "<th style='padding:10px 12px;text-align:left;'>As Of</th>",
    "<th style='padding:10px 12px;text-align:right;'>FAFSA Completion</th></tr>",
    "<tr><td style='padding:10px 12px;border-bottom:1px solid #e5e7eb;'>",
    safe(as_of_current), "</td>",
    "<td style='padding:10px 12px;text-align:right;border-bottom:1px solid #e5e7eb;'>",
    "<strong>", safe(pct_current), "</strong></td></tr>",
    previous_row,
    "</table></td></tr></table>"
  )
}


# ==== 3. COMPOSE THE COMPLETE EMAIL =========================================
# The main script supplies the school name, snapshot HTML, logo, and links.
# Sections appear in the same order as they will appear in the message.
# build_email_body() returns a string; Outlook delivery happens in the main script.
build_email_body <- function(lea_name,
                             snapshot_block,
                             logo_src,
                             dashboard_url,
                             support_booking_url,
                             contact_email) {
  
  paste0(
    "<table width='80%' cellpadding='0' cellspacing='0' ",
    "role='presentation' lang='en' ",
    "style='font-family:Arial,sans-serif;color:#333;line-height:1.5;'>",
    
    "<tr>",
    "<td style='padding:0;font-family:Arial,sans-serif;",
    "font-size:16px;line-height:22px;color:#333333;",
    "mso-line-height-rule:exactly;'>",
    
    # Greeting
    "<p style='font-size:16px;margin:0 0 14px;",
    "font-family:Arial,sans-serif;line-height:22px;color:#333333;'>",
    "Hello ", safe(lea_name), "!",
    "</p>",
    
    # Intro
    "<p style='margin:0 0 14px;font-size:14px;line-height:20px;",
    "font-family:Arial,sans-serif;color:#333333;'>",
    "<strong>Thank you</strong> for your continued support in helping students ",
    "complete the FAFSA. Your efforts are crucial to ensuring students have ",
    "access to financial aid and higher education opportunities.",
    "</p>",
    
    "<p style='margin:0 0 14px;font-size:14px;line-height:20px;",
    "font-family:Arial,sans-serif;color:#333333;'>",
    "A <strong>completed FAFSA is required</strong> for the ",
    "<strong>SEED Scholarship</strong> at DTCC and UD’s Associate of Arts ",
    "program, as well as the Inspire Scholarship at Delaware State University.",
    "</p>",
    
    "<hr style='margin:25px 0;border:0;border-top:1px solid #cccccc;",
    "height:1px;line-height:1px;' />",
    
    # Biweekly data
    "<p style='margin:0 0 14px;font-size:14px;line-height:20px;",
    "font-family:Arial,sans-serif;color:#333333;'>",
    "Here is your <strong>biweekly FAFSA completion update</strong>, ",
    "showing the latest available snapshot and prior update when available. You can also view your school’s ",
    "<strong>student-level FAFSA completion status</strong> anytime through EdInsight.",
    "</p>",
    
    snapshot_block,
    
    # Dashboard
    "<p style='margin:16px 0 10px;font-size:14px;line-height:20px;",
    "font-family:Arial,sans-serif;color:#333333;'>",
    "For a broader view of monthly school, LEA, and statewide FAFSA completion trends:",
    "</p>",
    
    build_button(
      url = dashboard_url,
      label = "View FAFSA Completion Dashboard",
      background = "#0066A1",
      width = 300
    ),
    
    # How this helps
    "<p style='margin:16px 0 6px;font-size:14px;line-height:20px;",
    "font-family:Arial,sans-serif;color:#333333;font-weight:bold;'>",
    "How this helps your team:",
    "</p>",
    
    "<ul style='margin:0 0 16px 20px;padding:0;font-size:14px;",
    "line-height:20px;font-family:Arial,sans-serif;color:#333333;'>",
    "<li>Spot where additional outreach may be needed to support seniors</li>",
    "<li>Track progress over time with school- and statewide trends</li>",
    "<li>Target individual students using EdInsight’s student-level view</li>",
    "</ul>",
    
    # Stand By Me
    "<p style='margin:0 0 16px;font-size:14px;line-height:20px;",
    "font-family:Arial,sans-serif;color:#333333;'>",
    "Please also encourage students and families to use the ",
    "<strong>free one-on-one FAFSA completion support</strong> provided by ",
    "Stand By Me, in person or via Zoom.",
    "</p>",
    
    build_button(
      url = support_booking_url,
      label = "Book 1:1 FAFSA Help",
      background = "#2ECC40",
      width = 220
    ),
    
    # Closing
    "<p style='margin:0 0 20px;font-style:italic;color:#555555;",
    "font-size:14px;line-height:20px;font-family:Arial,sans-serif;'>",
    "We look forward to partnering with you to increase FAFSA completion rates ",
    "at your school.",
    "</p>",
    
    "<p style='margin:0 0 6px;font-size:14px;line-height:20px;",
    "font-family:Arial,sans-serif;color:#333333;'>",
    "Thank you!<br/>",
    "Delaware Higher Education Office<br/>",
    "Delaware Department of Education",
    "</p>",
    
    # Footer
    "<div style='margin-top:18px;font-family:Arial,sans-serif;",
    "font-size:13px;line-height:18px;color:#555555;'>",
    
    "<img src='", logo_src, "' width='300' ",
    "style='max-width:100%;height:auto;margin:0 0 12px;' ",
    "alt='Delaware DOE Logo'/>",
    
    "<p style='font-size:13px;color:#555555;margin:0 0 4px;",
    "font-family:Arial,sans-serif;line-height:18px;'>",
    "For questions or feedback, please contact ",
    
    "<a href='mailto:", safe(contact_email), "' ",
    "style='color:#0066cc;text-decoration:underline;'>",
    "Delaware Higher Education Office",
    "</a>.",
    
    "</p>",
    "</div>",
    
    "</td>",
    "</tr>",
    "</table>"
  )
}



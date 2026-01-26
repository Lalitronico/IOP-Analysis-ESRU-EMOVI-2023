# ============================================================================
# 07_cohort_analysis.R - Cohort Analysis of IOp Trends
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Analyze temporal trends in IOp across birth cohorts
# ============================================================================

# Load setup and previous scripts
source(here::here("src", "R", "00_setup.R"))
source(here::here("src", "R", "05_iop_metrics.R"))

log_msg("Starting cohort analysis")

# ============================================================================
# 1. Define Cohort Groups
# ============================================================================

# EMOVI typically has birth cohorts in 10-year bands
# Adjust these definitions based on actual data
COHORT_DEFINITIONS <- list(
  # Option 1: Use existing cohorte variable directly
  use_existing = TRUE,


  # Option 2: Create from birth year if needed
  birth_year_breaks = c(-Inf, 1959, 1969, 1979, 1989, 1999, Inf),
  birth_year_labels = c("Pre-1960", "1960-1969", "1970-1979",
                        "1980-1989", "1990-1999", "2000+")
)

# Circumstances to use (excluding cohorte since we stratify by it)
COHORT_CIRCUMSTANCES <- c(
  "educp",        # Father's education
  "educm",        # Mother's education
  "clasep",       # Father's occupation
  "sexo",         # Sex
  "indigenous",   # Indigenous language
  "skin_tone",    # Skin tone
  "region_14",    # Region at 14
  "rural_14"      # Rural/urban at 14
)

# ============================================================================
# 2. Prepare Cohort Data
# ============================================================================

#' Prepare data with cohort groupings
#' @param df Raw data frame
#' @return Data frame with standardized cohort variable
prepare_cohort_data <- function(df) {

  # Check if cohorte exists
  if ("cohorte" %in% names(df)) {
    log_msg("Using existing 'cohorte' variable")

    # Get unique values
    cohorts <- unique(df$cohorte)
    log_msg("Cohorts found: ", paste(cohorts, collapse = ", "))

    # Ensure it's a factor with proper ordering
    if (is.factor(df$cohorte)) {
      df$cohort_group <- df$cohorte
    } else {
      df$cohort_group <- factor(df$cohorte)
    }

  } else if ("edad" %in% names(df)) {
    log_msg("Creating cohort from 'edad' (age)")

    # Assuming survey year is 2023
    survey_year <- 2023
    df$birth_year <- survey_year - as.numeric(df$edad)

    df$cohort_group <- cut(
      df$birth_year,
      breaks = COHORT_DEFINITIONS$birth_year_breaks,
      labels = COHORT_DEFINITIONS$birth_year_labels,
      right = TRUE
    )

  } else {
    stop("Cannot create cohort groups: neither 'cohorte' nor 'edad' found")
  }

  return(df)
}

# ============================================================================
# 3. IOp by Cohort Analysis
# ============================================================================

#' Calculate IOp for each cohort separately
#' @param df Data frame with cohort_group variable
#' @param outcome Outcome variable name
#' @param circumstances Vector of circumstance variable names
#' @param min_n Minimum sample size per cohort
#' @return Tibble with IOp by cohort
calculate_iop_by_cohort <- function(df,
                                     outcome = "ingc_pc",
                                     circumstances = COHORT_CIRCUMSTANCES,
                                     min_n = 500) {

  log_msg("=== IOp by Cohort Analysis ===")

  # Get cohorts
  cohorts <- levels(df$cohort_group)
  if (is.null(cohorts)) cohorts <- unique(df$cohort_group)
  cohorts <- cohorts[!is.na(cohorts)]

  log_msg("Analyzing ", length(cohorts), " cohorts")

  results <- list()

  for (cohort in cohorts) {
    log_msg("\n--- Cohort: ", cohort, " ---")

    # Subset data
    df_cohort <- df %>% filter(cohort_group == cohort)
    log_msg("  Total N: ", nrow(df_cohort))

    # Prepare analysis data
    vars_needed <- c(outcome, circumstances)
    df_analysis <- df_cohort %>%
      select(any_of(vars_needed)) %>%
      drop_na()

    log_msg("  Complete cases: ", nrow(df_analysis))

    if (nrow(df_analysis) < min_n) {
      log_msg("  Skipping: Sample too small (< ", min_n, ")")
      next
    }

    # Get available circumstances
    available <- circumstances[circumstances %in% names(df_analysis)]

    if (length(available) < 3) {
      log_msg("  Skipping: Too few circumstances available")
      next
    }

    # Fit ctree
    formula <- as.formula(paste(outcome, "~", paste(available, collapse = " + ")))

    ctrl <- partykit::ctree_control(
      mincriterion = 0.95,
      minsplit = max(50, nrow(df_analysis) / 50),  # Adapt to sample size
      minbucket = max(25, nrow(df_analysis) / 100),
      maxdepth = 5
    )

    model <- tryCatch(
      partykit::ctree(formula, data = df_analysis, control = ctrl),
      error = function(e) {
        log_msg("  Error: ", e$message)
        return(NULL)
      }
    )

    if (is.null(model)) next

    # Calculate IOp metrics
    type_means <- predict(model, type = "response")
    types <- predict(model, type = "node")
    y <- df_analysis[[outcome]]

    iop_gini <- calculate_iop_share(y, type_means, metric = "gini")
    iop_mld <- calculate_iop_share(y, type_means, metric = "mld")
    iop_rsq <- calculate_iop_rsq(y, type_means)

    # Variable importance
    varimp <- tryCatch({
      vi <- partykit::varimp(model)
      sort(vi, decreasing = TRUE)
    }, error = function(e) NULL)

    # Top 3 circumstances
    top3 <- if (!is.null(varimp)) {
      paste(names(head(varimp, 3)), collapse = ", ")
    } else "N/A"

    # Store results
    results[[cohort]] <- tibble(
      cohort = cohort,
      n_obs = nrow(df_analysis),
      n_types = length(unique(types)),
      gini_total = iop_gini$ineq_total,
      iop_gini = iop_gini$iop_share,
      iop_mld = iop_mld$iop_share,
      iop_rsq = iop_rsq,
      top_circumstances = top3
    )

    log_msg("  IOp (Gini): ", round(iop_gini$iop_share * 100, 1), "%")
    log_msg("  IOp (R²): ", round(iop_rsq * 100, 1), "%")
    log_msg("  Total Gini: ", round(iop_gini$ineq_total, 3))
    log_msg("  Types: ", length(unique(types)))
  }

  # Combine results
  cohort_results <- bind_rows(results)

  return(cohort_results)
}

# ============================================================================
# 4. Trend Analysis
# ============================================================================

#' Analyze trends in IOp across cohorts
#' @param cohort_results Results from calculate_iop_by_cohort
#' @return List with trend statistics
analyze_cohort_trends <- function(cohort_results) {

  log_msg("\n=== Cohort Trend Analysis ===")

  if (nrow(cohort_results) < 3) {
    warning("Too few cohorts for trend analysis")
    return(NULL)
  }

  # Add numeric cohort order for trend analysis
  cohort_results <- cohort_results %>%
    mutate(cohort_order = row_number())

  # Linear trend in IOp (Gini)
  trend_gini <- lm(iop_gini ~ cohort_order, data = cohort_results)
  trend_rsq <- lm(iop_rsq ~ cohort_order, data = cohort_results)
  trend_total <- lm(gini_total ~ cohort_order, data = cohort_results)

  # Trend statistics
  trends <- list(
    iop_gini = list(
      slope = coef(trend_gini)[2],
      pvalue = summary(trend_gini)$coefficients[2, 4],
      direction = ifelse(coef(trend_gini)[2] > 0, "increasing", "decreasing")
    ),
    iop_rsq = list(
      slope = coef(trend_rsq)[2],
      pvalue = summary(trend_rsq)$coefficients[2, 4],
      direction = ifelse(coef(trend_rsq)[2] > 0, "increasing", "decreasing")
    ),
    total_inequality = list(
      slope = coef(trend_total)[2],
      pvalue = summary(trend_total)$coefficients[2, 4],
      direction = ifelse(coef(trend_total)[2] > 0, "increasing", "decreasing")
    )
  )

  # Summary statistics
  summary_stats <- tibble(
    metric = c("IOp (Gini)", "IOp (R²)", "Total Inequality (Gini)"),
    earliest = c(
      cohort_results$iop_gini[1],
      cohort_results$iop_rsq[1],
      cohort_results$gini_total[1]
    ),
    latest = c(
      tail(cohort_results$iop_gini, 1),
      tail(cohort_results$iop_rsq, 1),
      tail(cohort_results$gini_total, 1)
    ),
    change_pp = c(
      (tail(cohort_results$iop_gini, 1) - cohort_results$iop_gini[1]) * 100,
      (tail(cohort_results$iop_rsq, 1) - cohort_results$iop_rsq[1]) * 100,
      (tail(cohort_results$gini_total, 1) - cohort_results$gini_total[1]) * 100
    ),
    trend_direction = c(
      trends$iop_gini$direction,
      trends$iop_rsq$direction,
      trends$total_inequality$direction
    ),
    trend_pvalue = c(
      trends$iop_gini$pvalue,
      trends$iop_rsq$pvalue,
      trends$total_inequality$pvalue
    )
  )

  log_msg("\nTrend Summary:")
  log_msg("  IOp (Gini): ", trends$iop_gini$direction,
          " (p=", round(trends$iop_gini$pvalue, 3), ")")
  log_msg("  IOp (R²): ", trends$iop_rsq$direction,
          " (p=", round(trends$iop_rsq$pvalue, 3), ")")
  log_msg("  Total Ineq: ", trends$total_inequality$direction,
          " (p=", round(trends$total_inequality$pvalue, 3), ")")

  return(list(
    trends = trends,
    summary = summary_stats
  ))
}

# ============================================================================
# 5. Visualization
# ============================================================================

#' Plot IOp trends across cohorts
#' @param cohort_results Results from calculate_iop_by_cohort
#' @param filename Output filename
#' @return ggplot object
plot_cohort_trends <- function(cohort_results, filename = "cohort_iop_trends") {

  # Reshape for plotting
  plot_data <- cohort_results %>%
    select(cohort, iop_gini, iop_rsq, gini_total) %>%
    pivot_longer(
      cols = c(iop_gini, iop_rsq, gini_total),
      names_to = "metric",
      values_to = "value"
    ) %>%
    mutate(
      metric_label = case_when(
        metric == "iop_gini" ~ "IOp Share (Gini)",
        metric == "iop_rsq" ~ "IOp Share (R²)",
        metric == "gini_total" ~ "Total Inequality (Gini)"
      ),
      is_iop = metric != "gini_total"
    )

  # Plot IOp shares
  p1 <- plot_data %>%
    filter(is_iop) %>%
    ggplot(aes(x = cohort, y = value * 100, color = metric_label, group = metric_label)) +
    geom_line(linewidth = 1.2) +
    geom_point(size = 3) +
    geom_text(aes(label = paste0(round(value * 100, 1), "%")),
              vjust = -1, size = 3) +
    scale_color_manual(
      values = c("IOp Share (Gini)" = "#0072B2", "IOp Share (R²)" = "#D55E00"),
      name = "Metric"
    ) +
    scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.15))) +
    labs(
      title = "Inequality of Opportunity Across Birth Cohorts",
      subtitle = "Trends in IOp share over time",
      x = "Birth Cohort",
      y = "IOp Share (%)"
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.title = element_text(face = "bold")
    )

  # Plot total inequality alongside
  p2 <- plot_data %>%
    filter(!is_iop) %>%
    ggplot(aes(x = cohort, y = value, group = 1)) +
    geom_line(linewidth = 1.2, color = "#009E73") +
    geom_point(size = 3, color = "#009E73") +
    geom_text(aes(label = round(value, 3)), vjust = -1, size = 3) +
    scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.15))) +
    labs(
      title = "Total Income Inequality Across Cohorts",
      subtitle = "Gini coefficient by birth cohort",
      x = "Birth Cohort",
      y = "Gini Coefficient"
    ) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.title = element_text(face = "bold")
    )

  # Combine plots
  p_combined <- p1 / p2 +
    plot_annotation(
      title = "Temporal Trends in Inequality of Opportunity",
      subtitle = "ESRU-EMOVI 2023 - Analysis by Birth Cohort",
      theme = theme(
        plot.title = element_text(face = "bold", size = 14),
        plot.subtitle = element_text(color = "gray40")
      )
    )

  # Save
  ggsave(
    get_path(config$paths$figures, paste0(filename, ".png")),
    p_combined, width = 10, height = 10, dpi = 300
  )

  log_msg("Saved plot: ", filename, ".png")

  return(p_combined)
}

#' Plot decomposition by cohort (stacked bar)
#' @param cohort_results Results from calculate_iop_by_cohort
#' @param filename Output filename
#' @return ggplot object
plot_cohort_decomposition <- function(cohort_results,
                                       filename = "cohort_decomposition") {

  plot_data <- cohort_results %>%
    mutate(
      within_type = 1 - iop_gini,  # Residual inequality
      between_type = iop_gini       # IOp
    ) %>%
    select(cohort, within_type, between_type) %>%
    pivot_longer(
      cols = c(within_type, between_type),
      names_to = "component",
      values_to = "share"
    ) %>%
    mutate(
      component_label = case_when(
        component == "between_type" ~ "IOp (Between Types)",
        component == "within_type" ~ "Residual (Within Types)"
      ),
      component_label = factor(component_label,
                               levels = c("Residual (Within Types)", "IOp (Between Types)"))
    )

  p <- ggplot(plot_data, aes(x = cohort, y = share * 100, fill = component_label)) +
    geom_col(position = "stack", width = 0.7) +
    geom_text(
      aes(label = ifelse(share > 0.1, paste0(round(share * 100, 1), "%"), "")),
      position = position_stack(vjust = 0.5),
      size = 3, color = "white", fontface = "bold"
    ) +
    scale_fill_manual(
      values = c("IOp (Between Types)" = "#0072B2",
                 "Residual (Within Types)" = "#E69F00"),
      name = "Component"
    ) +
    scale_y_continuous(labels = function(x) paste0(x, "%")) +
    labs(
      title = "Decomposition of Income Inequality by Birth Cohort",
      subtitle = "IOp (circumstances) vs Residual (effort + luck)",
      x = "Birth Cohort",
      y = "Share of Total Inequality"
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      axis.text.x = element_text(angle = 45, hjust = 1),
      plot.title = element_text(face = "bold")
    )

  ggsave(
    get_path(config$paths$figures, paste0(filename, ".png")),
    p, width = 10, height = 6, dpi = 300
  )

  log_msg("Saved plot: ", filename, ".png")

  return(p)
}

# ============================================================================
# 6. Main Execution
# ============================================================================

#' Run complete cohort analysis
#' @param df Data frame (optional, will load if NULL)
#' @param outcome Outcome variable name
#' @return List with all cohort analysis results
run_cohort_analysis <- function(df = NULL, outcome = "ingc_pc") {

  # Load data if not provided
  if (is.null(df)) {
    df <- readRDS(get_path(config$paths$data_processed, "entrevistado_clean.rds"))
  }

  log_msg("\n")
  log_msg(paste(rep("=", 60), collapse = ""))
  log_msg("COHORT ANALYSIS OF INEQUALITY OF OPPORTUNITY")
  log_msg(paste(rep("=", 60), collapse = ""))

  # Prepare cohort data
  df <- prepare_cohort_data(df)

  # Calculate IOp by cohort
  cohort_results <- calculate_iop_by_cohort(df, outcome)

  if (nrow(cohort_results) == 0) {
    stop("No cohort results generated - check data and variables")
  }

  # Analyze trends
  trends <- analyze_cohort_trends(cohort_results)

  # Create visualizations
  p_trends <- plot_cohort_trends(cohort_results)
  p_decomp <- plot_cohort_decomposition(cohort_results)

  # Save results
  save_table(cohort_results, "cohort_iop_results")
  if (!is.null(trends)) {
    save_table(trends$summary, "cohort_trend_summary")
  }

  log_msg("\n")
  log_msg(paste(rep("=", 60), collapse = ""))
  log_msg("COHORT ANALYSIS COMPLETE")
  log_msg(paste(rep("=", 60), collapse = ""))

  # Print summary
  log_msg("\nKey Findings:")
  log_msg("  Cohorts analyzed: ", nrow(cohort_results))
  log_msg("  IOp range: ",
          round(min(cohort_results$iop_gini) * 100, 1), "% - ",
          round(max(cohort_results$iop_gini) * 100, 1), "%")

  if (!is.null(trends)) {
    log_msg("\nTrend: IOp is ", trends$trends$iop_gini$direction,
            " across cohorts (p=", round(trends$trends$iop_gini$pvalue, 3), ")")
  }

  return(list(
    cohort_results = cohort_results,
    trends = trends,
    plots = list(trends = p_trends, decomposition = p_decomp)
  ))
}

# ============================================================================
# Run analysis (uncomment to execute)
# ============================================================================

# cohort_analysis <- run_cohort_analysis()

log_msg("07_cohort_analysis.R loaded")
log_msg("Available functions:")
log_msg("  - run_cohort_analysis(df, outcome)")
log_msg("  - calculate_iop_by_cohort(df, outcome, circumstances)")
log_msg("  - analyze_cohort_trends(cohort_results)")
log_msg("  - plot_cohort_trends(cohort_results)")

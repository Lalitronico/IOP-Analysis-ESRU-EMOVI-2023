# ============================================================================
# 06_sensitivity_analysis.R - Robustness and Sensitivity Analyses
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Test robustness of IOp estimates across specifications
# ============================================================================

# Load setup and previous scripts
source(here::here("src", "R", "00_setup.R"))
source(here::here("src", "R", "05_iop_metrics.R"))

log_msg("Starting sensitivity analysis")

# ============================================================================
# 1. Circumstance Set Definitions (from variable_roles.yaml)
# ============================================================================

# Minimal: Core circumstances only (5 variables)
CIRCUMSTANCE_SETS <- list(
  minimal = c(
    "educp",           # Father's education
    "educm",           # Mother's education
    "sexo",            # Sex
    "indigenous",      # Speaks indigenous language
    "region_14"        # Region at age 14
  ),

  # Standard: Following Brunori et al. (9 variables)
  standard = c(
    "educp", "educm", "clasep",
    "sexo", "indigenous", "skin_tone",
    "region_14", "cohorte", "rural_14"
  ),

  # Extended: Full circumstance set (13+ variables)
  extended = c(
    "educp", "educm", "clasep",
    "sexo", "indigenous", "skin_tone",
    "region_14", "cohorte", "rural_14",
    "floor_material_14", "water_14", "bathroom_14", "n_cars_14"
  ),

  # No parental: Exclude parental education (robustness check)
  no_parental = c(
    "clasep",          # Father's class (proxy for SES)
    "sexo", "indigenous", "skin_tone",
    "region_14", "rural_14"
  ),

  # ---- NEW EXTENDED SETS WITH INDICES ----

  # Standard + household economic conditions
  extended_household = c(
    "educp", "educm", "clasep",
    "sexo", "indigenous", "skin_tone",
    "region_14", "cohorte", "rural_14",
    "household_economic_index",
    "crowding_index"
  ),

  # Standard + neighborhood quality
  extended_neighborhood = c(
    "educp", "educm", "clasep",
    "sexo", "indigenous", "skin_tone",
    "region_14", "cohorte", "rural_14",
    "neighborhood_index"
  ),

  # Standard + cultural capital
  extended_cultural = c(
    "educp", "educm", "clasep",
    "sexo", "indigenous", "skin_tone",
    "region_14", "cohorte", "rural_14",
    "cultural_capital_index"
  ),

  # Maximum: All available circumstances (upper bound)
  maximum = c(
    "educp", "educm", "clasep",
    "sexo", "indigenous", "skin_tone",
    "region_14", "cohorte", "rural_14",
    "household_economic_index",
    "neighborhood_index",
    "cultural_capital_index",
    "crowding_index",
    "financial_inclusion_index"
  )
)

# ============================================================================
# 2. Main Sensitivity Analysis: Circumstance Sets
# ============================================================================

#' Compare IOp estimates across different circumstance sets
#'
#' This is a key robustness check: IOp estimates should be relatively
#' stable across reasonable specifications. Large changes suggest
#' sensitivity to variable selection.
#'
#' @param df Data frame with outcome and circumstance variables
#' @param outcome Outcome variable name
#' @param sets Named list of circumstance variable vectors
#' @param weight Weight variable name (optional)
#' @param ctree_params List of ctree parameters
#' @return Tibble with comparative IOp results
run_circumstance_sensitivity <- function(df, outcome = "ln_ingc_pc",
                                          sets = CIRCUMSTANCE_SETS,
                                          weight = "factor",
                                          ctree_params = list(
                                            mincriterion = 0.95,
                                            minsplit = 100,
                                            minbucket = 50,
                                            maxdepth = 6
                                          )) {

  log_msg("=== Sensitivity Analysis: Circumstance Sets ===")
  log_msg("Comparing ", length(sets), " specifications")

  results <- list()

  for (set_name in names(sets)) {
    log_msg("\n--- Running: ", set_name, " (", length(sets[[set_name]]),
            " circumstances) ---")

    circumstances <- sets[[set_name]]

    # Prepare data
    vars_needed <- c(outcome, circumstances)
    if (!is.null(weight)) vars_needed <- c(vars_needed, weight)

    df_analysis <- df %>%
      select(any_of(vars_needed)) %>%
      drop_na()

    log_msg("  Sample size: ", nrow(df_analysis))

    # Check which circumstances are available
    available <- circumstances[circumstances %in% names(df_analysis)]
    missing <- circumstances[!circumstances %in% names(df_analysis)]

    if (length(missing) > 0) {
      log_msg("  Warning: Missing variables: ", paste(missing, collapse = ", "))
    }

    if (length(available) < 2) {
      log_msg("  Skipping: Too few variables available")
      next
    }

    # Create formula and fit ctree
    formula <- as.formula(paste(outcome, "~", paste(available, collapse = " + ")))

    ctrl <- partykit::ctree_control(
      mincriterion = ctree_params$mincriterion,
      minsplit = ctree_params$minsplit,
      minbucket = ctree_params$minbucket,
      maxdepth = ctree_params$maxdepth
    )

    model <- tryCatch(
      partykit::ctree(formula, data = df_analysis, control = ctrl),
      error = function(e) {
        log_msg("  Error fitting model: ", e$message)
        return(NULL)
      }
    )

    if (is.null(model)) next

    # Get predictions
    type_means <- predict(model, type = "response")
    types <- predict(model, type = "node")
    y <- df_analysis[[outcome]]
    w <- if (!is.null(weight) && weight %in% names(df_analysis)) {
      df_analysis[[weight]]
    } else NULL

    # Calculate IOp metrics
    iop_gini <- calculate_iop_share(y, type_means, w, "gini")
    iop_mld <- calculate_iop_share(y, type_means, w, "mld")
    iop_rsq <- calculate_iop_rsq(y, type_means, w)

    # Store results
    results[[set_name]] <- tibble(
      circumstance_set = set_name,
      n_circumstances = length(available),
      n_types = length(unique(types)),
      n_obs = nrow(df_analysis),
      iop_gini = iop_gini$iop_share,
      iop_mld = iop_mld$iop_share,
      iop_rsq = iop_rsq,
      gini_total = iop_gini$ineq_total,
      mld_total = iop_mld$ineq_total
    )

    log_msg("  IOp (Gini): ", round(iop_gini$iop_share * 100, 1), "%")
    log_msg("  IOp (R-sq): ", round(iop_rsq * 100, 1), "%")
    log_msg("  Types: ", length(unique(types)))
  }

  # Combine results
  comparison <- bind_rows(results)

  # Save results
  save_table(comparison, "sensitivity_circumstance_sets")

  log_msg("\n=== Sensitivity Analysis Complete ===")
  log_msg("Results saved to: sensitivity_circumstance_sets.csv")

  return(comparison)
}

# ============================================================================
# 3. Subsample Analysis
# ============================================================================

#' Compare IOp across population subsamples
#'
#' @param df Data frame
#' @param outcome Outcome variable name
#' @param circumstances Circumstance variable vector
#' @param subsamples Named list defining subsample filters
#' @return Tibble with subsample comparison
run_subsample_sensitivity <- function(df, outcome = "ln_ingc_pc",
                                       circumstances = CIRCUMSTANCE_SETS$standard,
                                       subsamples = NULL) {

  if (is.null(subsamples)) {
    # Default subsamples based on config
    subsamples <- list(
      national = function(df) df,
      urban = function(df) df %>% filter(rural_14 == 1),  # Ciudad
      rural = function(df) df %>% filter(rural_14 %in% c(2, 3)),  # Pueblo/Rancheria
      male = function(df) df %>% filter(sexo == 1),
      female = function(df) df %>% filter(sexo == 2)
    )
  }

  log_msg("=== Subsample Sensitivity Analysis ===")

  results <- list()

  for (sample_name in names(subsamples)) {
    log_msg("\n--- Subsample: ", sample_name, " ---")

    df_sub <- subsamples[[sample_name]](df)
    log_msg("  N = ", nrow(df_sub))

    if (nrow(df_sub) < 500) {
      log_msg("  Skipping: Sample too small")
      next
    }

    # Prepare data
    df_analysis <- df_sub %>%
      select(any_of(c(outcome, circumstances))) %>%
      drop_na()

    # Fit model
    available <- circumstances[circumstances %in% names(df_analysis)]
    formula <- as.formula(paste(outcome, "~", paste(available, collapse = " + ")))

    ctrl <- partykit::ctree_control(mincriterion = 0.95, minsplit = 100, maxdepth = 6)

    model <- tryCatch(
      partykit::ctree(formula, data = df_analysis, control = ctrl),
      error = function(e) NULL
    )

    if (is.null(model)) {
      log_msg("  Error fitting model")
      next
    }

    # Calculate IOp
    type_means <- predict(model, type = "response")
    y <- df_analysis[[outcome]]

    iop_gini <- calculate_iop_share(y, type_means, metric = "gini")
    iop_rsq <- calculate_iop_rsq(y, type_means)

    results[[sample_name]] <- tibble(
      subsample = sample_name,
      n_obs = nrow(df_analysis),
      iop_gini = iop_gini$iop_share,
      iop_rsq = iop_rsq
    )

    log_msg("  IOp (Gini): ", round(iop_gini$iop_share * 100, 1), "%")
  }

  comparison <- bind_rows(results)
  save_table(comparison, "sensitivity_subsamples")

  return(comparison)
}

# ============================================================================
# 4. Hyperparameter Sensitivity
# ============================================================================

#' Test sensitivity to ctree hyperparameters
#'
#' @param df Data frame
#' @param outcome Outcome variable
#' @param circumstances Circumstance variables
#' @param param_grid Parameter grid to test
#' @return Tibble with hyperparameter sensitivity results
run_hyperparameter_sensitivity <- function(df, outcome = "ln_ingc_pc",
                                            circumstances = CIRCUMSTANCE_SETS$standard,
                                            param_grid = NULL) {

  if (is.null(param_grid)) {
    param_grid <- expand.grid(
      mincriterion = c(0.90, 0.95, 0.99),
      maxdepth = c(4, 6, 8),
      stringsAsFactors = FALSE
    )
  }

  log_msg("=== Hyperparameter Sensitivity ===")
  log_msg("Testing ", nrow(param_grid), " parameter combinations")

  # Prepare data
  df_analysis <- df %>%
    select(any_of(c(outcome, circumstances))) %>%
    drop_na()

  available <- circumstances[circumstances %in% names(df_analysis)]
  formula <- as.formula(paste(outcome, "~", paste(available, collapse = " + ")))

  results <- list()

  for (i in 1:nrow(param_grid)) {
    params <- param_grid[i, ]

    ctrl <- partykit::ctree_control(
      mincriterion = params$mincriterion,
      minsplit = 100,
      minbucket = 50,
      maxdepth = params$maxdepth
    )

    model <- tryCatch(
      partykit::ctree(formula, data = df_analysis, control = ctrl),
      error = function(e) NULL
    )

    if (is.null(model)) next

    type_means <- predict(model, type = "response")
    types <- predict(model, type = "node")
    y <- df_analysis[[outcome]]

    iop_gini <- calculate_iop_share(y, type_means, metric = "gini")
    iop_rsq <- calculate_iop_rsq(y, type_means)

    results[[i]] <- tibble(
      mincriterion = params$mincriterion,
      maxdepth = params$maxdepth,
      n_types = length(unique(types)),
      iop_gini = iop_gini$iop_share,
      iop_rsq = iop_rsq
    )
  }

  comparison <- bind_rows(results)
  save_table(comparison, "sensitivity_hyperparameters")

  log_msg("IOp range (Gini): ",
          round(min(comparison$iop_gini) * 100, 1), "% - ",
          round(max(comparison$iop_gini) * 100, 1), "%")

  return(comparison)
}

# ============================================================================
# 5. Visualization
# ============================================================================

#' Plot sensitivity analysis results
#'
#' @param results Tibble from run_circumstance_sensitivity
#' @param filename Output filename
#' @return ggplot object
plot_sensitivity_results <- function(results, filename = "sensitivity_plot") {

  # Reshape for plotting
  plot_data <- results %>%
    select(circumstance_set, iop_gini, iop_mld, iop_rsq) %>%
    pivot_longer(
      cols = starts_with("iop"),
      names_to = "metric",
      values_to = "value"
    ) %>%
    mutate(
      metric = case_when(
        metric == "iop_gini" ~ "Gini-based",
        metric == "iop_mld" ~ "MLD-based",
        metric == "iop_rsq" ~ "R-squared"
      ),
      circumstance_set = factor(circumstance_set,
                                 levels = c("minimal", "standard", "extended",
                                            "extended_household", "extended_neighborhood",
                                            "extended_cultural", "maximum", "no_parental"))
    )

  p <- ggplot(plot_data, aes(x = circumstance_set, y = value * 100,
                              fill = metric, group = metric)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7) +
    geom_text(aes(label = paste0(round(value * 100, 1), "%")),
              position = position_dodge(width = 0.8),
              vjust = -0.5, size = 3) +
    scale_fill_manual(
      values = c("Gini-based" = "#0072B2",
                 "MLD-based" = "#009E73",
                 "R-squared" = "#D55E00"),
      name = "Metric"
    ) +
    scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    labs(
      title = "IOp Sensitivity to Circumstance Set Specification",
      subtitle = "Results should be stable across reasonable specifications",
      x = "Circumstance Set",
      y = "IOp Share (%)"
    ) +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      axis.text.x = element_text(angle = 45, hjust = 1)
    )

  ggsave(
    get_path(config$paths$figures, paste0(filename, ".png")),
    p, width = 10, height = 7, dpi = 300
  )

  log_msg("Saved plot: ", filename, ".png")

  return(p)
}

# ============================================================================
# 6. Main Execution
# ============================================================================

#' Run complete sensitivity analysis
#'
#' @param df Data frame
#' @param outcome Outcome variable
#' @return List with all sensitivity results
run_full_sensitivity <- function(df = NULL, outcome = "ln_ingc_pc") {

  # Load data if not provided
  if (is.null(df)) {
    df <- readRDS(get_path(config$paths$data_processed, "entrevistado_clean.rds"))
  }

  log_msg("\n")
  log_msg(paste(rep("=", 60), collapse = ""))
  log_msg("FULL SENSITIVITY ANALYSIS")
  log_msg(paste(rep("=", 60), collapse = ""))

  # 1. Circumstance set sensitivity
  circ_results <- run_circumstance_sensitivity(df, outcome)

  # 2. Subsample sensitivity
  sub_results <- run_subsample_sensitivity(df, outcome)

  # 3. Hyperparameter sensitivity
  hyper_results <- run_hyperparameter_sensitivity(df, outcome)

  # 4. Visualization
  if (nrow(circ_results) > 0) {
    plot_sensitivity_results(circ_results)
  }

  log_msg("\n")
  log_msg(paste(rep("=", 60), collapse = ""))
  log_msg("SENSITIVITY ANALYSIS COMPLETE")
  log_msg(paste(rep("=", 60), collapse = ""))

  # Summary
  log_msg("\nKey findings:")
  if (nrow(circ_results) > 0) {
    log_msg("  IOp (Gini) range: ",
            round(min(circ_results$iop_gini, na.rm = TRUE) * 100, 1), "% - ",
            round(max(circ_results$iop_gini, na.rm = TRUE) * 100, 1), "%")
  }

  return(list(
    circumstance_sets = circ_results,
    subsamples = sub_results,
    hyperparameters = hyper_results
  ))
}

# Run (uncomment to execute)
# sensitivity_results <- run_full_sensitivity()

log_msg("06_sensitivity_analysis.R loaded")
log_msg("Available functions:")
log_msg("  - run_full_sensitivity(df, outcome)")
log_msg("  - run_circumstance_sensitivity(df, outcome, sets)")
log_msg("  - run_subsample_sensitivity(df, outcome)")
log_msg("  - run_hyperparameter_sensitivity(df, outcome)")

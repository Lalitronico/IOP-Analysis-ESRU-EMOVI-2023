# ============================================================================
# 04_cforest_model.R - Conditional Inference Forest for Variable Importance
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Fit cforest model, compute permutation variable importance
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

log_msg("Starting cforest modeling")

# ============================================================================
# 1. Load Data and Variable Definitions
# ============================================================================

df <- readRDS(get_path(config$paths$data_processed, "entrevistado_clean.rds"))

# Same variable definitions as ctree (from 03_ctree_model.R)
OUTCOME_VAR <- "income_decile"  # Placeholder
CIRCUMSTANCE_VARS <- c(
  "father_education", "mother_education", "father_occupation",
  "n_books_14", "sex", "ethnicity", "skin_tone", "birth_region", "birth_cohort"
)
WEIGHT_VAR <- "factor"

# ============================================================================
# 2. cforest Configuration
# ============================================================================

#' Create cforest control object (using party package for unbiased settings)
#' @param ntree number of trees
#' @param mtry number of variables to consider at each split
#' @param replace sampling with replacement
#' @return cforest_control object
create_cforest_control <- function(ntree = 500, mtry = NULL, replace = FALSE) {

  # Use unbiased settings per Strobl et al. (2007)
  party::cforest_unbiased(
    ntree = ntree,
    mtry = mtry  # NULL = sqrt(n_vars)
  )
}

# ============================================================================
# 3. Fit cforest Model
# ============================================================================

#' Fit cforest model
#' @param data data frame
#' @param formula model formula
#' @param control cforest_control object
#' @param seed random seed
#' @return cforest model
fit_cforest <- function(data, formula, control, seed = SEEDS$global) {

  set.seed(seed)
  log_msg("Fitting cforest with ntree=", control@ntree, ", mtry=", control@mtry)
  tic("cforest fitting")

  model <- party::cforest(
    formula = formula,
    data = data,
    controls = control
  )

  toc()
  log_msg("cforest fitted successfully")

  return(model)
}

# ============================================================================
# 4. Variable Importance
# ============================================================================

#' Compute permutation variable importance
#' @param model cforest model
#' @param conditional use conditional importance (accounts for correlations)
#' @param nperm number of permutations
#' @return named vector of variable importance
compute_varimp <- function(model, conditional = TRUE, nperm = 1) {

  log_msg("Computing ", ifelse(conditional, "conditional", "unconditional"),
          " variable importance")
  tic("varimp computation")

  if (conditional) {
    # Conditional importance - accounts for correlations between variables
    # More computationally expensive but recommended for correlated predictors
    vi <- party::varimp(model, conditional = TRUE)
  } else {
    # Standard permutation importance
    vi <- party::varimp(model, conditional = FALSE, nperm = nperm)
  }

  toc()
  return(vi)
}

#' Bootstrap variable importance for confidence intervals
#' @param data data frame
#' @param formula model formula
#' @param control cforest control
#' @param n_boot number of bootstrap samples
#' @param seeds vector of bootstrap seeds
#' @param conditional use conditional importance
#' @return list with mean, sd, and all bootstrap results
bootstrap_varimp <- function(data, formula, control, n_boot = 100,
                             seeds = SEEDS$bootstrap, conditional = TRUE) {

  log_msg("Bootstrap variable importance with ", n_boot, " replications")

  # Storage for results
  vi_results <- list()

  for (b in 1:n_boot) {
    if (b %% 10 == 0) log_msg("Bootstrap iteration ", b, "/", n_boot)

    set.seed(seeds[b])

    # Bootstrap sample
    boot_idx <- sample(1:nrow(data), replace = TRUE)
    boot_data <- data[boot_idx, ]

    # Fit model
    model <- party::cforest(
      formula = formula,
      data = boot_data,
      controls = control
    )

    # Compute importance
    vi_results[[b]] <- party::varimp(model, conditional = conditional)
  }

  # Combine results
  vi_matrix <- do.call(rbind, vi_results)

  # Compute summary statistics
  summary <- tibble(
    variable = colnames(vi_matrix),
    mean_importance = colMeans(vi_matrix),
    sd_importance = apply(vi_matrix, 2, sd),
    ci_lower = apply(vi_matrix, 2, quantile, probs = 0.025),
    ci_upper = apply(vi_matrix, 2, quantile, probs = 0.975)
  ) %>%
    arrange(desc(mean_importance))

  return(list(
    summary = summary,
    all_results = vi_matrix
  ))
}

# ============================================================================
# 5. Variable Importance Visualization
# ============================================================================

#' Plot variable importance with confidence intervals
#' @param vi_summary tibble from bootstrap_varimp
#' @param filename output filename
#' @return ggplot object
plot_varimp <- function(vi_summary, filename = "varimp_cforest") {

  p <- vi_summary %>%
    mutate(variable = fct_reorder(variable, mean_importance)) %>%
    ggplot(aes(x = mean_importance, y = variable)) +
    geom_point(size = 3, color = "#0072B2") +
    geom_errorbarh(
      aes(xmin = ci_lower, xmax = ci_upper),
      height = 0.2,
      color = "#0072B2"
    ) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
    labs(
      title = "Conditional Variable Importance (cforest)",
      subtitle = "With 95% bootstrap confidence intervals",
      x = "Importance (reduction in MSE)",
      y = NULL
    ) +
    theme_iop()

  save_figure(p, filename, width = 8, height = 6)

  return(p)
}

#' Compare conditional vs unconditional importance
#' @param model cforest model
#' @param filename output filename
#' @return ggplot object
plot_varimp_comparison <- function(model, filename = "varimp_comparison") {

  # Compute both types
  vi_unconditional <- compute_varimp(model, conditional = FALSE)
  vi_conditional <- compute_varimp(model, conditional = TRUE)

  # Combine into data frame
  comparison <- tibble(
    variable = names(vi_unconditional),
    unconditional = vi_unconditional,
    conditional = vi_conditional
  ) %>%
    pivot_longer(
      cols = c(unconditional, conditional),
      names_to = "type",
      values_to = "importance"
    ) %>%
    mutate(
      variable = fct_reorder(variable, importance, .fun = mean),
      type = factor(type, levels = c("unconditional", "conditional"))
    )

  p <- ggplot(comparison, aes(x = importance, y = variable, color = type)) +
    geom_point(size = 3, position = position_dodge(width = 0.5)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
    scale_color_manual(
      values = c("unconditional" = "#E69F00", "conditional" = "#0072B2"),
      labels = c("Unconditional", "Conditional (recommended)")
    ) +
    labs(
      title = "Variable Importance: Unconditional vs Conditional",
      subtitle = "Conditional importance accounts for correlations between circumstances",
      x = "Importance (reduction in MSE)",
      y = NULL,
      color = "Type"
    ) +
    theme_iop()

  save_figure(p, filename, width = 9, height = 6)

  return(p)
}

# ============================================================================
# 6. Prediction and Type Assignment Stability
# ============================================================================

#' Assess stability of type assignments across bootstrap samples
#' @param data data frame
#' @param ctree_model ctree model for type assignment
#' @param n_boot number of bootstrap samples
#' @param seeds bootstrap seeds
#' @return stability metrics
assess_type_stability <- function(data, ctree_model, n_boot = 100,
                                   seeds = SEEDS$bootstrap) {

  log_msg("Assessing type assignment stability")

  # Get original type assignments
  original_types <- predict(ctree_model, type = "node")
  n_obs <- length(original_types)

  # Track agreement with original
  agreement <- numeric(n_boot)

  for (b in 1:n_boot) {
    set.seed(seeds[b])

    # Bootstrap sample
    boot_idx <- sample(1:n_obs, replace = TRUE)
    boot_data <- data[boot_idx, ]

    # Re-fit ctree on bootstrap sample
    boot_model <- partykit::ctree(
      formula = ctree_model$info$formula,
      data = boot_data,
      control = ctree_model$info$control
    )

    # Predict types for ORIGINAL data
    boot_types <- predict(boot_model, newdata = data, type = "node")

    # Calculate agreement (normalized mutual information or simple match)
    agreement[b] <- mean(original_types == boot_types)
  }

  stability <- list(
    mean_agreement = mean(agreement),
    sd_agreement = sd(agreement),
    ci_lower = quantile(agreement, 0.025),
    ci_upper = quantile(agreement, 0.975)
  )

  log_msg("Type stability: ", round(stability$mean_agreement * 100, 1),
          "% agreement (95% CI: ",
          round(stability$ci_lower * 100, 1), "-",
          round(stability$ci_upper * 100, 1), "%)")

  return(stability)
}

# ============================================================================
# 7. Main Execution
# ============================================================================

run_cforest_analysis <- function() {

  # NOTE: Placeholder - uncomment when variables are defined

  # # Create formula
  # formula_str <- paste(OUTCOME_VAR, "~", paste(CIRCUMSTANCE_VARS, collapse = " + "))
  # formula <- as.formula(formula_str)
  #
  # # Prepare data
  # df_analysis <- df %>%
  #   select(all_of(c(OUTCOME_VAR, CIRCUMSTANCE_VARS))) %>%
  #   drop_na()
  #
  # log_msg("Analysis data: ", nrow(df_analysis), " complete cases")
  #
  # # Set up control
  # ctrl <- create_cforest_control(
  #   ntree = config$cforest$ntree,
  #   mtry = floor(sqrt(length(CIRCUMSTANCE_VARS)))
  # )
  #
  # # Fit model
  # model <- fit_cforest(df_analysis, formula, ctrl)
  #
  # # Compute variable importance
  # vi <- compute_varimp(model, conditional = TRUE)
  # log_msg("Top 3 circumstances: ", paste(names(sort(vi, decreasing = TRUE))[1:3], collapse = ", "))
  #
  # # Bootstrap for confidence intervals
  # vi_boot <- bootstrap_varimp(
  #   df_analysis, formula, ctrl,
  #   n_boot = min(50, config$seeds$n_bootstrap),  # Reduced for speed
  #   conditional = TRUE
  # )
  # save_table(vi_boot$summary, "varimp_bootstrap_ci")
  #
  # # Visualizations
  # plot_varimp(vi_boot$summary)
  # plot_varimp_comparison(model)
  #
  # # Save model and results
  # saveRDS(model, get_path(config$paths$models, "cforest_final.rds"))
  # saveRDS(vi_boot, get_path(config$paths$models, "varimp_bootstrap.rds"))
  #
  # log_msg("cforest analysis complete")
  # return(list(model = model, varimp = vi, varimp_boot = vi_boot))

  log_msg("cforest analysis placeholder - update variable names and uncomment code")
}

# Run analysis
# results <- run_cforest_analysis()

log_msg("04_cforest_model.R loaded - call run_cforest_analysis() when data is ready")

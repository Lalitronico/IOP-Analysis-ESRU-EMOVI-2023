# ============================================================================
# 03_ctree_model.R - Conditional Inference Tree for Type Partition
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Fit ctree model to partition sample into "types" based on circumstances
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

log_msg("Starting ctree modeling")

# ============================================================================
# 1. Load Preprocessed Data
# ============================================================================

df <- readRDS(get_path(config$paths$data_processed, "entrevistado_clean.rds"))
log_msg("Loaded data: ", nrow(df), " observations")

# ============================================================================
# 2. Define Analysis Variables
# ============================================================================
# NOTE: Update these with actual variable names from EMOVI 2023

# Outcome variable
OUTCOME_VAR <- "income_decile"  # Placeholder - update with actual var

# Circumstance variables (from variable_roles.yaml)
CIRCUMSTANCE_VARS <- c(
  # Parental
  "father_education",
  "mother_education",
  "father_occupation",
  # Household origin
  "n_books_14",
  # Demographics
  "sex",
  "ethnicity",
  "skin_tone",
  "birth_region",
  "birth_cohort"
)

# Survey weight
WEIGHT_VAR <- "factor"  # Placeholder - update with actual var

# ============================================================================
# 3. Prepare Analysis Dataset
# ============================================================================

#' Prepare data for ctree analysis
#' @param df data frame
#' @param outcome outcome variable name
#' @param circumstances vector of circumstance variable names
#' @param weight weight variable name (optional)
#' @return list with train/test data and formula
prepare_ctree_data <- function(df, outcome, circumstances, weight = NULL) {

  # Check variables exist
  all_vars <- c(outcome, circumstances, weight)
  missing_vars <- all_vars[!all_vars %in% names(df)]

  if (length(missing_vars) > 0) {
    stop("Missing variables: ", paste(missing_vars, collapse = ", "))
  }

  # Select analysis variables
  df_analysis <- df %>%
    select(all_of(all_vars)) %>%
    drop_na(all_of(outcome))  # Remove missing outcomes

  log_msg("Analysis dataset: ", nrow(df_analysis), " observations after removing NA outcomes")

  # Create formula
  formula_str <- paste(outcome, "~", paste(circumstances, collapse = " + "))
  formula <- as.formula(formula_str)

  return(list(
    data = df_analysis,
    formula = formula,
    outcome = outcome,
    circumstances = circumstances,
    weight = weight
  ))
}

# ============================================================================
# 4. ctree Control Parameters
# ============================================================================

#' Create ctree control object
#' @param mincriterion significance level for splits
#' @param minsplit minimum observations for split
#' @param minbucket minimum observations per terminal node
#' @param maxdepth maximum tree depth
#' @return ctree_control object
create_ctree_control <- function(mincriterion = 0.95,
                                  minsplit = 100,
                                  minbucket = 50,
                                  maxdepth = 6) {

  partykit::ctree_control(
    mincriterion = mincriterion,
    minsplit = minsplit,
    minbucket = minbucket,
    maxdepth = maxdepth,
    teststat = "quadratic",
    testtype = "Bonferroni",
    splitstat = "quadratic"
  )
}

# ============================================================================
# 5. Fit Single ctree
# ============================================================================

#' Fit ctree model
#' @param data prepared data list from prepare_ctree_data
#' @param control ctree_control object
#' @return ctree model
fit_ctree <- function(data, control) {

  log_msg("Fitting ctree with maxdepth=", control$maxdepth)
  tic("ctree fitting")

  # Fit model
  model <- partykit::ctree(
    formula = data$formula,
    data = data$data,
    control = control
  )

  toc()

  # Summary statistics
  n_nodes <- length(model)
  n_terminal <- sum(sapply(1:n_nodes, function(i) is.null(model[[i]]$kids)))

  log_msg("Tree fitted: ", n_nodes, " total nodes, ", n_terminal, " terminal nodes (types)")

  return(model)
}

# ============================================================================
# 6. Extract Type Information
# ============================================================================

#' Extract type assignments and means from ctree
#' @param model ctree model
#' @param data data frame used for fitting
#' @param outcome outcome variable name
#' @return tibble with type information
extract_types <- function(model, data, outcome) {

  # Get terminal node (type) assignments
  type_assignments <- predict(model, type = "node")

  # Get predicted values (type means)
  type_means <- predict(model, type = "response")

  # Create summary by type
  type_summary <- tibble(
    observation = 1:length(type_assignments),
    type = type_assignments,
    observed = data[[outcome]],
    type_mean = type_means
  ) %>%
    group_by(type) %>%
    summarise(
      n = n(),
      mean_outcome = mean(observed, na.rm = TRUE),
      sd_outcome = sd(observed, na.rm = TRUE),
      predicted_mean = first(type_mean),
      .groups = "drop"
    ) %>%
    arrange(desc(n))

  return(type_summary)
}

# ============================================================================
# 7. Plot ctree
# ============================================================================

#' Plot ctree with customized appearance
#' @param model ctree model
#' @param filename output filename (without extension)
#' @param width figure width in inches
#' @param height figure height in inches
plot_ctree <- function(model, filename = "ctree_plot", width = 16, height = 10) {

  filepath <- get_path(config$paths$figures, paste0(filename, ".png"))

  png(filepath, width = width, height = height, units = "in", res = 300)

  plot(model,
       type = "simple",
       inner_panel = node_inner,
       terminal_panel = node_boxplot,
       tp_args = list(id = FALSE, fill = "lightblue"),
       ep_args = list(justmin = 5),
       gp = gpar(fontsize = 8))

  dev.off()

  log_msg("Saved ctree plot: ", filepath)
}

# ============================================================================
# 8. Cross-Validation for Hyperparameter Tuning
# ============================================================================

#' Cross-validate ctree parameters
#' @param data prepared data list
#' @param param_grid data frame with parameter combinations
#' @param n_folds number of CV folds
#' @param seed random seed
#' @return tibble with CV results
cv_ctree <- function(data, param_grid, n_folds = 5, seed = SEEDS$cv) {

  set.seed(seed)

  # Create fold indices
  folds <- cut(sample(1:nrow(data$data)), breaks = n_folds, labels = FALSE)

  results <- list()

  for (i in 1:nrow(param_grid)) {
    params <- param_grid[i, ]
    log_msg("CV for params: mincriterion=", params$mincriterion,
            ", maxdepth=", params$maxdepth)

    fold_results <- numeric(n_folds)

    for (fold in 1:n_folds) {
      # Split data
      train_idx <- which(folds != fold)
      test_idx <- which(folds == fold)

      train_data <- data$data[train_idx, ]
      test_data <- data$data[test_idx, ]

      # Create control
      ctrl <- create_ctree_control(
        mincriterion = params$mincriterion,
        minsplit = params$minsplit,
        minbucket = params$minbucket,
        maxdepth = params$maxdepth
      )

      # Fit model
      model <- partykit::ctree(
        formula = data$formula,
        data = train_data,
        control = ctrl
      )

      # Predict on test set
      predictions <- predict(model, newdata = test_data, type = "response")

      # Calculate R-squared
      ss_res <- sum((test_data[[data$outcome]] - predictions)^2, na.rm = TRUE)
      ss_tot <- sum((test_data[[data$outcome]] - mean(test_data[[data$outcome]], na.rm = TRUE))^2, na.rm = TRUE)
      fold_results[fold] <- 1 - ss_res / ss_tot
    }

    results[[i]] <- tibble(
      mincriterion = params$mincriterion,
      minsplit = params$minsplit,
      minbucket = params$minbucket,
      maxdepth = params$maxdepth,
      mean_r2 = mean(fold_results),
      sd_r2 = sd(fold_results)
    )
  }

  bind_rows(results) %>%
    arrange(desc(mean_r2))
}

# ============================================================================
# 9. Main Execution
# ============================================================================

run_ctree_analysis <- function() {

  # NOTE: This function will fail until actual variable names are specified
  # Uncomment and run when data is ready

  # # Prepare data
  # prep <- prepare_ctree_data(
  #   df = df,
  #   outcome = OUTCOME_VAR,
  #   circumstances = CIRCUMSTANCE_VARS,
  #   weight = WEIGHT_VAR
  # )
  #
  # # Define parameter grid for CV
  # param_grid <- expand.grid(
  #   mincriterion = config$ctree$mincriterion$grid,
  #   minsplit = config$ctree$minsplit$default,
  #   minbucket = config$ctree$minbucket$default,
  #   maxdepth = config$ctree$maxdepth$grid
  # )
  #
  # # Run cross-validation
  # cv_results <- cv_ctree(prep, param_grid)
  # save_table(cv_results, "ctree_cv_results")
  #
  # # Get best parameters
  # best_params <- cv_results[1, ]
  # log_msg("Best parameters: mincriterion=", best_params$mincriterion,
  #         ", maxdepth=", best_params$maxdepth,
  #         " (CV R² = ", round(best_params$mean_r2, 4), ")")
  #
  # # Fit final model with best parameters
  # best_ctrl <- create_ctree_control(
  #   mincriterion = best_params$mincriterion,
  #   minsplit = best_params$minsplit,
  #   minbucket = best_params$minbucket,
  #   maxdepth = best_params$maxdepth
  # )
  #
  # final_model <- fit_ctree(prep, best_ctrl)
  #
  # # Extract type information
  # type_info <- extract_types(final_model, prep$data, OUTCOME_VAR)
  # save_table(type_info, "ctree_type_summary")
  #
  # # Plot tree
  # plot_ctree(final_model, "ctree_final")
  #
  # # Save model
  # saveRDS(final_model, get_path(config$paths$models, "ctree_final.rds"))
  #
  # log_msg("ctree analysis complete")
  # return(list(model = final_model, types = type_info, cv = cv_results))

  log_msg("ctree analysis placeholder - update variable names and uncomment code")
}

# Run analysis
# results <- run_ctree_analysis()

log_msg("03_ctree_model.R loaded - call run_ctree_analysis() when data is ready")

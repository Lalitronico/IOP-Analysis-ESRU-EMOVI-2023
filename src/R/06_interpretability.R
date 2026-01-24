# ============================================================================
# 06_interpretability.R - PDP, ICE Plots for ctree/cforest
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Generate interpretability plots for tree-based models
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

log_msg("Loading interpretability functions")

# ============================================================================
# 1. Partial Dependence Plots (PDP)
# ============================================================================

#' Calculate partial dependence for a single variable
#' @param model fitted model
#' @param data data frame
#' @param var_name variable name
#' @param grid_resolution number of grid points
#' @return tibble with partial dependence values
calculate_pd <- function(model, data, var_name, grid_resolution = 50) {

  # Get variable values
  x <- data[[var_name]]

  # Create grid
  if (is.numeric(x)) {
    grid <- seq(min(x, na.rm = TRUE), max(x, na.rm = TRUE),
                length.out = grid_resolution)
  } else {
    grid <- unique(x)
  }

  # Calculate partial dependence
  pd_values <- sapply(grid, function(val) {
    # Replace variable with grid value
    data_mod <- data
    data_mod[[var_name]] <- val

    # Get predictions and average
    preds <- predict(model, newdata = data_mod, type = "response")
    mean(preds, na.rm = TRUE)
  })

  tibble(
    variable = var_name,
    value = if (is.numeric(x)) grid else as.character(grid),
    value_numeric = if (is.numeric(x)) grid else 1:length(grid),
    pd = pd_values
  )
}

#' Generate PDP for multiple variables
#' @param model fitted model
#' @param data data frame
#' @param var_names vector of variable names
#' @param grid_resolution number of grid points
#' @return combined tibble with all PDPs
calculate_pd_all <- function(model, data, var_names, grid_resolution = 50) {

  log_msg("Calculating partial dependence for ", length(var_names), " variables")

  results <- map_dfr(var_names, function(v) {
    log_msg("  Processing: ", v)
    calculate_pd(model, data, v, grid_resolution)
  })

  return(results)
}

#' Plot PDP grid for all circumstances
#' @param pd_data tibble from calculate_pd_all
#' @param filename output filename
#' @return ggplot object
plot_pdp_grid <- function(pd_data, filename = "pdp_grid") {

  p <- pd_data %>%
    ggplot(aes(x = value_numeric, y = pd)) +
    geom_line(color = "#0072B2", linewidth = 1) +
    geom_point(color = "#0072B2", size = 1.5) +
    facet_wrap(~variable, scales = "free_x", ncol = 3) +
    labs(
      title = "Partial Dependence Plots",
      subtitle = "Marginal effect of each circumstance on predicted outcome",
      x = "Variable Value",
      y = "Predicted Outcome"
    ) +
    theme_iop() +
    theme(
      strip.text = element_text(face = "bold"),
      strip.background = element_rect(fill = "gray95")
    )

  save_figure(p, filename, width = 12, height = 10)

  return(p)
}

# ============================================================================
# 2. Individual Conditional Expectation (ICE) Plots
# ============================================================================

#' Calculate ICE curves for a variable
#' @param model fitted model
#' @param data data frame
#' @param var_name variable name
#' @param n_sample number of observations to sample (for speed)
#' @param grid_resolution number of grid points
#' @return tibble with ICE curves
calculate_ice <- function(model, data, var_name, n_sample = 100,
                          grid_resolution = 50) {

  # Sample observations
  if (nrow(data) > n_sample) {
    set.seed(SEEDS$global)
    sample_idx <- sample(1:nrow(data), n_sample)
    data_sample <- data[sample_idx, ]
  } else {
    data_sample <- data
    sample_idx <- 1:nrow(data)
  }

  # Get variable values
  x <- data[[var_name]]

  # Create grid
  if (is.numeric(x)) {
    grid <- seq(min(x, na.rm = TRUE), max(x, na.rm = TRUE),
                length.out = grid_resolution)
  } else {
    grid <- unique(x)
  }

  # Calculate ICE for each sampled observation
  ice_results <- map_dfr(1:nrow(data_sample), function(i) {
    map_dfr(1:length(grid), function(j) {
      # Modify observation
      obs <- data_sample[i, ]
      obs[[var_name]] <- grid[j]

      # Predict
      pred <- predict(model, newdata = obs, type = "response")

      tibble(
        observation = i,
        original_id = sample_idx[i],
        variable = var_name,
        value = if (is.numeric(x)) grid[j] else as.character(grid[j]),
        value_numeric = if (is.numeric(x)) grid[j] else j,
        prediction = pred
      )
    })
  })

  return(ice_results)
}

#' Plot ICE curves with PDP overlay
#' @param ice_data tibble from calculate_ice
#' @param var_name variable name for title
#' @param filename output filename
#' @return ggplot object
plot_ice <- function(ice_data, var_name, filename = NULL) {

  # Calculate PDP (average of ICE curves)
  pd_data <- ice_data %>%
    group_by(variable, value, value_numeric) %>%
    summarise(pd = mean(prediction), .groups = "drop")

  p <- ggplot() +
    # ICE curves (thin, transparent)
    geom_line(
      data = ice_data,
      aes(x = value_numeric, y = prediction, group = observation),
      alpha = 0.1, color = "gray50"
    ) +
    # PDP overlay (thick, colored)
    geom_line(
      data = pd_data,
      aes(x = value_numeric, y = pd),
      color = "#D55E00", linewidth = 1.5
    ) +
    labs(
      title = paste("ICE Plot:", var_name),
      subtitle = "Gray = individual curves, Orange = average (PDP)",
      x = var_name,
      y = "Predicted Outcome"
    ) +
    theme_iop()

  if (!is.null(filename)) {
    save_figure(p, filename, width = 8, height = 6)
  }

  return(p)
}

#' Generate ICE plots for multiple variables
#' @param model fitted model
#' @param data data frame
#' @param var_names vector of variable names
#' @param n_sample observations to sample
#' @return list of ggplot objects
plot_ice_all <- function(model, data, var_names, n_sample = 100) {

  log_msg("Generating ICE plots for ", length(var_names), " variables")

  plots <- list()

  for (var in var_names) {
    log_msg("  Processing: ", var)
    ice_data <- calculate_ice(model, data, var, n_sample)
    filename <- paste0("ice_", janitor::make_clean_names(var))
    plots[[var]] <- plot_ice(ice_data, var, filename)
  }

  return(plots)
}

# ============================================================================
# 3. Variable Interaction Plots
# ============================================================================

#' Calculate 2D partial dependence (interaction)
#' @param model fitted model
#' @param data data frame
#' @param var1 first variable name
#' @param var2 second variable name
#' @param grid_resolution grid points per variable
#' @return tibble with 2D PD values
calculate_pd_2d <- function(model, data, var1, var2, grid_resolution = 20) {

  # Get variable values
  x1 <- data[[var1]]
  x2 <- data[[var2]]

  # Create grids
  if (is.numeric(x1)) {
    grid1 <- seq(min(x1, na.rm = TRUE), max(x1, na.rm = TRUE),
                 length.out = grid_resolution)
  } else {
    grid1 <- unique(x1)
  }

  if (is.numeric(x2)) {
    grid2 <- seq(min(x2, na.rm = TRUE), max(x2, na.rm = TRUE),
                 length.out = grid_resolution)
  } else {
    grid2 <- unique(x2)
  }

  # Calculate PD for all combinations
  results <- expand.grid(
    var1_val = grid1,
    var2_val = grid2
  )

  results$pd <- mapply(function(v1, v2) {
    data_mod <- data
    data_mod[[var1]] <- v1
    data_mod[[var2]] <- v2
    mean(predict(model, newdata = data_mod, type = "response"), na.rm = TRUE)
  }, results$var1_val, results$var2_val)

  results$var1 <- var1
  results$var2 <- var2

  return(as_tibble(results))
}

#' Plot 2D partial dependence (heatmap)
#' @param pd_2d tibble from calculate_pd_2d
#' @param filename output filename
#' @return ggplot object
plot_pd_2d <- function(pd_2d, filename = NULL) {

  var1 <- unique(pd_2d$var1)
  var2 <- unique(pd_2d$var2)

  p <- ggplot(pd_2d, aes(x = var1_val, y = var2_val, fill = pd)) +
    geom_tile() +
    scale_fill_viridis_c(option = "plasma", name = "Predicted\nOutcome") +
    labs(
      title = paste("Interaction:", var1, "x", var2),
      x = var1,
      y = var2
    ) +
    theme_iop() +
    theme(legend.position = "right")

  if (!is.null(filename)) {
    save_figure(p, filename, width = 8, height = 6)
  }

  return(p)
}

# ============================================================================
# 4. Using iml Package (Alternative)
# ============================================================================

#' Create IML predictor object
#' @param model fitted model
#' @param data data frame
#' @param outcome outcome variable name
#' @return iml Predictor object
create_iml_predictor <- function(model, data, outcome) {

  # Define prediction function for iml
  pred_fn <- function(model, newdata) {
    predict(model, newdata = newdata, type = "response")
  }

  # Create predictor object
  predictor <- iml::Predictor$new(
    model = model,
    data = data,
    y = data[[outcome]],
    predict.fun = pred_fn
  )

  return(predictor)
}

#' Generate feature effects using iml
#' @param predictor iml Predictor object
#' @param feature feature name
#' @param method "pdp", "ale", or "ice"
#' @return iml FeatureEffect object
calculate_feature_effect <- function(predictor, feature, method = "pdp+ice") {

  effect <- iml::FeatureEffect$new(
    predictor = predictor,
    feature = feature,
    method = method
  )

  return(effect)
}

# ============================================================================
# 5. Main Execution
# ============================================================================

run_interpretability_analysis <- function(model, data, circumstance_vars,
                                          outcome_var, top_n = 6) {

  log_msg("Starting interpretability analysis")

  # Load variable importance if available
  varimp_file <- get_path(config$paths$models, "varimp_bootstrap.rds")
  if (file.exists(varimp_file)) {
    varimp <- readRDS(varimp_file)
    top_vars <- varimp$summary %>%
      head(top_n) %>%
      pull(variable)
    log_msg("Using top ", top_n, " variables by importance")
  } else {
    top_vars <- circumstance_vars[1:min(top_n, length(circumstance_vars))]
    log_msg("Using first ", length(top_vars), " circumstance variables")
  }

  # 1. Generate PDPs
  log_msg("Generating partial dependence plots")
  pd_data <- calculate_pd_all(model, data, top_vars)
  save_table(pd_data, "pdp_data")
  plot_pdp_grid(pd_data)

  # 2. Generate ICE plots for top 3 variables
  log_msg("Generating ICE plots")
  ice_plots <- plot_ice_all(model, data, top_vars[1:min(3, length(top_vars))])

  # 3. Generate interaction plot for top 2 variables
  if (length(top_vars) >= 2) {
    log_msg("Generating interaction plot")
    pd_2d <- calculate_pd_2d(model, data, top_vars[1], top_vars[2])
    save_table(pd_2d, "pd_2d_data")
    plot_pd_2d(pd_2d, paste0("interaction_", top_vars[1], "_", top_vars[2]))
  }

  log_msg("Interpretability analysis complete")

  return(list(
    pd_data = pd_data,
    top_vars = top_vars
  ))
}

log_msg("06_interpretability.R loaded successfully")

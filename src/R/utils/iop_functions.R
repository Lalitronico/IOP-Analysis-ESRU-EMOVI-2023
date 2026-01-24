# ============================================================================
# iop_functions.R - Utility Functions for IOp Analysis
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Reusable helper functions for IOp calculations
# ============================================================================

# ============================================================================
# 1. Data Validation
# ============================================================================

#' Validate outcome variable for IOp analysis
#' @param x outcome variable
#' @param name variable name for error messages
#' @return TRUE if valid, error otherwise
validate_outcome <- function(x, name = "outcome") {
  assertthat::assert_that(
    is.numeric(x),
    msg = paste(name, "must be numeric")
  )

  assertthat::assert_that(
    sum(!is.na(x)) > 100,
    msg = paste(name, "must have more than 100 non-missing values")
  )

  if (any(x <= 0, na.rm = TRUE)) {
    warning(name, " has non-positive values; MLD/Theil metrics require positive values")
  }

  return(TRUE)
}

#' Validate circumstance variables
#' @param df data frame
#' @param vars character vector of variable names
#' @return TRUE if valid, error otherwise
validate_circumstances <- function(df, vars) {
  # Check all variables exist
  missing <- vars[!vars %in% names(df)]
  assertthat::assert_that(
    length(missing) == 0,
    msg = paste("Missing circumstance variables:", paste(missing, collapse = ", "))
  )

  # Check for constant variables
  constant <- vars[sapply(df[vars], function(x) length(unique(x[!is.na(x)])) <= 1)]
  if (length(constant) > 0) {
    warning("Constant circumstance variables (will be dropped): ",
            paste(constant, collapse = ", "))
  }

  return(TRUE)
}

# ============================================================================
# 2. Inequality Metrics (Extended)
# ============================================================================

#' Calculate Atkinson index
#' @param x numeric vector (positive values)
#' @param epsilon inequality aversion parameter (0 = no aversion, higher = more aversion)
#' @param weights optional sample weights
#' @return Atkinson index
atkinson <- function(x, epsilon = 1, weights = NULL) {
  x <- x[!is.na(x) & x > 0]

  if (is.null(weights)) {
    weights <- rep(1, length(x))
  } else {
    weights <- weights[!is.na(x) & x > 0]
  }
  weights <- weights / sum(weights)

  mu <- sum(weights * x)

  if (epsilon == 1) {
    # Special case: Atkinson(1) = 1 - exp(mean(log(x))) / mean(x)
    ede <- exp(sum(weights * log(x)))
  } else {
    # General case
    ede <- (sum(weights * x^(1 - epsilon)))^(1 / (1 - epsilon))
  }

  atk <- 1 - ede / mu
  return(atk)
}

#' Calculate generalized entropy index GE(alpha)
#' @param x numeric vector (positive values)
#' @param alpha parameter (0 = MLD, 1 = Theil, 2 = half CV squared)
#' @param weights optional sample weights
#' @return GE(alpha) value
generalized_entropy <- function(x, alpha = 1, weights = NULL) {
  x <- x[!is.na(x) & x > 0]

  if (is.null(weights)) {
    weights <- rep(1, length(x))
  } else {
    weights <- weights[!is.na(x) & x > 0]
  }
  weights <- weights / sum(weights)

  mu <- sum(weights * x)

  if (alpha == 0) {
    # MLD
    ge <- sum(weights * log(mu / x))
  } else if (alpha == 1) {
    # Theil
    ge <- sum(weights * (x / mu) * log(x / mu))
  } else {
    # General case
    ge <- (1 / (alpha * (alpha - 1))) *
      (sum(weights * (x / mu)^alpha) - 1)
  }

  return(ge)
}

# ============================================================================
# 3. IOp Bounds
# ============================================================================

#' Calculate lower bound of IOp (parametric)
#' Based on Ferreira & Gignoux (2011): uses OLS predictions
#' @param outcome outcome variable
#' @param circumstances data frame of circumstances
#' @param weights optional sample weights
#' @return IOp lower bound
iop_lower_bound <- function(outcome, circumstances, weights = NULL) {

  # Fit OLS
  df <- cbind(y = outcome, circumstances)
  model <- lm(y ~ ., data = df)

  # Get predictions
  predictions <- predict(model, newdata = df)

  # Calculate IOp share
  gini_total <- gini_coef(outcome, weights)
  gini_between <- gini_coef(predictions, weights)

  return(gini_between / gini_total)
}

#' Calculate upper bound of IOp (non-parametric with many types)
#' Uses finer partition of circumstances
#' @param outcome outcome variable
#' @param circumstances data frame of circumstances
#' @param weights optional sample weights
#' @return IOp upper bound estimate
iop_upper_bound <- function(outcome, circumstances, weights = NULL) {

  # Create fine partition by interacting all circumstances
  # This creates many small cells (types)

  # Discretize continuous variables
  circumstances_disc <- circumstances %>%
    mutate(across(where(is.numeric), ~cut(., breaks = 5, labels = FALSE)))

  # Create type indicator
  type <- interaction(circumstances_disc, drop = TRUE)

  # Calculate type means
  df <- data.frame(y = outcome, type = type)
  if (!is.null(weights)) df$w <- weights

  type_means <- df %>%
    group_by(type) %>%
    summarise(
      mean_y = if (is.null(weights)) mean(y, na.rm = TRUE) else weighted.mean(y, w, na.rm = TRUE),
      .groups = "drop"
    )

  # Merge back
  df <- df %>%
    left_join(type_means, by = "type")

  # Calculate IOp share
  gini_total <- gini_coef(outcome, weights)
  gini_between <- gini_coef(df$mean_y, weights)

  return(gini_between / gini_total)
}

# ============================================================================
# 4. Sensitivity Analysis Helpers
# ============================================================================

#' Run IOp analysis for multiple circumstance sets
#' @param outcome outcome variable
#' @param all_circumstances data frame with all circumstances
#' @param circumstance_sets named list of variable vectors
#' @param model_fn function to fit model
#' @param weights optional sample weights
#' @return tibble with IOp estimates for each set
compare_circumstance_sets <- function(outcome, all_circumstances,
                                       circumstance_sets, model_fn,
                                       weights = NULL) {

  results <- map_dfr(names(circumstance_sets), function(set_name) {
    vars <- circumstance_sets[[set_name]]

    # Subset circumstances
    circ <- all_circumstances[, vars, drop = FALSE]

    # Prepare complete cases
    complete <- complete.cases(cbind(outcome, circ))
    y <- outcome[complete]
    X <- circ[complete, ]
    w <- if (!is.null(weights)) weights[complete] else NULL

    # Fit model and get predictions
    mu <- model_fn(y, X)

    # Calculate IOp
    iop_gini <- gini_coef(mu, w) / gini_coef(y, w)
    iop_mld <- mld(mu, w) / mld(y, w)

    tibble(
      circumstance_set = set_name,
      n_circumstances = length(vars),
      n_obs = sum(complete),
      iop_gini = iop_gini,
      iop_mld = iop_mld
    )
  })

  return(results)
}

#' Run IOp analysis for subgroups
#' @param data full dataset
#' @param outcome_var outcome variable name
#' @param circumstance_vars circumstance variable names
#' @param group_var grouping variable name
#' @param model_fn function to fit model
#' @param weight_var optional weight variable name
#' @return tibble with IOp estimates for each group
compare_subgroups <- function(data, outcome_var, circumstance_vars,
                              group_var, model_fn, weight_var = NULL) {

  groups <- unique(data[[group_var]])

  results <- map_dfr(groups, function(g) {
    # Subset data
    df_sub <- data %>% filter(!!sym(group_var) == g)

    y <- df_sub[[outcome_var]]
    X <- df_sub[, circumstance_vars, drop = FALSE]
    w <- if (!is.null(weight_var)) df_sub[[weight_var]] else NULL

    # Prepare complete cases
    complete <- complete.cases(cbind(y, X))
    y <- y[complete]
    X <- X[complete, ]
    w <- if (!is.null(w)) w[complete] else NULL

    if (length(y) < 100) {
      warning("Subgroup ", g, " has fewer than 100 observations")
      return(NULL)
    }

    # Fit model and get predictions
    mu <- model_fn(y, X)

    # Calculate IOp
    tibble(
      group = as.character(g),
      n_obs = length(y),
      gini_total = gini_coef(y, w),
      iop_gini = gini_coef(mu, w) / gini_coef(y, w),
      iop_mld = mld(mu, w) / mld(y, w)
    )
  })

  return(results)
}

# ============================================================================
# 5. Reporting Helpers
# ============================================================================

#' Format IOp results for publication
#' @param iop_value IOp share (0-1)
#' @param ci_lower lower CI bound
#' @param ci_upper upper CI bound
#' @param digits decimal places
#' @return formatted string
format_iop_result <- function(iop_value, ci_lower = NULL, ci_upper = NULL,
                              digits = 3) {

  main <- round(iop_value * 100, digits - 1)

  if (!is.null(ci_lower) && !is.null(ci_upper)) {
    lower <- round(ci_lower * 100, digits - 1)
    upper <- round(ci_upper * 100, digits - 1)
    return(paste0(main, "% [", lower, "%, ", upper, "%]"))
  } else {
    return(paste0(main, "%"))
  }
}

#' Create LaTeX table of IOp results
#' @param results tibble with IOp results
#' @param caption table caption
#' @param label LaTeX label
#' @return character string with LaTeX code
create_latex_table <- function(results, caption = "IOp Results",
                               label = "tab:iop") {

  results %>%
    kableExtra::kbl(
      caption = caption,
      format = "latex",
      booktabs = TRUE,
      digits = 3
    ) %>%
    kableExtra::kable_styling(
      latex_options = c("hold_position", "striped")
    )
}

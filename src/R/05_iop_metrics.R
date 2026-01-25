# ============================================================================
# 05_iop_metrics.R - Inequality of Opportunity Metrics
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Calculate IOp indices (Gini, MLD, R²) from tree-based partitions
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

log_msg("Loading IOp metrics functions")

# ============================================================================
# 1. Core IOp Functions
# ============================================================================

#' Calculate Gini coefficient
#' @param x numeric vector
#' @param weights optional sample weights
#' @return Gini coefficient (0 = perfect equality, 1 = perfect inequality)
gini_coef <- function(x, weights = NULL) {
  # Remove NAs
  valid <- !is.na(x)
  x <- x[valid]

  if (length(x) == 0) return(NA_real_)

  if (is.null(weights)) {
    weights <- rep(1, length(x))
  } else {
    weights <- weights[valid]
  }

  # Sort by x

  ord <- order(x)
  x <- x[ord]
  weights <- weights[ord]

  # Normalize weights
  weights <- weights / sum(weights)

  # Weighted Gini using covariance formula
  n <- length(x)
  cum_w <- cumsum(weights)
  mu <- sum(weights * x)

  # Gini = (2 / mu) * Cov(x, F(x)) where F(x) is cumulative distribution
  # Approximation: Gini = (2 * sum(w * x * cumw) / mu) - 1
  gini <- (2 * sum(weights * x * cum_w) / mu) - 1

  return(max(0, min(1, gini)))
}

#' Calculate Mean Log Deviation (MLD / Theil L)
#' @param x numeric vector (must be positive)
#' @param weights optional sample weights
#' @return MLD value
mld <- function(x, weights = NULL) {
  x <- x[!is.na(x) & x > 0]  # MLD requires positive values

  if (length(x) == 0) return(NA_real_)

  if (is.null(weights)) {
    mu <- mean(x)
    return(mean(log(mu / x)))
  } else {
    weights <- weights[!is.na(x) & x > 0]
    weights <- weights / sum(weights)
    mu <- sum(weights * x)
    return(sum(weights * log(mu / x)))
  }
}

#' Calculate Theil index (GE(1))
#' @param x numeric vector (must be positive)
#' @param weights optional sample weights
#' @return Theil index
theil <- function(x, weights = NULL) {
  x <- x[!is.na(x) & x > 0]

  if (length(x) == 0) return(NA_real_)

  if (is.null(weights)) {
    mu <- mean(x)
    return(mean((x / mu) * log(x / mu)))
  } else {
    weights <- weights[!is.na(x) & x > 0]
    weights <- weights / sum(weights)
    mu <- sum(weights * x)
    return(sum(weights * (x / mu) * log(x / mu)))
  }
}

#' Calculate coefficient of variation
#' @param x numeric vector
#' @param weights optional sample weights
#' @return CV value
cv <- function(x, weights = NULL) {
  x <- x[!is.na(x)]

  if (is.null(weights)) {
    return(sd(x) / mean(x))
  } else {
    weights <- weights[!is.na(x)]
    mu <- weighted.mean(x, weights)
    var_w <- sum(weights * (x - mu)^2) / sum(weights)
    return(sqrt(var_w) / mu)
  }
}

# ============================================================================
# 2. IOp Share Calculations (Ex-Ante Approach)
# ============================================================================

#' Calculate IOp share using type means (ex-ante approach)
#' This is the Roemer/Fleurbaey definition: IOp = Ineq(smoothed) / Ineq(total)
#' where smoothed distribution replaces each Y with its type mean
#'
#' @param observed observed outcome values
#' @param type_means predicted type means (from ctree/cforest)
#' @param weights optional sample weights
#' @param metric inequality metric ("gini", "mld", "theil", "cv")
#' @return list with IOp share and component values
calculate_iop_share <- function(observed, type_means, weights = NULL,
                                 metric = "gini") {

  # Remove missing values
  valid <- !is.na(observed) & !is.na(type_means)
  y <- observed[valid]
  mu <- type_means[valid]
  w <- if (!is.null(weights)) weights[valid] else NULL

  # Select inequality function
  ineq_fn <- switch(metric,
                    gini = gini_coef,
                    mld = mld,
                    theil = theil,
                    cv = cv,
                    stop("Unknown metric: ", metric))

  # Calculate total inequality
  ineq_total <- ineq_fn(y, w)

  # Calculate inequality of type means (between-type inequality)
  ineq_between <- ineq_fn(mu, w)

  # IOp share = between / total
  iop_share <- ineq_between / ineq_total

  return(list(
    iop_share = iop_share,
    ineq_total = ineq_total,
    ineq_between = ineq_between,
    metric = metric,
    n = length(y)
  ))
}

#' Calculate R-squared based IOp share
#' R² = Var(type_means) / Var(observed) = 1 - Var(residuals) / Var(observed)
#'
#' @param observed observed outcome values
#' @param type_means predicted type means
#' @param weights optional sample weights
#' @return R-squared value
calculate_iop_rsq <- function(observed, type_means, weights = NULL) {

  valid <- !is.na(observed) & !is.na(type_means)
  y <- observed[valid]
  mu <- type_means[valid]

  if (is.null(weights)) {
    var_total <- var(y)
    var_explained <- var(mu)
    rsq <- var_explained / var_total
  } else {
    w <- weights[valid]
    w <- w / sum(w)
    mean_y <- sum(w * y)
    var_total <- sum(w * (y - mean_y)^2)
    var_explained <- sum(w * (mu - mean_y)^2)
    rsq <- var_explained / var_total
  }

  return(rsq)
}

# ============================================================================
# 3. MLD Decomposition
# ============================================================================

#' Decompose MLD into between-type and within-type components
#' MLD_total = MLD_between + MLD_within
#'
#' @param observed observed outcome values
#' @param types type assignments (factor or integer)
#' @param weights optional sample weights
#' @return list with decomposition components
decompose_mld <- function(observed, types, weights = NULL) {

  # Create data frame
  df <- tibble(
    y = observed,
    type = types,
    w = if (is.null(weights)) rep(1, length(observed)) else weights
  ) %>%
    filter(!is.na(y) & y > 0 & !is.na(type))

  # Total MLD
  mld_total <- mld(df$y, df$w)

  # Calculate type-level statistics
  type_stats <- df %>%
    group_by(type) %>%
    summarise(
      n = n(),
      total_weight = sum(w),
      mean_y = weighted.mean(y, w),
      mld_within = mld(y, w),
      .groups = "drop"
    ) %>%
    mutate(
      pop_share = total_weight / sum(total_weight),
      income_share = (mean_y * total_weight) / sum(mean_y * total_weight)
    )

  # Between-type MLD: MLD of type means (weighted by population share)
  mld_between <- mld(type_stats$mean_y, type_stats$total_weight)

  # Within-type MLD: weighted average of within-type MLDs
  mld_within <- sum(type_stats$pop_share * type_stats$mld_within, na.rm = TRUE)

  # IOp share
  iop_share <- mld_between / mld_total

  return(list(
    mld_total = mld_total,
    mld_between = mld_between,
    mld_within = mld_within,
    iop_share = iop_share,
    type_stats = type_stats,
    n_types = nrow(type_stats)
  ))
}

# ============================================================================
# 4. Bootstrap Confidence Intervals
# ============================================================================

#' Bootstrap IOp estimates for confidence intervals
#'
#' @param observed observed outcome values
#' @param circumstances matrix of circumstance variables
#' @param model_fn function to fit model and get predictions
#' @param n_boot number of bootstrap samples
#' @param seeds bootstrap seeds
#' @param weights optional sample weights
#' @param metrics vector of metrics to compute
#' @return list with summary and all bootstrap results
bootstrap_iop <- function(observed, circumstances, model_fn,
                          n_boot = 100, seeds = SEEDS$bootstrap,
                          weights = NULL, metrics = c("gini", "mld", "rsq")) {

  log_msg("Bootstrapping IOp estimates with ", n_boot, " replications")

  n <- length(observed)
  results <- list()

  for (b in 1:n_boot) {
    if (b %% 20 == 0) log_msg("Bootstrap ", b, "/", n_boot)

    set.seed(seeds[b])

    # Bootstrap sample
    idx <- sample(1:n, replace = TRUE)
    y_boot <- observed[idx]
    X_boot <- if (is.data.frame(circumstances)) {
      circumstances[idx, ]
    } else {
      circumstances[idx, , drop = FALSE]
    }
    w_boot <- if (!is.null(weights)) weights[idx] else NULL

    # Fit model and get predictions
    mu_boot <- model_fn(y_boot, X_boot)

    # Calculate metrics
    boot_results <- list(b = b)

    if ("gini" %in% metrics) {
      iop <- calculate_iop_share(y_boot, mu_boot, w_boot, "gini")
      boot_results$iop_gini <- iop$iop_share
      boot_results$gini_total <- iop$ineq_total
    }

    if ("mld" %in% metrics) {
      iop <- calculate_iop_share(y_boot, mu_boot, w_boot, "mld")
      boot_results$iop_mld <- iop$iop_share
      boot_results$mld_total <- iop$ineq_total
    }

    if ("rsq" %in% metrics) {
      boot_results$iop_rsq <- calculate_iop_rsq(y_boot, mu_boot, w_boot)
    }

    results[[b]] <- as_tibble(boot_results)
  }

  # Combine results
  all_results <- bind_rows(results)

  # Compute summary statistics
  summary <- tibble(
    metric = c("iop_gini", "iop_mld", "iop_rsq"),
    mean = c(
      if ("gini" %in% metrics) mean(all_results$iop_gini, na.rm = TRUE) else NA,
      if ("mld" %in% metrics) mean(all_results$iop_mld, na.rm = TRUE) else NA,
      if ("rsq" %in% metrics) mean(all_results$iop_rsq, na.rm = TRUE) else NA
    ),
    sd = c(
      if ("gini" %in% metrics) sd(all_results$iop_gini, na.rm = TRUE) else NA,
      if ("mld" %in% metrics) sd(all_results$iop_mld, na.rm = TRUE) else NA,
      if ("rsq" %in% metrics) sd(all_results$iop_rsq, na.rm = TRUE) else NA
    ),
    ci_lower = c(
      if ("gini" %in% metrics) quantile(all_results$iop_gini, 0.025, na.rm = TRUE) else NA,
      if ("mld" %in% metrics) quantile(all_results$iop_mld, 0.025, na.rm = TRUE) else NA,
      if ("rsq" %in% metrics) quantile(all_results$iop_rsq, 0.025, na.rm = TRUE) else NA
    ),
    ci_upper = c(
      if ("gini" %in% metrics) quantile(all_results$iop_gini, 0.975, na.rm = TRUE) else NA,
      if ("mld" %in% metrics) quantile(all_results$iop_mld, 0.975, na.rm = TRUE) else NA,
      if ("rsq" %in% metrics) quantile(all_results$iop_rsq, 0.975, na.rm = TRUE) else NA
    )
  ) %>%
    filter(!is.na(mean))

  return(list(summary = summary, all_results = all_results))
}

# ============================================================================
# 5. Summary Table Generation
# ============================================================================

#' Create comprehensive IOp summary table
#'
#' @param observed observed outcome
#' @param type_means predicted type means
#' @param types type assignments
#' @param weights optional sample weights
#' @return tibble with all IOp metrics
create_iop_summary <- function(observed, type_means, types, weights = NULL) {

  # Calculate all metrics
  iop_gini <- calculate_iop_share(observed, type_means, weights, "gini")
  iop_mld <- calculate_iop_share(observed, type_means, weights, "mld")
  iop_rsq <- calculate_iop_rsq(observed, type_means, weights)
  mld_decomp <- decompose_mld(observed, types, weights)

  # Create summary table
  summary <- tibble(
    metric = c(
      "Total Inequality (Gini)",
      "Total Inequality (MLD)",
      "Between-Type Inequality (Gini)",
      "Between-Type Inequality (MLD)",
      "IOp Share (Gini-based)",
      "IOp Share (MLD-based)",
      "IOp Share (R²)",
      "Number of Types",
      "Sample Size"
    ),
    value = c(
      iop_gini$ineq_total,
      iop_mld$ineq_total,
      iop_gini$ineq_between,
      iop_mld$ineq_between,
      iop_gini$iop_share,
      iop_mld$iop_share,
      iop_rsq,
      mld_decomp$n_types,
      iop_gini$n
    ),
    interpretation = c(
      "Overall outcome inequality",
      "Overall outcome inequality (log-based)",
      "Inequality due to circumstances",
      "Inequality due to circumstances (log-based)",
      "% of inequality due to circumstances (Gini)",
      "% of inequality due to circumstances (MLD)",
      "Variance explained by circumstances",
      "Number of circumstance-based groups",
      "Observations used"
    )
  )

  return(summary)
}

# ============================================================================
# 6. Visualization Functions
# ============================================================================

#' Plot IOp decomposition
#' @param iop_summary tibble from create_iop_summary
#' @param filename output filename
#' @return ggplot object
plot_iop_decomposition <- function(iop_summary, filename = "iop_decomposition") {

  # Extract IOp shares for plotting
  iop_values <- iop_summary %>%
    filter(grepl("IOp Share", metric)) %>%
    mutate(
      metric_short = case_when(
        grepl("Gini", metric) ~ "Gini-based",
        grepl("MLD", metric) ~ "MLD-based",
        grepl("R²", metric) ~ "R²-based"
      ),
      percentage = value * 100
    )

  p <- ggplot(iop_values, aes(x = metric_short, y = percentage, fill = metric_short)) +
    geom_col(width = 0.6) +
    geom_text(aes(label = paste0(round(percentage, 1), "%")),
              vjust = -0.5, size = 4, fontface = "bold") +
    scale_fill_manual(values = c("Gini-based" = "#0072B2",
                                  "MLD-based" = "#009E73",
                                  "R²-based" = "#D55E00")) +
    scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    labs(
      title = "Inequality of Opportunity Share",
      subtitle = "Percentage of total inequality due to circumstances",
      x = NULL,
      y = "IOp Share (%)"
    ) +
    theme_iop() +
    theme(legend.position = "none")

  save_figure(p, filename, width = 7, height = 5)

  return(p)
}

#' Plot type means distribution
#' @param type_stats tibble with type statistics
#' @param filename output filename
#' @return ggplot object
plot_type_distribution <- function(type_stats, filename = "type_distribution") {

  p <- type_stats %>%
    arrange(mean_y) %>%
    mutate(type = factor(type, levels = type)) %>%
    ggplot(aes(x = type, y = mean_y, size = pop_share)) +
    geom_point(color = "#0072B2", alpha = 0.7) +
    scale_size_continuous(
      name = "Population Share",
      range = c(2, 10),
      labels = scales::percent
    ) +
    labs(
      title = "Type Means and Population Shares",
      subtitle = "Each point is a circumstance-based type",
      x = "Type (ordered by mean outcome)",
      y = "Mean Outcome"
    ) +
    theme_iop() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))

  save_figure(p, filename, width = 10, height = 6)

  return(p)
}

# ============================================================================
# 7. Main Execution
# ============================================================================

run_iop_analysis <- function(model, data, outcome_var, weight_var = NULL) {

  log_msg("Calculating IOp metrics")

  # Get predictions
  type_means <- predict(model, newdata = data, type = "response")
  types <- predict(model, newdata = data, type = "node")

  observed <- data[[outcome_var]]
  weights <- if (!is.null(weight_var)) data[[weight_var]] else NULL

  # Calculate all metrics
  iop_summary <- create_iop_summary(observed, type_means, types, weights)

  # Print summary
  cat("\n")
  cat(paste(rep("=", 60), collapse = ""), "\n")
  cat("INEQUALITY OF OPPORTUNITY ANALYSIS RESULTS\n")
  cat(paste(rep("=", 60), collapse = ""), "\n")
  print(iop_summary, n = Inf)
  cat(paste(rep("=", 60), collapse = ""), "\n")

  # Save and plot
  save_table(iop_summary, "iop_main_results")

  plot_iop_decomposition(iop_summary)

  mld_decomp <- decompose_mld(observed, types, weights)
  plot_type_distribution(mld_decomp$type_stats)

  log_msg("IOp analysis complete")

  return(list(
    summary = iop_summary,
    mld_decomposition = mld_decomp,
    type_means = type_means,
    types = types
  ))
}

log_msg("05_iop_metrics.R loaded successfully")

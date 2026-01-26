# ============================================================================
# 08_shapley_decomposition.R - Shapley Decomposition of IOp
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Formal Shapley decomposition following Ferreira & Gignoux (2011)
# ============================================================================
#
# IMPORTANT DISTINCTION:
# This is NOT the same as SHAP (SHapley Additive exPlanations) from ML.
# - SHAP: Decomposes individual predictions
# - Shapley IOp: Decomposes aggregate inequality measure
#
# Shapley IOp asks: "What is each circumstance's marginal contribution
# to total IOp, averaged over all possible orderings?"
#
# ============================================================================

# Load setup and previous scripts
source(here::here("src", "R", "00_setup.R"))
source(here::here("src", "R", "05_iop_metrics.R"))

log_msg("Starting Shapley decomposition module")

# ============================================================================
# 1. Shapley Decomposition Theory
# ============================================================================
#
# For K circumstances, the Shapley value of circumstance k is:
#
#   φ_k = Σ_{S ⊆ K\{k}} [|S|!(K-|S|-1)!/K!] × [IOp(S∪{k}) - IOp(S)]
#
# This requires computing IOp for ALL 2^K subsets of circumstances.
#
# For K=9 (standard set): 2^9 = 512 subsets
# For K=14 (maximum set): 2^14 = 16,384 subsets (computationally expensive)
#
# ============================================================================

# ============================================================================
# 2. Generate All Subsets
# ============================================================================

#' Generate all subsets of a vector
#' @param elements Vector of elements
#' @return List of all subsets (including empty set)
generate_all_subsets <- function(elements) {
  n <- length(elements)
  subsets <- list()

  # Generate all 2^n subsets using binary representation
  for (i in 0:(2^n - 1)) {
    # Convert to binary and select elements
    binary <- as.integer(intToBits(i)[1:n])
    subset <- elements[binary == 1]
    subsets[[length(subsets) + 1]] <- subset
  }

  return(subsets)
}

#' Count subset sizes
#' @param subsets List of subsets
#' @return Table of sizes
count_subset_sizes <- function(subsets) {
  sizes <- sapply(subsets, length)
  table(sizes)
}

# ============================================================================
# 3. Calculate IOp for Each Subset
# ============================================================================

#' Calculate IOp for a given subset of circumstances
#' @param df Data frame
#' @param outcome Outcome variable name
#' @param circumstances Vector of circumstance names
#' @param metric IOp metric ("gini", "mld", "rsq")
#' @return Numeric IOp value
calculate_iop_subset <- function(df, outcome, circumstances, metric = "gini") {

  # Handle empty set: IOp = 0 (no circumstances explain anything)
  if (length(circumstances) == 0) {
    return(0)
  }

  # Prepare data
  vars_needed <- c(outcome, circumstances)
  df_analysis <- df %>%
    select(any_of(vars_needed)) %>%
    drop_na()

  if (nrow(df_analysis) < 100) {
    return(NA_real_)
  }

  # Check which circumstances are available
  available <- circumstances[circumstances %in% names(df_analysis)]

  if (length(available) == 0) {
    return(0)
  }

  # Fit ctree
  formula <- as.formula(paste(outcome, "~", paste(available, collapse = " + ")))

  ctrl <- partykit::ctree_control(
    mincriterion = 0.95,
    minsplit = 100,
    minbucket = 50,
    maxdepth = 6
  )

  model <- tryCatch(
    partykit::ctree(formula, data = df_analysis, control = ctrl),
    error = function(e) NULL
  )

  if (is.null(model)) {
    return(NA_real_)
  }

  # Calculate IOp
  type_means <- predict(model, type = "response")
  y <- df_analysis[[outcome]]

  if (metric == "rsq") {
    iop <- calculate_iop_rsq(y, type_means)
  } else {
    iop_result <- calculate_iop_share(y, type_means, metric = metric)
    iop <- iop_result$iop_share
  }

  return(iop)
}

# ============================================================================
# 4. Main Shapley Calculation
# ============================================================================

#' Calculate Shapley decomposition of IOp
#'
#' @param df Data frame
#' @param outcome Outcome variable name
#' @param circumstances Vector of circumstance names
#' @param metric IOp metric ("gini", "mld", "rsq")
#' @param verbose Print progress
#' @return List with Shapley values and all subset IOps
shapley_iop_decomposition <- function(df,
                                       outcome = "ingc_pc",
                                       circumstances,
                                       metric = "gini",
                                       verbose = TRUE) {

  K <- length(circumstances)

  if (verbose) {
    log_msg("\n", paste(rep("=", 60), collapse = ""))
    log_msg("SHAPLEY DECOMPOSITION OF IOp")
    log_msg(paste(rep("=", 60), collapse = ""))
    log_msg("Circumstances (K=", K, "): ", paste(circumstances, collapse = ", "))
    log_msg("Total subsets to evaluate: 2^", K, " = ", 2^K)
    log_msg("Metric: ", metric)
    log_msg(paste(rep("=", 60), collapse = ""))
  }

  # Generate all subsets
  all_subsets <- generate_all_subsets(circumstances)

  if (verbose) {
    log_msg("\nStep 1: Computing IOp for all ", length(all_subsets), " subsets...")
  }

  # Calculate IOp for each subset
  subset_iops <- list()

  for (i in seq_along(all_subsets)) {
    if (verbose && i %% 50 == 0) {
      log_msg("  Progress: ", i, "/", length(all_subsets),
              " (", round(i/length(all_subsets)*100, 1), "%)")
    }

    subset <- all_subsets[[i]]
    subset_key <- paste(sort(subset), collapse = "+")
    if (length(subset) == 0) subset_key <- "(empty)"

    iop_value <- calculate_iop_subset(df, outcome, subset, metric)

    subset_iops[[i]] <- list(
      subset = subset,
      key = subset_key,
      size = length(subset),
      iop = iop_value
    )
  }

  # Convert to data frame for easier lookup
  subset_df <- tibble(
    key = sapply(subset_iops, function(x) x$key),
    size = sapply(subset_iops, function(x) x$size),
    iop = sapply(subset_iops, function(x) x$iop)
  )

  if (verbose) {
    log_msg("\nStep 2: Calculating Shapley values...")
  }

  # Calculate Shapley value for each circumstance
  shapley_values <- numeric(K)
  names(shapley_values) <- circumstances

  for (k in 1:K) {
    circ_k <- circumstances[k]
    other_circs <- circumstances[-k]

    # Generate all subsets of other circumstances
    other_subsets <- generate_all_subsets(other_circs)

    # Calculate marginal contributions
    marginal_contributions <- numeric(length(other_subsets))
    weights <- numeric(length(other_subsets))

    for (j in seq_along(other_subsets)) {
      S <- other_subsets[[j]]
      S_with_k <- c(S, circ_k)

      # Get keys
      key_S <- if (length(S) == 0) "(empty)" else paste(sort(S), collapse = "+")
      key_S_k <- paste(sort(S_with_k), collapse = "+")

      # Look up IOp values
      iop_S <- subset_df$iop[subset_df$key == key_S]
      iop_S_k <- subset_df$iop[subset_df$key == key_S_k]

      if (length(iop_S) == 0) iop_S <- NA
      if (length(iop_S_k) == 0) iop_S_k <- NA

      # Marginal contribution
      marginal_contributions[j] <- iop_S_k - iop_S

      # Shapley weight: |S|!(K-|S|-1)!/K!
      s <- length(S)
      weights[j] <- factorial(s) * factorial(K - s - 1) / factorial(K)
    }

    # Shapley value = weighted sum of marginal contributions
    valid <- !is.na(marginal_contributions)
    if (sum(valid) > 0) {
      # Re-normalize weights for valid contributions
      weights_valid <- weights[valid] / sum(weights[valid])
      shapley_values[k] <- sum(weights_valid * marginal_contributions[valid])
    } else {
      shapley_values[k] <- NA
    }
  }

  # Normalize to percentages (sum should approximately equal total IOp)
  total_iop <- subset_df$iop[subset_df$size == K]
  shapley_pct <- shapley_values / sum(shapley_values, na.rm = TRUE) * 100

  # Create results table
  results <- tibble(
    circumstance = names(shapley_values),
    shapley_value = shapley_values,
    shapley_pct = shapley_pct,
    rank = rank(-shapley_values, na.last = TRUE)
  ) %>%
    arrange(rank)

  if (verbose) {
    log_msg("\n", paste(rep("=", 60), collapse = ""))
    log_msg("SHAPLEY DECOMPOSITION RESULTS")
    log_msg(paste(rep("=", 60), collapse = ""))
    log_msg("Total IOp (", metric, "): ", round(total_iop * 100, 2), "%")
    log_msg("Sum of Shapley values: ", round(sum(shapley_values, na.rm = TRUE) * 100, 2), "%")
    log_msg("\nContributions by circumstance:")

    for (i in 1:nrow(results)) {
      log_msg("  ", i, ". ", results$circumstance[i], ": ",
              round(results$shapley_pct[i], 1), "%",
              " (Shapley = ", round(results$shapley_value[i], 4), ")")
    }
    log_msg(paste(rep("=", 60), collapse = ""))
  }

  return(list(
    shapley_values = shapley_values,
    shapley_pct = shapley_pct,
    results = results,
    subset_iops = subset_df,
    total_iop = total_iop,
    metric = metric,
    circumstances = circumstances,
    K = K
  ))
}

# ============================================================================
# 5. Visualization
# ============================================================================

#' Plot Shapley decomposition results
#' @param shapley_result Result from shapley_iop_decomposition
#' @param filename Output filename
#' @return ggplot object
plot_shapley_decomposition <- function(shapley_result,
                                        filename = "shapley_decomposition") {

  results <- shapley_result$results

  # Bar plot of contributions
  p <- results %>%
    mutate(circumstance = factor(circumstance, levels = rev(circumstance))) %>%
    ggplot(aes(x = circumstance, y = shapley_pct, fill = shapley_pct)) +
    geom_col(width = 0.7) +
    geom_text(aes(label = paste0(round(shapley_pct, 1), "%")),
              hjust = -0.1, size = 3.5) +
    coord_flip() +
    scale_fill_gradient(low = "#56B4E9", high = "#0072B2", guide = "none") +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(
      title = "Shapley Decomposition of Inequality of Opportunity",
      subtitle = paste0("Contribution of each circumstance to total IOp (",
                        shapley_result$metric, "-based)"),
      x = "Circumstance",
      y = "Contribution to IOp (%)",
      caption = paste0("Total IOp: ", round(shapley_result$total_iop * 100, 1),
                       "% | Method: Ferreira & Gignoux (2011)")
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(face = "bold"),
      panel.grid.major.y = element_blank()
    )

  ggsave(
    get_path(config$paths$figures, paste0(filename, ".png")),
    p, width = 10, height = 7, dpi = 300
  )

  log_msg("Saved plot: ", filename, ".png")

  return(p)
}

#' Plot IOp as function of number of circumstances
#' @param shapley_result Result from shapley_iop_decomposition
#' @param filename Output filename
#' @return ggplot object
plot_iop_by_subset_size <- function(shapley_result,
                                     filename = "iop_by_subset_size") {

  subset_df <- shapley_result$subset_iops

  # Summary by subset size
  size_summary <- subset_df %>%
    group_by(size) %>%
    summarise(
      mean_iop = mean(iop, na.rm = TRUE),
      min_iop = min(iop, na.rm = TRUE),
      max_iop = max(iop, na.rm = TRUE),
      n_subsets = n(),
      .groups = "drop"
    )

  p <- ggplot(size_summary, aes(x = size, y = mean_iop * 100)) +
    geom_ribbon(aes(ymin = min_iop * 100, ymax = max_iop * 100),
                alpha = 0.3, fill = "#0072B2") +
    geom_line(linewidth = 1.2, color = "#0072B2") +
    geom_point(size = 3, color = "#0072B2") +
    geom_text(aes(label = paste0(round(mean_iop * 100, 1), "%")),
              vjust = -1, size = 3) +
    scale_x_continuous(breaks = 0:max(size_summary$size)) +
    scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.15))) +
    labs(
      title = "IOp as Function of Number of Circumstances",
      subtitle = "Shows diminishing returns to adding circumstances (lower bound property)",
      x = "Number of Circumstances",
      y = "IOp Share (%)",
      caption = "Shaded area shows range across all subsets of each size"
    ) +
    theme_minimal() +
    theme(plot.title = element_text(face = "bold"))

  ggsave(
    get_path(config$paths$figures, paste0(filename, ".png")),
    p, width = 10, height = 6, dpi = 300
  )

  log_msg("Saved plot: ", filename, ".png")

  return(p)
}

# ============================================================================
# 6. Compare with SHAP
# ============================================================================

#' Compare Shapley IOp decomposition with SHAP importance
#' @param shapley_result Result from shapley_iop_decomposition
#' @param shap_file Path to SHAP importance CSV
#' @return Comparison table and plot
compare_shapley_vs_shap <- function(shapley_result, shap_file = NULL) {

  if (is.null(shap_file)) {
    shap_file <- get_path(config$paths$tables, "shap_importance.csv")
  }

  if (!file.exists(shap_file)) {
    log_msg("SHAP file not found: ", shap_file)
    return(NULL)
  }

  shap_data <- read_csv(shap_file, show_col_types = FALSE)

  # Standardize names for joining
  shapley_df <- shapley_result$results %>%
    select(circumstance, shapley_pct) %>%
    rename(variable = circumstance)

  # Try to match variable names
  comparison <- shap_data %>%
    left_join(shapley_df, by = c("feature" = "variable")) %>%
    filter(!is.na(shapley_pct)) %>%
    mutate(
      shap_pct = importance_pct,
      diff_pct = shapley_pct - shap_pct
    ) %>%
    select(feature, shap_pct, shapley_pct, diff_pct) %>%
    arrange(desc(shapley_pct))

  if (nrow(comparison) > 0) {
    log_msg("\n=== Comparison: Shapley IOp vs SHAP ===")
    log_msg("Note: These measure DIFFERENT things!")
    log_msg("  - Shapley IOp: Contribution to aggregate inequality")
    log_msg("  - SHAP: Feature importance for individual predictions")

    print(comparison)

    # Correlation
    cor_val <- cor(comparison$shap_pct, comparison$shapley_pct, use = "complete.obs")
    log_msg("\nCorrelation between methods: ", round(cor_val, 3))
  }

  return(comparison)
}

# ============================================================================
# 7. Main Execution
# ============================================================================

#' Run complete Shapley decomposition analysis
#' @param df Data frame (optional)
#' @param outcome Outcome variable
#' @param circumstance_set Name of circumstance set to use
#' @return Shapley decomposition results
run_shapley_analysis <- function(df = NULL,
                                  outcome = "ingc_pc",
                                  circumstance_set = "standard") {

  # Load data if not provided
  if (is.null(df)) {
    df <- readRDS(get_path(config$paths$data_processed, "entrevistado_clean.rds"))
  }

  # Get circumstances from predefined sets
  circumstances <- switch(circumstance_set,
    "minimal" = c("educp", "educm", "sexo", "indigenous", "region_14"),
    "standard" = c("educp", "educm", "clasep", "sexo", "indigenous",
                   "skin_tone", "region_14", "cohorte", "rural_14"),
    "standard_no_cohorte" = c("educp", "educm", "clasep", "sexo", "indigenous",
                              "skin_tone", "region_14", "rural_14"),
    stop("Unknown circumstance set: ", circumstance_set)
  )

  log_msg("\n")
  log_msg("Running Shapley decomposition with '", circumstance_set, "' set")
  log_msg("Circumstances: ", paste(circumstances, collapse = ", "))

  # Run Shapley decomposition
  shapley_result <- shapley_iop_decomposition(
    df = df,
    outcome = outcome,
    circumstances = circumstances,
    metric = "gini",
    verbose = TRUE
  )

  # Create visualizations
  p1 <- plot_shapley_decomposition(shapley_result)
  p2 <- plot_iop_by_subset_size(shapley_result)

  # Save results
  save_table(shapley_result$results, paste0("shapley_decomposition_", circumstance_set))
  save_table(shapley_result$subset_iops, paste0("shapley_all_subsets_", circumstance_set))

  # Compare with SHAP if available
  shap_comparison <- compare_shapley_vs_shap(shapley_result)
  if (!is.null(shap_comparison)) {
    save_table(shap_comparison, "shapley_vs_shap_comparison")
  }

  log_msg("\nShapley analysis complete")
  log_msg("Results saved to: shapley_decomposition_", circumstance_set, ".csv")

  return(list(
    shapley = shapley_result,
    shap_comparison = shap_comparison,
    plots = list(decomposition = p1, subset_size = p2)
  ))
}

# ============================================================================
# Run analysis (uncomment to execute)
# ============================================================================

# shapley_results <- run_shapley_analysis(circumstance_set = "standard")

log_msg("08_shapley_decomposition.R loaded")
log_msg("Available functions:")
log_msg("  - run_shapley_analysis(df, outcome, circumstance_set)")
log_msg("  - shapley_iop_decomposition(df, outcome, circumstances, metric)")
log_msg("  - plot_shapley_decomposition(shapley_result)")
log_msg("  - compare_shapley_vs_shap(shapley_result)")
log_msg("")
log_msg("WARNING: Shapley decomposition is computationally expensive!")
log_msg("  K=9 (standard): 512 models")
log_msg("  K=14 (maximum): 16,384 models")

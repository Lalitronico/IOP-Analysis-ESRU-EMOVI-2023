# ============================================================================
# run_sensitivity.R - Execute Sensitivity Analysis
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

#' Calculate Gini coefficient (simple implementation)
calc_gini <- function(x) {
  x <- sort(x[x > 0 & is.finite(x)])
  n <- length(x)
  if (n < 2) return(NA)
  g <- sum((2 * seq_len(n) - n - 1) * x) / (n * sum(x))
  return(g)
}

#' Calculate IOp share using between-group inequality
calculate_iop_share <- function(y, y_hat, weights = NULL, metric = "gini") {
  valid <- !is.na(y) & !is.na(y_hat) & is.finite(y) & is.finite(y_hat)
  y <- y[valid]
  y_hat <- y_hat[valid]
  if (!is.null(weights)) weights <- weights[valid]

  if (length(y) < 100) {
    return(list(iop_share = NA_real_, ineq_total = NA_real_, ineq_between = NA_real_))
  }

  tryCatch({
    if (metric == "gini") {
      y_orig <- exp(y)
      y_hat_orig <- exp(y_hat)

      ineq_total <- calc_gini(y_orig)
      ineq_between <- calc_gini(y_hat_orig)
    } else if (metric == "mld") {
      y_orig <- y
      y_hat_orig <- y_hat
      mu <- mean(y_orig, na.rm = TRUE)
      ineq_total <- mean(log(mu / y_orig), na.rm = TRUE)
      mu_hat <- mean(y_hat_orig, na.rm = TRUE)
      ineq_between <- mean(log(mu_hat / y_hat_orig), na.rm = TRUE)
    }

    iop_share <- ineq_between / ineq_total
    return(list(iop_share = iop_share, ineq_total = ineq_total, ineq_between = ineq_between))
  }, error = function(e) {
    return(list(iop_share = NA_real_, ineq_total = NA_real_, ineq_between = NA_real_))
  })
}

calculate_iop_rsq <- function(y, y_hat, weights = NULL) {
  valid <- !is.na(y) & !is.na(y_hat)
  y <- y[valid]
  y_hat <- y_hat[valid]
  ss_res <- sum((y - y_hat)^2)
  ss_tot <- sum((y - mean(y))^2)
  r2 <- 1 - ss_res / ss_tot
  return(max(0, r2))
}

log_msg("Starting sensitivity analysis")

# ============================================================================
# Define Circumstance Sets (using ACTUAL variable names)
# ============================================================================

CIRCUMSTANCE_SETS <- list(
  minimal = c(
    "educp", "educm", "sexo", "p111", "region_14"
  ),
  standard = c(
    "educp", "educm", "clasep",
    "sexo", "p111", "p112",
    "region_14", "cohorte", "p21"
  ),
  extended_household = c(
    "educp", "educm", "clasep",
    "sexo", "p111", "p112",
    "region_14", "cohorte", "p21",
    "household_economic_index", "crowding_index"
  ),
  extended_neighborhood = c(
    "educp", "educm", "clasep",
    "sexo", "p111", "p112",
    "region_14", "cohorte", "p21",
    "neighborhood_index"
  ),
  extended_cultural = c(
    "educp", "educm", "clasep",
    "sexo", "p111", "p112",
    "region_14", "cohorte", "p21",
    "cultural_capital_index"
  ),
  maximum = c(
    "educp", "educm", "clasep",
    "sexo", "p111", "p112",
    "region_14", "cohorte", "p21",
    "household_economic_index", "neighborhood_index",
    "cultural_capital_index", "crowding_index",
    "financial_inclusion_index"
  )
)

# ============================================================================
# Load and Prepare Data
# ============================================================================

df <- readRDS(get_path(config$paths$data_processed, "entrevistado_clean.rds"))
log_msg("Loaded data: ", nrow(df), " observations")

# Create log income variable
df$ln_ingc_pc <- log(as.numeric(df$ingc_pc))
df$ln_ingc_pc[!is.finite(df$ln_ingc_pc)] <- NA
log_msg("Created ln_ingc_pc: ", sum(!is.na(df$ln_ingc_pc)), " valid obs")

outcome <- "ln_ingc_pc"

# ============================================================================
# Run Analysis for Each Set
# ============================================================================

results <- list()

for (set_name in names(CIRCUMSTANCE_SETS)) {
  log_msg("\n--- Running: ", set_name, " ---")

  circumstances <- CIRCUMSTANCE_SETS[[set_name]]

  # Check available variables
  available <- circumstances[circumstances %in% names(df)]
  missing <- circumstances[!circumstances %in% names(df)]

  if (length(missing) > 0) {
    log_msg("  Missing: ", paste(missing, collapse = ", "))
  }

  log_msg("  Variables: ", length(available))

  # Prepare data - convert factors and characters to numeric for ctree
  vars_needed <- c(outcome, available)
  df_analysis <- df %>%
    select(any_of(vars_needed)) %>%
    mutate(across(where(is.character), ~as.numeric(as.factor(.)))) %>%
    mutate(across(where(is.factor), ~as.numeric(.))) %>%
    drop_na()

  log_msg("  Sample size: ", nrow(df_analysis))

  if (nrow(df_analysis) < 500) {
    log_msg("  Skipping: Sample too small")
    next
  }

  # Create formula and fit ctree
  formula <- as.formula(paste(outcome, "~", paste(available, collapse = " + ")))

  ctrl <- partykit::ctree_control(
    mincriterion = 0.95,
    minsplit = 100,
    minbucket = 50,
    maxdepth = 6
  )

  model <- tryCatch(
    partykit::ctree(formula, data = df_analysis, control = ctrl),
    error = function(e) {
      log_msg("  Error: ", e$message)
      return(NULL)
    }
  )

  if (is.null(model)) next

  # Get predictions
  type_means <- predict(model, type = "response")
  types <- predict(model, type = "node")
  y <- df_analysis[[outcome]]

  # Calculate IOp metrics
  iop_gini <- calculate_iop_share(y, type_means, metric = "gini")
  iop_mld <- calculate_iop_share(y, type_means, metric = "mld")
  iop_rsq <- calculate_iop_rsq(y, type_means)

  # Safely extract values
  iop_gini_val <- if (is.list(iop_gini)) iop_gini$iop_share else NA_real_
  iop_mld_val <- if (is.list(iop_mld)) iop_mld$iop_share else NA_real_
  gini_total_val <- if (is.list(iop_gini)) iop_gini$ineq_total else NA_real_

  results[[set_name]] <- tibble(
    circumstance_set = set_name,
    n_circumstances = length(available),
    n_types = length(unique(types)),
    n_obs = nrow(df_analysis),
    iop_gini = iop_gini_val,
    iop_mld = iop_mld_val,
    iop_rsq = iop_rsq,
    gini_total = gini_total_val
  )

  log_msg("  IOp (Gini): ", round(iop_gini_val * 100, 1), "%")
  log_msg("  IOp (R²):   ", round(iop_rsq * 100, 1), "%")
  log_msg("  Types:      ", length(unique(types)))
}

# ============================================================================
# Combine and Display Results
# ============================================================================

comparison <- bind_rows(results)

cat("\n")
cat("========================================================================\n")
cat("  SENSITIVITY ANALYSIS: IOp by Circumstance Specification\n")
cat("========================================================================\n\n")

# Format for display
comparison_display <- comparison %>%
  arrange(n_circumstances) %>%
  mutate(
    `IOp (Gini)` = paste0(round(iop_gini * 100, 1), "%"),
    `IOp (MLD)` = paste0(round(iop_mld * 100, 1), "%"),
    `IOp (R²)` = paste0(round(iop_rsq * 100, 1), "%"),
    `Gini Total` = round(gini_total, 3)
  ) %>%
  select(circumstance_set, n_circumstances, n_types, n_obs,
         `IOp (Gini)`, `IOp (MLD)`, `IOp (R²)`, `Gini Total`)

print(as.data.frame(comparison_display), row.names = FALSE)

# Save results
write_csv(comparison, get_path(config$paths$tables, "sensitivity_new_indices.csv"))
log_msg("\nResults saved to: outputs/tables/sensitivity_new_indices.csv")

# Summary
cat("\n")
cat("========================================================================\n")
cat("  KEY FINDINGS\n")
cat("========================================================================\n")

standard_iop <- comparison$iop_gini[comparison$circumstance_set == "standard"]
maximum_iop <- comparison$iop_gini[comparison$circumstance_set == "maximum"]
delta <- maximum_iop - standard_iop

cat("\n  IOp Range (Gini-based):\n")
cat("    Minimum (", comparison$circumstance_set[which.min(comparison$iop_gini)], "): ",
    round(min(comparison$iop_gini) * 100, 1), "%\n", sep = "")
cat("    Maximum (", comparison$circumstance_set[which.max(comparison$iop_gini)], "): ",
    round(max(comparison$iop_gini) * 100, 1), "%\n", sep = "")

cat("\n  Impact of New Indices:\n")
cat("    Standard specification:  ", round(standard_iop * 100, 1), "%\n", sep = "")
cat("    Maximum specification:   ", round(maximum_iop * 100, 1), "%\n", sep = "")
cat("    Delta (new indices):    +", round(delta * 100, 1), " pp\n", sep = "")

cat("\n  Interpretation:\n")
cat("    The new indices capture an additional ", round(delta * 100, 1),
    " percentage points\n", sep = "")
cat("    of inequality attributable to circumstances.\n")
cat("\n========================================================================\n")

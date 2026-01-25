# ============================================================================
# 07_simple_sensitivity.R - Simplified Sensitivity Analysis
# ============================================================================
# Standalone script that doesn't depend on other project files
# ============================================================================

library(tidyverse)
library(haven)
library(partykit)

# ----------------------------------------------------------------------------
# Helper Functions
# ----------------------------------------------------------------------------

# Simple Gini calculation
calc_gini <- function(x) {
  x <- x[!is.na(x) & x > 0]
  n <- length(x)
  if (n == 0) return(NA)
  x <- sort(x)
  G <- sum((2 * seq_along(x) - n - 1) * x)
  G / (n * sum(x))
}

# IOp share calculation
calc_iop <- function(y, y_hat) {
  gini_total <- calc_gini(exp(y))  # Back to original scale
  gini_between <- calc_gini(exp(y_hat))
  rsq <- var(y_hat) / var(y)

  list(
    iop_gini = gini_between / gini_total,
    iop_rsq = rsq,
    gini_total = gini_total
  )
}

# ----------------------------------------------------------------------------
# Main Analysis Function
# ----------------------------------------------------------------------------

run_simple_sensitivity <- function(df) {

  cat("\n========================================\n")
  cat("SENSITIVITY ANALYSIS - IOp Estimates\n")
  cat("========================================\n\n")

  # Define circumstance sets
  sets <- list(
    minimal = c("educp", "educm", "sexo", "region_14"),
    standard = c("educp", "educm", "clasep", "sexo", "region_14", "cohorte", "p21"),
    with_ethnicity = c("educp", "educm", "clasep", "sexo", "region_14", "cohorte", "p21", "p111", "p112")
  )

  results <- list()

  for (set_name in names(sets)) {
    cat("--- ", set_name, " ---\n")

    vars <- sets[[set_name]]
    available <- vars[vars %in% names(df)]

    # Prepare data
    df_sub <- df %>%
      select(ln_ingc_pc, all_of(available)) %>%
      drop_na()

    cat("  Variables: ", length(available), "\n")
    cat("  Sample: ", nrow(df_sub), "\n")

    if (nrow(df_sub) < 500) {
      cat("  Skipped: too few observations\n\n")
      next
    }

    # Fit ctree
    formula <- as.formula(paste("ln_ingc_pc ~", paste(available, collapse = " + ")))

    ctrl <- ctree_control(mincriterion = 0.95, minsplit = 100, maxdepth = 6)

    model <- tryCatch(
      ctree(formula, data = df_sub, control = ctrl),
      error = function(e) {
        cat("  Error: ", e$message, "\n\n")
        return(NULL)
      }
    )

    if (is.null(model)) next

    # Get predictions
    y <- df_sub$ln_ingc_pc
    y_hat <- predict(model)
    n_types <- length(unique(predict(model, type = "node")))

    # Calculate IOp
    iop <- calc_iop(y, y_hat)

    cat("  Types: ", n_types, "\n")
    cat("  IOp (Gini): ", round(iop$iop_gini * 100, 1), "%\n")
    cat("  IOp (R-sq): ", round(iop$iop_rsq * 100, 1), "%\n\n")

    results[[set_name]] <- tibble(
      set = set_name,
      n_vars = length(available),
      n_obs = nrow(df_sub),
      n_types = n_types,
      iop_gini = round(iop$iop_gini * 100, 1),
      iop_rsq = round(iop$iop_rsq * 100, 1)
    )
  }

  # Summary table
  cat("========================================\n")
  cat("SUMMARY\n")
  cat("========================================\n\n")

  summary_df <- bind_rows(results)
  print(summary_df)

  # Save results
  write_csv(summary_df, "outputs/tables/sensitivity_simple.csv")
  cat("\nResults saved to: outputs/tables/sensitivity_simple.csv\n")

  return(summary_df)
}

# ----------------------------------------------------------------------------
# Execute
# ----------------------------------------------------------------------------

cat("Loading data...\n")
df <- read_dta("data/raw/emovi/Data/entrevistado_2023.dta")

cat("Preparing data...\n")
df <- df %>%
  mutate(across(where(is.labelled), ~as.numeric(.))) %>%
  mutate(
    ln_ingc_pc = log(ingc_pc),
    # Convert p112 from PERLA letters (A-K) to numeric (1-11)
    p112 = match(p112, LETTERS[1:11])
  )

cat("Running analysis...\n\n")
results <- run_simple_sensitivity(df)

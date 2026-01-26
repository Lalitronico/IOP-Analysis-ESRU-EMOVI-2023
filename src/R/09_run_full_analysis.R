# ============================================================================
# 09_run_full_analysis.R - Execute Complete IOp Analysis Pipeline
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Run cohort analysis and Shapley decomposition, then generate report
# ============================================================================

# Load all required scripts
source(here::here("src", "R", "00_setup.R"))
source(here::here("src", "R", "05_iop_metrics.R"))
source(here::here("src", "R", "06_sensitivity_analysis.R"))
source(here::here("src", "R", "07_cohort_analysis.R"))
source(here::here("src", "R", "08_shapley_decomposition.R"))

log_msg("\n")
log_msg(paste(rep("=", 70), collapse = ""))
log_msg("COMPLETE IOp ANALYSIS PIPELINE")
log_msg(paste(rep("=", 70), collapse = ""))
log_msg("Start time: ", Sys.time())

# ============================================================================
# 1. Load Data
# ============================================================================

log_msg("\n[1/4] Loading data...")
df <- readRDS(get_path(config$paths$data_processed, "entrevistado_clean.rds"))
log_msg("  Loaded ", nrow(df), " observations, ", ncol(df), " variables")

# ============================================================================
# 2. Cohort Analysis
# ============================================================================

log_msg("\n[2/4] Running cohort analysis...")
tictoc::tic("Cohort analysis")

cohort_results <- tryCatch({
  run_cohort_analysis(df, outcome = "ingc_pc")
}, error = function(e) {
  log_msg("  ERROR in cohort analysis: ", e$message)
  NULL
})

tictoc::toc()

if (!is.null(cohort_results)) {
  log_msg("  Cohort analysis complete:")
  log_msg("    - Cohorts analyzed: ", nrow(cohort_results$cohort_results))
  log_msg("    - IOp range: ",
          round(min(cohort_results$cohort_results$iop_gini) * 100, 1), "% - ",
          round(max(cohort_results$cohort_results$iop_gini) * 100, 1), "%")
}

# ============================================================================
# 3. Shapley Decomposition
# ============================================================================

log_msg("\n[3/4] Running Shapley decomposition (standard set, K=9)...")
log_msg("  This will fit 512 models - please wait...")
tictoc::tic("Shapley decomposition")

shapley_results <- tryCatch({
  run_shapley_analysis(df, outcome = "ingc_pc", circumstance_set = "standard")
}, error = function(e) {
  log_msg("  ERROR in Shapley analysis: ", e$message)
  NULL
})

tictoc::toc()

if (!is.null(shapley_results)) {
  log_msg("  Shapley decomposition complete:")
  log_msg("    - Total IOp: ", round(shapley_results$shapley$total_iop * 100, 1), "%")
  log_msg("    - Top circumstance: ", shapley_results$shapley$results$circumstance[1],
          " (", round(shapley_results$shapley$results$shapley_pct[1], 1), "%)")
}

# ============================================================================
# 4. Compile Results Summary
# ============================================================================

log_msg("\n[4/4] Compiling results summary...")

# Create comprehensive summary
analysis_summary <- list(
  timestamp = Sys.time(),
  n_observations = nrow(df),

  # Cohort results
  cohort = if (!is.null(cohort_results)) {
    list(
      n_cohorts = nrow(cohort_results$cohort_results),
      iop_range = c(
        min = min(cohort_results$cohort_results$iop_gini),
        max = max(cohort_results$cohort_results$iop_gini)
      ),
      trend = if (!is.null(cohort_results$trends)) {
        cohort_results$trends$trends$iop_gini$direction
      } else "unknown",
      data = cohort_results$cohort_results
    )
  } else NULL,

  # Shapley results
  shapley = if (!is.null(shapley_results)) {
    list(
      total_iop = shapley_results$shapley$total_iop,
      n_circumstances = shapley_results$shapley$K,
      n_subsets = nrow(shapley_results$shapley$subset_iops),
      top3 = head(shapley_results$shapley$results, 3),
      data = shapley_results$shapley$results
    )
  } else NULL
)

# Save summary as RDS for report
saveRDS(analysis_summary, get_path(config$paths$outputs, "analysis_summary.rds"))

# ============================================================================
# 5. Print Final Summary
# ============================================================================

log_msg("\n")
log_msg(paste(rep("=", 70), collapse = ""))
log_msg("ANALYSIS COMPLETE")
log_msg(paste(rep("=", 70), collapse = ""))

log_msg("\nKey Results:")

if (!is.null(cohort_results)) {
  log_msg("\n  COHORT ANALYSIS:")
  log_msg("    - IOp is ", analysis_summary$cohort$trend, " across cohorts")
  log_msg("    - Range: ", round(analysis_summary$cohort$iop_range["min"] * 100, 1),
          "% - ", round(analysis_summary$cohort$iop_range["max"] * 100, 1), "%")
}

if (!is.null(shapley_results)) {
  log_msg("\n  SHAPLEY DECOMPOSITION (Ferreira & Gignoux method):")
  log_msg("    - Total IOp: ", round(analysis_summary$shapley$total_iop * 100, 1), "%")
  log_msg("    - Top 3 circumstances:")
  for (i in 1:3) {
    row <- analysis_summary$shapley$top3[i, ]
    log_msg("      ", i, ". ", row$circumstance, ": ",
            round(row$shapley_pct, 1), "%")
  }
}

log_msg("\nOutput Files:")
log_msg("  - outputs/tables/cohort_iop_results.csv")
log_msg("  - outputs/tables/cohort_trend_summary.csv")
log_msg("  - outputs/tables/shapley_decomposition_standard.csv")
log_msg("  - outputs/tables/shapley_all_subsets_standard.csv")
log_msg("  - outputs/figures/cohort_iop_trends.png")
log_msg("  - outputs/figures/cohort_decomposition.png")
log_msg("  - outputs/figures/shapley_decomposition.png")
log_msg("  - outputs/figures/iop_by_subset_size.png")
log_msg("  - outputs/analysis_summary.rds")

log_msg("\nEnd time: ", Sys.time())
log_msg(paste(rep("=", 70), collapse = ""))

# Return results for further use
list(
  cohort = cohort_results,
  shapley = shapley_results,
  summary = analysis_summary
)

# ============================================================================
# 01_load_validate.R - Load and Validate EMOVI Data
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Import EMOVI datasets, validate structure, check missingness
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

log_msg("Starting data loading and validation")

# ============================================================================
# 1. Load Main Datasets
# ============================================================================

tic("Loading datasets")

# Load individual-level data (main respondent file)
entrevistado_raw <- haven::read_dta(
  get_path(config$data_files$main$entrevistado)
)
log_msg("Loaded entrevistado_2023: ", nrow(entrevistado_raw), " observations, ",
        ncol(entrevistado_raw), " variables")

# Load household-level data
hogar_raw <- haven::read_dta(
  get_path(config$data_files$main$hogar)
)
log_msg("Loaded hogar_2023: ", nrow(hogar_raw), " observations, ",
        ncol(hogar_raw), " variables")

# Load income data (2017 - may be used for comparison)
ingreso_raw <- haven::read_dta(
  get_path(config$data_files$main$ingreso)
)
log_msg("Loaded ingreso_2017: ", nrow(ingreso_raw), " observations, ",
        ncol(ingreso_raw), " variables")

# Load financial inclusion module
inclusion_raw <- haven::read_dta(
  get_path(config$data_files$financial_inclusion)
)
log_msg("Loaded inclusion_financiera: ", nrow(inclusion_raw), " observations, ",
        ncol(inclusion_raw), " variables")

toc()

# ============================================================================
# 2. Load Data Dictionary
# ============================================================================

log_msg("Loading data dictionary")

# Read all sheets from the Excel dictionary
dictionary_path <- get_path(config$data_files$dictionary)
dictionary_sheets <- readxl::excel_sheets(dictionary_path)

log_msg("Dictionary sheets: ", paste(dictionary_sheets, collapse = ", "))

# Load each sheet into a list
dictionary <- lapply(dictionary_sheets, function(sheet) {
  readxl::read_excel(dictionary_path, sheet = sheet)
})
names(dictionary) <- dictionary_sheets

# ============================================================================
# 3. Initial Data Exploration
# ============================================================================

#' Summarize dataset structure
#' @param df data frame
#' @param name dataset name
summarize_dataset <- function(df, name) {
  cat("\n", paste(rep("=", 60), collapse = ""), "\n")
  cat("Dataset:", name, "\n")
  cat(paste(rep("=", 60), collapse = ""), "\n")
  cat("Observations:", nrow(df), "\n")
  cat("Variables:", ncol(df), "\n")

  # Variable types
  var_types <- sapply(df, class) %>%
    sapply(function(x) x[1]) %>%
    table()
  cat("\nVariable types:\n")
  print(var_types)

  # Missingness summary
  missing_pct <- sapply(df, function(x) mean(is.na(x)) * 100)
  cat("\nMissingness summary:\n")
  cat("  Variables with no missing:", sum(missing_pct == 0), "\n")
  cat("  Variables with <5% missing:", sum(missing_pct > 0 & missing_pct < 5), "\n")
  cat("  Variables with 5-20% missing:", sum(missing_pct >= 5 & missing_pct < 20), "\n")
  cat("  Variables with >20% missing:", sum(missing_pct >= 20), "\n")

  # Show most problematic variables
  if (any(missing_pct > 20)) {
    cat("\nVariables with >20% missing:\n")
    high_missing <- sort(missing_pct[missing_pct > 20], decreasing = TRUE)
    print(head(high_missing, 10))
  }

  invisible(NULL)
}

# Summarize each dataset
summarize_dataset(entrevistado_raw, "Entrevistado 2023")
summarize_dataset(hogar_raw, "Hogar 2023")
summarize_dataset(inclusion_raw, "Inclusion Financiera")

# ============================================================================
# 4. Variable Name Exploration
# ============================================================================

#' Search for variables matching a pattern
#' @param df data frame
#' @param pattern regex pattern
#' @return matching variable names with labels
search_vars <- function(df, pattern) {
  # Get variable names
  var_names <- names(df)
  matching <- grep(pattern, var_names, value = TRUE, ignore.case = TRUE)

  # Get labels if available
  result <- tibble(
    variable = matching,
    label = sapply(matching, function(v) {
      lbl <- attr(df[[v]], "label")
      if (is.null(lbl)) "" else lbl
    })
  )

  return(result)
}

# Search for potential outcome variables
log_msg("\nSearching for potential outcome variables...")

# Income-related
income_vars <- search_vars(entrevistado_raw, "ingreso|decil|quintil|salary|sueldo")
if (nrow(income_vars) > 0) {
  cat("\nPotential income variables:\n")
  print(income_vars, n = 20)
}

# Education-related
educ_vars <- search_vars(entrevistado_raw, "educ|escolar|estudi|school")
if (nrow(educ_vars) > 0) {
  cat("\nPotential education variables:\n")
  print(educ_vars, n = 20)
}

# Search for circumstance variables
log_msg("\nSearching for potential circumstance variables...")

# Parental variables
parent_vars <- search_vars(entrevistado_raw, "padre|madre|papa|mama|parent")
if (nrow(parent_vars) > 0) {
  cat("\nPotential parental variables:\n")
  print(parent_vars, n = 30)
}

# Variables at age 14
age14_vars <- search_vars(entrevistado_raw, "14|catorce")
if (nrow(age14_vars) > 0) {
  cat("\nPotential 'at age 14' variables:\n")
  print(age14_vars, n = 30)
}

# Demographics
demo_vars <- search_vars(entrevistado_raw, "sexo|sex|genero|etni|indigen|region|nac")
if (nrow(demo_vars) > 0) {
  cat("\nPotential demographic variables:\n")
  print(demo_vars, n = 20)
}

# ============================================================================
# 5. Data Quality Checks
# ============================================================================

#' Run data quality checks
#' @param df data frame
#' @param name dataset name
#' @return list of check results
run_quality_checks <- function(df, name) {
  checks <- list()

  # Check 1: Duplicate rows
  n_dups <- sum(duplicated(df))
  checks$duplicates <- list(
    passed = n_dups == 0,
    message = glue("{n_dups} duplicate rows found")
  )

  # Check 2: All-NA columns
  all_na_cols <- names(df)[sapply(df, function(x) all(is.na(x)))]
  checks$all_na_columns <- list(
    passed = length(all_na_cols) == 0,
    message = glue("{length(all_na_cols)} columns are all NA: {paste(all_na_cols, collapse=', ')}")
  )

  # Check 3: Constant columns
  constant_cols <- names(df)[sapply(df, function(x) {
    x <- x[!is.na(x)]
    length(unique(x)) <= 1
  })]
  checks$constant_columns <- list(
    passed = length(constant_cols) == 0,
    message = glue("{length(constant_cols)} constant columns: {paste(constant_cols, collapse=', ')}")
  )

  # Check 4: Expected sample size (EMOVI 2023 should have ~17,843 obs)
  expected_n <- 17843
  tolerance <- 0.05
  checks$sample_size <- list(
    passed = abs(nrow(df) - expected_n) / expected_n < tolerance,
    message = glue("Sample size: {nrow(df)} (expected ~{expected_n})")
  )

  # Print results
  cat("\n", paste(rep("-", 50), collapse = ""), "\n")
  cat("Quality checks for:", name, "\n")
  cat(paste(rep("-", 50), collapse = ""), "\n")

  for (check_name in names(checks)) {
    status <- if (checks[[check_name]]$passed) "[PASS]" else "[WARN]"
    cat(status, check_name, ":", checks[[check_name]]$message, "\n")
  }

  return(checks)
}

# Run quality checks
checks_entrevistado <- run_quality_checks(entrevistado_raw, "Entrevistado 2023")
checks_hogar <- run_quality_checks(hogar_raw, "Hogar 2023")

# ============================================================================
# 6. Save Validated Raw Data
# ============================================================================

# Save as RDS for faster subsequent loading
log_msg("Saving validated raw data as RDS")

saveRDS(entrevistado_raw, get_path(config$paths$data_processed, "entrevistado_raw.rds"))
saveRDS(hogar_raw, get_path(config$paths$data_processed, "hogar_raw.rds"))
saveRDS(inclusion_raw, get_path(config$paths$data_processed, "inclusion_raw.rds"))
saveRDS(dictionary, get_path(config$paths$data_processed, "dictionary.rds"))

# ============================================================================
# 7. Create Variable Inventory
# ============================================================================

#' Create variable inventory for a dataset
#' @param df data frame
#' @return tibble with variable info
create_var_inventory <- function(df) {
  tibble(
    variable = names(df),
    label = sapply(names(df), function(v) {
      lbl <- attr(df[[v]], "label")
      if (is.null(lbl)) NA_character_ else lbl
    }),
    type = sapply(df, function(x) class(x)[1]),
    n_unique = sapply(df, function(x) length(unique(x[!is.na(x)]))),
    pct_missing = sapply(df, function(x) round(mean(is.na(x)) * 100, 2)),
    example_values = sapply(df, function(x) {
      vals <- unique(x[!is.na(x)])[1:min(3, length(unique(x[!is.na(x)])))]
      paste(vals, collapse = ", ")
    })
  )
}

# Create and save inventories
inventory_entrevistado <- create_var_inventory(entrevistado_raw)
inventory_hogar <- create_var_inventory(hogar_raw)
inventory_inclusion <- create_var_inventory(inclusion_raw)

save_table(inventory_entrevistado, "variable_inventory_entrevistado")
save_table(inventory_hogar, "variable_inventory_hogar")
save_table(inventory_inclusion, "variable_inventory_inclusion")

# ============================================================================
# 8. Summary Output
# ============================================================================

log_msg("Data loading and validation complete")
log_msg("Outputs saved to: ", get_path(config$paths$data_processed))
log_msg("Variable inventories saved to: ", get_path(config$paths$tables))

# Print summary
cat("\n")
cat("=" , paste(rep("=", 58), collapse = ""), "\n")
cat("SUMMARY: Data Loading and Validation\n")
cat("=" , paste(rep("=", 58), collapse = ""), "\n")
cat("Datasets loaded:\n")
cat("  - entrevistado_2023:", nrow(entrevistado_raw), "obs,", ncol(entrevistado_raw), "vars\n")
cat("  - hogar_2023:", nrow(hogar_raw), "obs,", ncol(hogar_raw), "vars\n")
cat("  - inclusion_financiera:", nrow(inclusion_raw), "obs,", ncol(inclusion_raw), "vars\n")
cat("\nNext step: Run 02_preprocess.R to prepare analysis dataset\n")
cat("=" , paste(rep("=", 58), collapse = ""), "\n")

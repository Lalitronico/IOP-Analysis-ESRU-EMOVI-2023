# ============================================================================
# 01_load_data.R - Load Raw Data from Stata Files
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Read Stata .dta files and save as RDS for faster loading
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

log_msg("Starting data loading")

# ============================================================================
# 1. Define Data Paths
# ============================================================================

data_raw_path <- get_path("data", "raw", "emovi", "Data")

# Check data files exist
expected_files <- c("entrevistado_2023.dta", "hogar_2023.dta")
for (f in expected_files) {
  fpath <- file.path(data_raw_path, f)
  if (!file.exists(fpath)) {
    stop("Required data file not found: ", fpath)
  }
}

log_msg("Data files found in: ", data_raw_path)

# ============================================================================
# 2. Load Stata Files
# ============================================================================

log_msg("Loading entrevistado_2023.dta...")
entrevistado <- haven::read_dta(file.path(data_raw_path, "entrevistado_2023.dta"))
log_msg("  Loaded: ", nrow(entrevistado), " observations, ", ncol(entrevistado), " variables")

log_msg("Loading hogar_2023.dta...")
hogar <- haven::read_dta(file.path(data_raw_path, "hogar_2023.dta"))
log_msg("  Loaded: ", nrow(hogar), " observations, ", ncol(hogar), " variables")

# Check for inclusion file (may not exist)
inclusion_path <- file.path(data_raw_path, "inclusion_2023.dta")
if (file.exists(inclusion_path)) {
  log_msg("Loading inclusion_2023.dta...")
  inclusion <- haven::read_dta(inclusion_path)
  log_msg("  Loaded: ", nrow(inclusion), " observations")
} else {
  log_msg("Note: inclusion_2023.dta not found, creating empty placeholder")
  inclusion <- tibble()
}

# ============================================================================
# 3. Save as RDS
# ============================================================================

processed_path <- get_path(config$paths$data_processed)

# Ensure directory exists
if (!dir.exists(processed_path)) {
  dir.create(processed_path, recursive = TRUE)
}

log_msg("Saving RDS files...")

saveRDS(entrevistado, file.path(processed_path, "entrevistado_raw.rds"))
log_msg("  Saved: entrevistado_raw.rds")

saveRDS(hogar, file.path(processed_path, "hogar_raw.rds"))
log_msg("  Saved: hogar_raw.rds")

saveRDS(inclusion, file.path(processed_path, "inclusion_raw.rds"))
log_msg("  Saved: inclusion_raw.rds")

log_msg("Data loading complete")
log_msg("Next step: Run 02_preprocess.R")

# ============================================================================
# generate_renv_lock.R - Generate renv.lock for Reproducibility
# ============================================================================
# Run this script to generate renv.lock file
# Usage: Rscript src/R/generate_renv_lock.R
# ============================================================================

# Check if renv is installed
if (!requireNamespace("renv", quietly = TRUE)) {
  message("Installing renv package...")
  install.packages("renv", repos = "https://cloud.r-project.org")
}

library(renv)

# Initialize renv if not already done
if (!file.exists("renv.lock")) {
  message("Initializing renv...")
  renv::init(bare = TRUE)
}

# Snapshot current packages
message("Creating renv.lock snapshot...")
renv::snapshot(prompt = FALSE)

message("Done! renv.lock created successfully.")
message("To restore this environment on another machine: renv::restore()")

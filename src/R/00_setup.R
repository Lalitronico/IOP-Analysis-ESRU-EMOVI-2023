# ============================================================================
# 00_setup.R - Load Packages, Config, and Set Seeds
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Initialize R environment for all subsequent scripts
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Package Management
# ----------------------------------------------------------------------------

# Required packages
required_packages <- c(
  # Data manipulation
  "tidyverse",
  "haven",        # Read Stata files
  "readxl",       # Read Excel files
  "yaml",         # Read YAML config
  "janitor",      # Clean variable names
  "labelled",     # Handle labelled data

  # Trees and forests
  "party",        # cforest (original)
  "partykit",     # ctree (modern)

  # Inequality metrics
  "ineq",         # Gini, Theil, etc.
  "acid",         # Advanced decomposition

  # Interpretability
  "pdp",          # Partial dependence
  "iml",          # ICE plots
  "vip",          # Variable importance

  # Survey analysis
  "survey",

  # Reporting
  "rmarkdown",
  "knitr",
  "kableExtra",
  "gt",
  "patchwork",
  "scales",

  # Utilities
  "here",
  "glue",
  "assertthat",
  "tictoc",

  # Multiple Correspondence Analysis
  "FactoMineR"   # For MCA on categorical variables
)

# Install missing packages
install_if_missing <- function(packages) {
  new_packages <- packages[!(packages %in% installed.packages()[, "Package"])]
  if (length(new_packages) > 0) {
    message("Installing missing packages: ", paste(new_packages, collapse = ", "))
    install.packages(new_packages, dependencies = TRUE)
  }
}

install_if_missing(required_packages)

# Load all packages
suppressPackageStartupMessages({
  lapply(required_packages, library, character.only = TRUE)
})

# ----------------------------------------------------------------------------
# 2. Load Configuration
# ----------------------------------------------------------------------------

# Set project root (using here package)
if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- here::here()
}

# Load main config
config <- yaml::read_yaml(file.path(PROJECT_ROOT, "config", "config.yaml"))

# Load variable roles
variable_roles <- yaml::read_yaml(file.path(PROJECT_ROOT, "config", "variable_roles.yaml"))

# ----------------------------------------------------------------------------
# 3. Set Random Seeds
# ----------------------------------------------------------------------------

set.seed(config$seeds$global)

# Store seeds for reproducibility
SEEDS <- list(
  global = config$seeds$global,
  cv = config$seeds$cv,
  bootstrap = seq(
    from = config$seeds$bootstrap_start,
    length.out = config$seeds$n_bootstrap
  )
)

# ----------------------------------------------------------------------------
# 4. Create Output Directories
# ----------------------------------------------------------------------------

# Ensure all output directories exist
output_dirs <- c(
  config$paths$figures,
  config$paths$tables,
  config$paths$models,
  config$paths$data_processed
)

for (dir_path in output_dirs) {
  full_path <- file.path(PROJECT_ROOT, dir_path)
  if (!dir.exists(full_path)) {
    dir.create(full_path, recursive = TRUE)
  }
}

# ----------------------------------------------------------------------------
# 5. Utility Functions
# ----------------------------------------------------------------------------

#' Get full path relative to project root
#' @param ... path components
#' @return full path
get_path <- function(...) {
  file.path(PROJECT_ROOT, ...)
}

#' Save figure with standard settings
#' @param plot ggplot object
#' @param filename filename (without extension)
#' @param width width in inches
#' @param height height in inches
save_figure <- function(plot, filename, width = 8, height = 6) {
  filepath <- get_path(
    config$paths$figures,
    paste0(filename, ".", config$output$figure_format)
  )
  ggsave(
    filepath,
    plot = plot,
    width = width,
    height = height,
    dpi = config$output$figure_dpi
  )
  message("Saved figure: ", filepath)
}

#' Save table to CSV
#' @param data data frame
#' @param filename filename (without extension)
save_table <- function(data, filename) {
  filepath <- get_path(
    config$paths$tables,
    paste0(filename, ".csv")
  )
  write_csv(data, filepath)
  message("Saved table: ", filepath)
}

#' Log message with timestamp
log_msg <- function(...) {
  message("[", Sys.time(), "] ", ...)
}

# ----------------------------------------------------------------------------
# 6. ggplot2 Theme
# ----------------------------------------------------------------------------

# Set default theme for all plots
theme_iop <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 14),
      plot.subtitle = element_text(color = "gray40"),
      axis.title = element_text(face = "bold"),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )
}

theme_set(theme_iop())

# Color palette for circumstances
COLORS <- list(
  parental = "#E69F00",      # Orange
  demographic = "#56B4E9",   # Sky blue
  household = "#009E73",     # Green
  financial = "#F0E442",     # Yellow
  effort = "#CC79A7"         # Pink
)

# ----------------------------------------------------------------------------
# 7. Session Info
# ----------------------------------------------------------------------------

log_msg("Setup complete")
log_msg("Project root: ", PROJECT_ROOT)
log_msg("R version: ", R.version.string)
log_msg("Loaded packages: ", paste(required_packages, collapse = ", "))

# Print session info to file for reproducibility
session_info_file <- get_path(config$paths$outputs, "session_info.txt")
if (!file.exists(session_info_file)) {
  sink(session_info_file)
  print(sessionInfo())
  sink()
}

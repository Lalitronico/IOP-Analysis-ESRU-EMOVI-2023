# ============================================================================
# data_loader.R - Data Loading Utilities
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Functions for loading and merging EMOVI datasets
# ============================================================================

#' Load all EMOVI datasets
#' @param config configuration list
#' @param project_root project root path
#' @return list with all datasets
load_emovi_datasets <- function(config, project_root) {

  datasets <- list()

  # Load main respondent file
  datasets$entrevistado <- haven::read_dta(
    file.path(project_root, config$data_files$main$entrevistado)
  )

  # Load household file
  datasets$hogar <- haven::read_dta(
    file.path(project_root, config$data_files$main$hogar)
  )

  # Load income file (2017)
  datasets$ingreso <- haven::read_dta(
    file.path(project_root, config$data_files$main$ingreso)
  )

  # Load financial inclusion module
  datasets$inclusion <- haven::read_dta(
    file.path(project_root, config$data_files$financial_inclusion)
  )

  # Print summary
  message("Loaded datasets:")
  for (name in names(datasets)) {
    message("  - ", name, ": ", nrow(datasets[[name]]), " obs, ",
            ncol(datasets[[name]]), " vars")
  }

  return(datasets)
}

#' Merge EMOVI datasets on household ID
#' @param datasets list of datasets from load_emovi_datasets
#' @param household_id name of household ID variable
#' @return merged data frame
merge_emovi_datasets <- function(datasets, household_id = "folio") {

  # Check that household ID exists in all datasets
  for (name in names(datasets)) {
    if (!household_id %in% names(datasets[[name]])) {
      warning(name, " does not have household ID variable '", household_id, "'")
    }
  }

  # Start with entrevistado (main respondent file)
  merged <- datasets$entrevistado

  # Merge with hogar if different
  if (!identical(datasets$entrevistado, datasets$hogar)) {
    # Identify variables to keep from hogar (avoid duplicates)
    hogar_vars <- setdiff(names(datasets$hogar), names(merged))
    hogar_vars <- c(household_id, hogar_vars)

    merged <- merged %>%
      left_join(
        datasets$hogar[, hogar_vars],
        by = household_id,
        suffix = c("", "_hogar")
      )
  }

  # Merge with financial inclusion
  if (household_id %in% names(datasets$inclusion)) {
    inclusion_vars <- setdiff(names(datasets$inclusion), names(merged))
    inclusion_vars <- c(household_id, inclusion_vars)

    merged <- merged %>%
      left_join(
        datasets$inclusion[, inclusion_vars],
        by = household_id,
        suffix = c("", "_inclusion")
      )
  }

  message("Merged dataset: ", nrow(merged), " observations, ",
          ncol(merged), " variables")

  return(merged)
}

#' Quick load for analysis (uses cached RDS if available)
#' @param project_root project root path
#' @param force_reload force reload from Stata files
#' @return cleaned data frame
quick_load_emovi <- function(project_root = here::here(), force_reload = FALSE) {

  rds_path <- file.path(project_root, "data/processed/entrevistado_clean.rds")

  if (file.exists(rds_path) && !force_reload) {
    message("Loading from cached RDS file")
    return(readRDS(rds_path))
  }

  message("Loading from Stata files (first load or force_reload)")

  # Load config
  config <- yaml::read_yaml(file.path(project_root, "config/config.yaml"))

  # Load all datasets
  datasets <- load_emovi_datasets(config, project_root)

  # Basic cleaning
  df <- datasets$entrevistado %>%
    janitor::clean_names() %>%
    mutate(across(where(haven::is.labelled), haven::as_factor))

  # Save for faster future loading
  saveRDS(df, rds_path)
  message("Saved cleaned data to: ", rds_path)

  return(df)
}

#' Get variable labels from Stata file
#' @param df data frame loaded with haven
#' @return tibble with variable names and labels
get_variable_labels <- function(df) {

  tibble(
    variable = names(df),
    label = sapply(names(df), function(v) {
      lbl <- attr(df[[v]], "label")
      if (is.null(lbl)) NA_character_ else lbl
    }),
    type = sapply(df, function(x) {
      if (haven::is.labelled(x)) "labelled"
      else class(x)[1]
    }),
    n_unique = sapply(df, function(x) length(unique(x[!is.na(x)])))
  )
}

#' Get value labels for a labelled variable
#' @param x labelled variable
#' @return tibble with value-label mapping
get_value_labels <- function(x) {

  if (!haven::is.labelled(x)) {
    return(NULL)
  }

  labels <- attr(x, "labels")

  tibble(
    value = labels,
    label = names(labels)
  )
}

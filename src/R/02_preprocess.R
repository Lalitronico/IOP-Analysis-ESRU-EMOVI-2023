# ============================================================================
# 02_preprocess.R - Data Preprocessing and Feature Engineering
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Recode variables, handle missing data, create indices
# ============================================================================

# Load setup
source(here::here("src", "R", "00_setup.R"))

log_msg("Starting data preprocessing")

# ============================================================================
# 1. Load Raw Data
# ============================================================================

# Load from RDS (faster than re-reading Stata files)
entrevistado <- readRDS(get_path(config$paths$data_processed, "entrevistado_raw.rds"))
hogar <- readRDS(get_path(config$paths$data_processed, "hogar_raw.rds"))
inclusion <- readRDS(get_path(config$paths$data_processed, "inclusion_raw.rds"))

log_msg("Loaded data: entrevistado (", nrow(entrevistado), " obs)")

# ============================================================================
# 2. Variable Mapping
# ============================================================================
# NOTE: Update these mappings after examining the data dictionary
# The variable names below are placeholders and need to be replaced
# with actual EMOVI 2023 variable names

# Define variable mappings (source_var -> analysis_var)
var_mapping <- list(
  # ----- OUTCOMES -----
  outcomes = list(
    # Primary outcomes - UPDATE THESE WITH ACTUAL VAR NAMES
    income_decile = "decil",           # Placeholder
    ln_income = "ingreso_hogar",       # Placeholder
    education_years = "anios_esc"      # Placeholder
  ),

  # ----- CIRCUMSTANCES -----
  # Parental
  parental = list(
    father_education = "p5_2",         # Placeholder
    mother_education = "p5_1",         # Placeholder
    father_occupation = "p6_2",        # Placeholder
    mother_occupation = "p6_1"         # Placeholder
  ),

  # Household at 14
  household_14 = list(
    n_books_14 = "p7_1",               # Placeholder
    n_siblings = "p3_1"                # Placeholder
  ),

  # Demographics
  demographic = list(
    sex = "sexo",                      # Placeholder
    birth_year = "p2_2",               # Placeholder
    ethnicity = "p9_1",                # Placeholder
    skin_tone = "p9_2",                # Placeholder
    birth_region = "region"            # Placeholder
  ),

  # Survey design
  design = list(
    weight = "factor",
    strata = "estrato",
    cluster = "upm",
    household_id = "folio"
  )
)

# ============================================================================
# 3. Select and Rename Variables
# ============================================================================

#' Safely select and rename variables
#' @param df data frame
#' @param mapping named list (new_name = old_name)
#' @return data frame with selected/renamed variables
safe_select_rename <- function(df, mapping) {
  # Check which variables exist
  existing <- names(mapping)[mapping %in% names(df)]
  missing <- names(mapping)[!mapping %in% names(df)]

  if (length(missing) > 0) {
    warning("Variables not found: ", paste(unlist(mapping[missing]), collapse = ", "))
  }

  if (length(existing) == 0) {
    stop("No variables found from mapping")
  }

  # Select and rename existing variables
  mapping_existing <- mapping[existing]
  df %>%
    select(all_of(unlist(mapping_existing))) %>%
    rename(!!!setNames(unlist(mapping_existing), names(mapping_existing)))
}

# NOTE: This section will produce warnings until variable names are updated
# Uncomment and modify once actual variable names are known

# df_analysis <- entrevistado %>%
#   safe_select_rename(c(var_mapping$outcomes,
#                        var_mapping$parental,
#                        var_mapping$household_14,
#                        var_mapping$demographic,
#                        var_mapping$design))

# ============================================================================
# 4. Variable Recoding Functions
# ============================================================================

#' Recode education to years
#' @param x education level variable
#' @return years of schooling
recode_education_years <- function(x) {
  # NOTE: Update this based on actual EMOVI coding scheme
  # Example mapping (adjust based on data dictionary):
  case_when(
    x == 1 ~ 0,    # No education
    x == 2 ~ 6,    # Primary complete
    x == 3 ~ 9,    # Secondary complete
    x == 4 ~ 12,   # High school complete
    x == 5 ~ 16,   # University complete
    x == 6 ~ 18,   # Postgraduate
    TRUE ~ NA_real_
  )
}

#' Recode birth year to cohort
#' @param birth_year year of birth
#' @return birth cohort category
recode_birth_cohort <- function(birth_year) {
  cut(birth_year,
      breaks = c(-Inf, 1959, 1969, 1979, 1989, 1999, Inf),
      labels = c("pre1960", "1960s", "1970s", "1980s", "1990s", "2000s"),
      right = TRUE)
}

#' Recode region
#' @param region region code
#' @return region name
recode_region <- function(region) {
  # NOTE: Update based on actual EMOVI regions
  case_when(
    region == 1 ~ "North",
    region == 2 ~ "Center_North",
    region == 3 ~ "Center",
    region == 4 ~ "Center_South",
    region == 5 ~ "South",
    TRUE ~ NA_character_
  )
}

#' Recode sex
#' @param sex sex code
#' @return sex label
recode_sex <- function(sex) {
  case_when(
    sex == 1 ~ "Male",
    sex == 2 ~ "Female",
    TRUE ~ NA_character_
  )
}

# ============================================================================
# 5. Index Construction Functions
# ============================================================================

#' Create wealth index using PCA
#' @param df data frame with asset variables
#' @param asset_vars vector of asset variable names
#' @return numeric vector of wealth index scores
create_wealth_index <- function(df, asset_vars) {
  # Select asset variables
  assets <- df %>% select(all_of(asset_vars))

  # Handle missing values - complete cases only for PCA
  complete_idx <- complete.cases(assets)

  if (sum(complete_idx) < 100) {
    warning("Too few complete cases for PCA: ", sum(complete_idx))
    return(rep(NA_real_, nrow(df)))
  }

  # Run PCA on complete cases
  pca <- prcomp(assets[complete_idx, ], center = TRUE, scale. = TRUE)

  # Use first principal component as wealth index
  wealth_complete <- pca$x[, 1]

  # Standardize to 0-100 scale
  wealth_complete <- (wealth_complete - min(wealth_complete)) /
    (max(wealth_complete) - min(wealth_complete)) * 100

  # Create full vector with NAs for incomplete cases
  wealth_index <- rep(NA_real_, nrow(df))
  wealth_index[complete_idx] <- wealth_complete

  return(wealth_index)
}

#' Create housing quality index
#' @param df data frame with housing variables
#' @param floor_var floor material variable
#' @param walls_var walls material variable
#' @param roof_var roof material variable
#' @return numeric housing quality index
create_housing_index <- function(df, floor_var, walls_var, roof_var) {
  # NOTE: Update scoring based on actual EMOVI categories
  # Higher = better quality

  # Example scoring (adjust based on data dictionary)
  floor_score <- case_when(
    df[[floor_var]] == 1 ~ 1,   # Dirt
    df[[floor_var]] == 2 ~ 2,   # Cement
    df[[floor_var]] == 3 ~ 3,   # Tile/wood
    TRUE ~ NA_real_
  )

  walls_score <- case_when(
    df[[walls_var]] == 1 ~ 1,   # Cardboard/waste
    df[[walls_var]] == 2 ~ 2,   # Adobe
    df[[walls_var]] == 3 ~ 3,   # Brick/concrete
    TRUE ~ NA_real_
  )

  roof_score <- case_when(
    df[[roof_var]] == 1 ~ 1,   # Cardboard/waste
    df[[roof_var]] == 2 ~ 2,   # Lamina
    df[[roof_var]] == 3 ~ 3,   # Concrete
    TRUE ~ NA_real_
  )

  # Combine into index (simple sum)
  housing_index <- floor_score + walls_score + roof_score

  # Standardize to 0-100
  housing_index <- (housing_index - min(housing_index, na.rm = TRUE)) /
    (max(housing_index, na.rm = TRUE) - min(housing_index, na.rm = TRUE)) * 100

  return(housing_index)
}

# ============================================================================
# NEW: Household Economic Index (MCA - Multiple Correspondence Analysis)
# ============================================================================
#' Create comprehensive household economic index using MCA
#' MCA is methodologically appropriate for binary/categorical variables
#' @param df data frame with asset and service variables
#' @return list with index, MCA object, and variance explained
create_household_economic_index <- function(df) {
  # Variables de bienes (binarias: 1=Sí, 2=No)
  asset_vars <- c("p31a", "p31b", "p31c", "p31d", "p31e",
                  "p31g", "p31h", "p31i", "p31k", "p31l")

  # Servicios básicos
  service_vars <- c("p26a", "p26b", "p26c", "p26d", "p26e")

  # Check which variables exist
  all_vars <- c(asset_vars, service_vars, "p25")
  available_vars <- all_vars[all_vars %in% names(df)]

  if (length(available_vars) < 5) {
    warning("Insufficient variables for household economic index")
    return(list(index = rep(NA_real_, nrow(df)), variance_explained = NA))
  }

  # Preparar data frame para MCA (variables como factores)
  df_mca <- df %>%
    select(all_of(available_vars)) %>%
    mutate(across(everything(), as.factor))

  # MCA en casos completos
  complete_idx <- complete.cases(df_mca)
  if (sum(complete_idx) < 100) {
    warning("Insuficientes casos completos para MCA: ", sum(complete_idx))
    return(list(index = rep(NA_real_, nrow(df)), variance_explained = NA))
  }

  # Ejecutar MCA con FactoMineR
  mca_result <- FactoMineR::MCA(df_mca[complete_idx, ],
                                 ncp = 2,           # Primeras 2 dimensiones
                                 graph = FALSE)     # Sin gráficos automáticos

  # Usar Dimensión 1 (típicamente captura nivel socioeconómico)
  dim1 <- mca_result$ind$coord[, 1]

  # Estandarizar a 0-100
  index <- rep(NA_real_, nrow(df))
  index[complete_idx] <- (dim1 - min(dim1)) / (max(dim1) - min(dim1)) * 100

  return(list(
    index = index,
    mca = mca_result,
    variance_explained = mca_result$eig[1, 2] / 100  # % de inercia explicada
  ))
}

# ============================================================================
# NEW: Neighborhood Quality Index (Suma ponderada)
# ============================================================================
#' Create neighborhood quality index from P33 variables
#' Captures access to public services and community amenities
#' @param df data frame with p33a-h variables
#' @return numeric vector (0-100 scale)
create_neighborhood_index <- function(df) {
  neigh_vars <- paste0("p33", letters[1:8])

  # Check which exist
  available_vars <- neigh_vars[neigh_vars %in% names(df)]
  if (length(available_vars) == 0) {
    warning("No neighborhood variables found")
    return(rep(NA_real_, nrow(df)))
  }

  # Recodificar: Sí->2, No->0, Más o menos/NS->1
  # Handle both factor labels (Spanish) and numeric codes
  recode_p33 <- function(x) {
    if (is.factor(x)) {
      x_char <- as.character(x)
      case_when(
        x_char == "Sí" ~ 2,
        x_char == "No" ~ 0,
        x_char %in% c("Más o menos", "NS") ~ NA_real_,
        TRUE ~ NA_real_
      )
    } else {
      case_when(
        x == 1 ~ 2,  # Sí
        x == 2 ~ 1,  # Más o menos
        x == 3 ~ 0,  # No
        TRUE ~ NA_real_
      )
    }
  }

  df_neigh <- df %>%
    select(all_of(available_vars)) %>%
    mutate(across(everything(), recode_p33))

  # Suma simple, estandarizar a 0-100
  max_score <- length(available_vars) * 2
  index <- rowSums(df_neigh, na.rm = FALSE) / max_score * 100

  return(index)
}

# ============================================================================
# NEW: Crowding Index (Hacinamiento)
# ============================================================================
#' Calculate household crowding (persons per bedroom)
#' @param df data frame with p22 (persons) and p24 (bedrooms)
#' @return numeric vector (persons per bedroom)
create_crowding_index <- function(df) {
  if (!all(c("p22", "p24") %in% names(df))) {
    warning("Variables p22 or p24 not found")
    return(rep(NA_real_, nrow(df)))
  }

  # Get numeric values (handle factors if present)
  p22 <- if (is.factor(df$p22)) as.numeric(as.character(df$p22)) else as.numeric(df$p22)
  p24 <- if (is.factor(df$p24)) as.numeric(as.character(df$p24)) else as.numeric(df$p24)

  # Treat extreme values (99, 999, etc.) as missing
  p22[p22 >= 50] <- NA  # Unlikely to have 50+ persons in household
  p24[p24 >= 50] <- NA  # Unlikely to have 50+ bedrooms

  # Personas por cuarto de dormir (mínimo 1 cuarto para evitar división por 0)
  crowding <- p22 / pmax(p24, 1)

  return(crowding)
}

# ============================================================================
# NEW: Financial Inclusion Index
# ============================================================================
#' Create family financial inclusion index at age 14
#' Captures access to formal financial services
#' @param df data frame with p32e, p32f, p32n variables
#' @return numeric vector (0-100 scale)
create_financial_inclusion_index <- function(df) {
  fin_vars <- c("p32e", "p32f", "p32n")

  # Check which exist
  available_vars <- fin_vars[fin_vars %in% names(df)]
  if (length(available_vars) == 0) {
    warning("No financial inclusion variables found")
    return(rep(NA_real_, nrow(df)))
  }

  # Helper to recode binary yes/no (handles factors and numeric)
  recode_yes_no <- function(x) {
    if (is.factor(x)) {
      x_char <- as.character(x)
      case_when(
        x_char == "Sí" ~ 1,
        x_char == "No" ~ 0,
        TRUE ~ NA_real_  # NS or other
      )
    } else {
      ifelse(x == 1, 1, 0)
    }
  }

  df_fin <- df %>%
    select(all_of(available_vars)) %>%
    mutate(across(everything(), recode_yes_no))

  # Suma (0-n), estandarizar a 0-100
  index <- rowSums(df_fin, na.rm = FALSE) / length(available_vars) * 100

  return(index)
}

# ============================================================================
# NEW: Cultural Capital Index
# ============================================================================
#' Create cultural/digital capital index
#' Captures access to information, digital resources, and cultural content
#' @param df data frame with p31k, p31l, p31e, p31h, p31m variables
#' @return numeric vector (0-100 scale)
create_cultural_capital_index <- function(df) {
  # Variables que capturan capital cultural/digital del hogar de origen:
  # - p31k: Computadora (acceso a conocimiento digital)
  # - p31l: Internet (conectividad global)
  # - p31e: Televisor (acceso a información/entretenimiento)
  # - p31h: TV cable (contenido diverso/educativo)
  # - p31m: DVD/Videocasetera (material audiovisual)
  cultural_vars <- c("p31k", "p31l", "p31e", "p31h", "p31m")

  # Check which exist
  available_vars <- cultural_vars[cultural_vars %in% names(df)]
  if (length(available_vars) == 0) {
    warning("No cultural capital variables found")
    return(rep(NA_real_, nrow(df)))
  }

  # Helper to recode binary yes/no (handles factors and numeric)
  recode_yes_no <- function(x) {
    if (is.factor(x)) {
      x_char <- as.character(x)
      case_when(
        x_char == "Sí" ~ 1,
        x_char == "No" ~ 0,
        TRUE ~ NA_real_  # NS or other
      )
    } else {
      ifelse(x == 1, 1, 0)
    }
  }

  df_cult <- df %>%
    select(all_of(available_vars)) %>%
    mutate(across(everything(), recode_yes_no))

  # Suma simple, estandarizar a 0-100
  index <- rowSums(df_cult, na.rm = FALSE) / length(available_vars) * 100

  return(index)
}

# ============================================================================
# 6. Missing Data Handling
# ============================================================================

#' Summarize missingness by variable category
#' @param df data frame
#' @param var_groups named list of variable vectors by category
#' @return summary tibble
summarize_missingness <- function(df, var_groups) {
  results <- map_dfr(names(var_groups), function(group_name) {
    vars <- var_groups[[group_name]]
    vars_exist <- vars[vars %in% names(df)]

    if (length(vars_exist) == 0) return(NULL)

    df %>%
      select(all_of(vars_exist)) %>%
      summarise(across(everything(), ~mean(is.na(.)) * 100)) %>%
      pivot_longer(everything(), names_to = "variable", values_to = "pct_missing") %>%
      mutate(category = group_name)
  })

  return(results)
}

#' Impute missing values using mode (categorical) or median (numeric)
#' @param df data frame
#' @param vars variables to impute
#' @return data frame with imputed values
impute_missing <- function(df, vars) {
  for (var in vars) {
    if (!var %in% names(df)) next

    x <- df[[var]]

    if (is.numeric(x)) {
      # Median imputation for numeric
      median_val <- median(x, na.rm = TRUE)
      df[[var]][is.na(x)] <- median_val
      message("Imputed ", var, " with median: ", round(median_val, 2))
    } else {
      # Mode imputation for categorical
      mode_val <- names(sort(table(x), decreasing = TRUE))[1]
      df[[var]][is.na(x)] <- mode_val
      message("Imputed ", var, " with mode: ", mode_val)
    }
  }

  return(df)
}

# ============================================================================
# 7. Main Preprocessing Pipeline
# ============================================================================

preprocess_emovi <- function(raw_data) {
  log_msg("Starting preprocessing pipeline")

  # Step 1: Clean variable names
  df <- raw_data %>%
    janitor::clean_names()

  # Step 2: Convert labelled to factors where appropriate
  df <- df %>%
    mutate(across(where(haven::is.labelled), haven::as_factor))

  # Step 3: Apply recoding (uncomment when variable names are known)
  # df <- df %>%
  #   mutate(
  #     birth_cohort = recode_birth_cohort(birth_year),
  #     region_name = recode_region(region),
  #     sex_label = recode_sex(sex)
  #   )

  # Step 4: Create indices (uncomment when asset variables are identified)
  # df <- df %>%
  #   mutate(
  #     wealth_index = create_wealth_index(., c("asset1", "asset2", ...)),
  #     housing_index = create_housing_index(., "floor", "walls", "roof")
  #   )

  # Step 5: Handle missing values
  # vars_to_impute <- c("father_education", "mother_education", ...)
  # df <- impute_missing(df, vars_to_impute)

  log_msg("Preprocessing complete")
  return(df)
}

# ============================================================================
# 8. Execute Preprocessing
# ============================================================================

# Run preprocessing (basic cleaning for now)
entrevistado_clean <- entrevistado %>%
  janitor::clean_names() %>%
  mutate(across(where(haven::is.labelled), haven::as_factor))

log_msg("Basic cleaning complete")
log_msg("Clean dataset: ", nrow(entrevistado_clean), " obs, ",
        ncol(entrevistado_clean), " vars")

# ============================================================================
# 8b. Create Circumstance Indices
# ============================================================================
log_msg("Creating circumstance indices...")

# 1. Household Economic Index (MCA)
tryCatch({
  hh_result <- create_household_economic_index(entrevistado_clean)
  entrevistado_clean$household_economic_index <- hh_result$index
  if (!is.na(hh_result$variance_explained)) {
    log_msg("  household_economic_index (MCA): inertia explained = ",
            round(hh_result$variance_explained * 100, 1), "%")
  } else {
    log_msg("  household_economic_index: could not compute (missing variables)")
  }
}, error = function(e) {
  log_msg("  household_economic_index: error - ", e$message)
})

# 2. Neighborhood Index
tryCatch({
  entrevistado_clean$neighborhood_index <- create_neighborhood_index(entrevistado_clean)
  n_valid <- sum(!is.na(entrevistado_clean$neighborhood_index))
  log_msg("  neighborhood_index created (", n_valid, " valid obs)")
}, error = function(e) {
  log_msg("  neighborhood_index: error - ", e$message)
})

# 3. Crowding Index
tryCatch({
  entrevistado_clean$crowding_index <- create_crowding_index(entrevistado_clean)
  n_valid <- sum(!is.na(entrevistado_clean$crowding_index))
  log_msg("  crowding_index created (", n_valid, " valid obs)")
}, error = function(e) {
  log_msg("  crowding_index: error - ", e$message)
})

# 4. Financial Inclusion Index
tryCatch({
  entrevistado_clean$financial_inclusion_index <- create_financial_inclusion_index(entrevistado_clean)
  n_valid <- sum(!is.na(entrevistado_clean$financial_inclusion_index))
  log_msg("  financial_inclusion_index created (", n_valid, " valid obs)")
}, error = function(e) {
  log_msg("  financial_inclusion_index: error - ", e$message)
})

# 5. Cultural Capital Index
tryCatch({
  entrevistado_clean$cultural_capital_index <- create_cultural_capital_index(entrevistado_clean)
  n_valid <- sum(!is.na(entrevistado_clean$cultural_capital_index))
  log_msg("  cultural_capital_index created (", n_valid, " valid obs)")
}, error = function(e) {
  log_msg("  cultural_capital_index: error - ", e$message)
})

log_msg("Circumstance indices creation complete")

# ============================================================================
# 9. Save Preprocessed Data
# ============================================================================

saveRDS(entrevistado_clean,
        get_path(config$paths$data_processed, "entrevistado_clean.rds"))

log_msg("Saved preprocessed data")

# ============================================================================
# 10. Export Sample for Python
# ============================================================================

# Export to CSV for Python/XGBoost analysis
# Uncomment when analysis variables are defined

# df_for_python <- entrevistado_clean %>%
#   select(all_of(c(outcome_vars, circumstance_vars, weight_var)))
#
# write_csv(df_for_python,
#           get_path(config$paths$data_processed, "emovi_for_python.csv"))

log_msg("Preprocessing script complete")
log_msg("Next step: Examine variable inventory and update variable mappings")

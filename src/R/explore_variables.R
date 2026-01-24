# ============================================================================
# explore_variables.R - Quick exploration of EMOVI 2023 variables
# ============================================================================
# Run this script to identify variable names for IOp analysis
# ============================================================================

# Load required packages
if (!require("haven")) install.packages("haven", repos = "https://cran.r-project.org")
if (!require("readxl")) install.packages("readxl", repos = "https://cran.r-project.org")
if (!require("dplyr")) install.packages("dplyr", repos = "https://cran.r-project.org")

library(haven)
library(readxl)
library(dplyr)

# Set working directory
setwd("C:/Users/HP ZBOOK/Desktop/Inequality of Opportunity")

cat("=" , rep("=", 70), "\n", sep = "")
cat("EMOVI 2023 - Variable Exploration\n")
cat("=" , rep("=", 70), "\n\n", sep = "")

# ============================================================================
# 1. Load main dataset
# ============================================================================

cat("Loading entrevistado_2023.dta...\n")
entrevistado <- haven::read_dta("data/raw/emovi/Data/entrevistado_2023.dta")
cat("Loaded:", nrow(entrevistado), "observations,", ncol(entrevistado), "variables\n\n")

# ============================================================================
# 2. Extract variable names and labels
# ============================================================================

get_var_info <- function(df) {
  data.frame(
    variable = names(df),
    label = sapply(names(df), function(v) {
      lbl <- attr(df[[v]], "label")
      if (is.null(lbl)) NA_character_ else lbl
    }),
    type = sapply(df, function(x) class(x)[1]),
    n_unique = sapply(df, function(x) length(unique(x[!is.na(x)]))),
    pct_missing = sapply(df, function(x) round(mean(is.na(x)) * 100, 1)),
    stringsAsFactors = FALSE
  )
}

var_info <- get_var_info(entrevistado)

# ============================================================================
# 3. Search for key variables
# ============================================================================

search_vars <- function(df_info, pattern, description) {
  cat("\n--- ", description, " ---\n", sep = "")
  matches <- df_info[grepl(pattern, df_info$variable, ignore.case = TRUE) |
                     grepl(pattern, df_info$label, ignore.case = TRUE), ]
  if (nrow(matches) > 0) {
    for (i in 1:min(nrow(matches), 30)) {
      cat(sprintf("  %-15s : %s (n_unique=%d, miss=%.1f%%)\n",
                  matches$variable[i],
                  substr(matches$label[i], 1, 60),
                  matches$n_unique[i],
                  matches$pct_missing[i]))
    }
  } else {
    cat("  No matches found\n")
  }
  invisible(matches)
}

# Search for different variable types
cat("\n" , rep("=", 70), "\n", sep = "")
cat("SEARCHING FOR KEY VARIABLES\n")
cat(rep("=", 70), "\n", sep = "")

# Income/outcome variables
search_vars(var_info, "ingreso|income|decil|quintil|sueldo|salario", "INCOME VARIABLES")
search_vars(var_info, "escol|educ|school|estudi|grado|nivel", "EDUCATION VARIABLES")
search_vars(var_info, "ocup|trabajo|empleo|job|work", "OCCUPATION VARIABLES")
search_vars(var_info, "riqueza|wealth|activo|asset|bien", "WEALTH/ASSETS")

# Circumstance variables
search_vars(var_info, "padre|papa|father", "FATHER VARIABLES")
search_vars(var_info, "madre|mama|mother", "MOTHER VARIABLES")
search_vars(var_info, "14|catorce", "AT AGE 14 VARIABLES")
search_vars(var_info, "sexo|sex|genero", "SEX/GENDER")
search_vars(var_info, "etni|indigen|lengua", "ETHNICITY/INDIGENOUS")
search_vars(var_info, "piel|skin|color|tono", "SKIN TONE")
search_vars(var_info, "region|estado|entidad|zona", "REGION/LOCATION")
search_vars(var_info, "nac|birth|edad|age|año", "BIRTH/AGE")
search_vars(var_info, "libro|book", "BOOKS")
search_vars(var_info, "hermano|sibling", "SIBLINGS")
search_vars(var_info, "factor|peso|weight|pond", "SURVEY WEIGHTS")

# ============================================================================
# 4. Show all variables (first 100)
# ============================================================================

cat("\n" , rep("=", 70), "\n", sep = "")
cat("ALL VARIABLES (first 100)\n")
cat(rep("=", 70), "\n", sep = "")

for (i in 1:min(100, nrow(var_info))) {
  cat(sprintf("%-15s : %s\n",
              var_info$variable[i],
              substr(var_info$label[i], 1, 65)))
}

if (nrow(var_info) > 100) {
  cat("\n... and", nrow(var_info) - 100, "more variables\n")
}

# ============================================================================
# 5. Save full variable list to CSV
# ============================================================================

write.csv(var_info, "outputs/tables/variable_inventory_full.csv", row.names = FALSE)
cat("\nFull variable inventory saved to: outputs/tables/variable_inventory_full.csv\n")

# ============================================================================
# 6. Load and explore data dictionary (Excel)
# ============================================================================

cat("\n" , rep("=", 70), "\n", sep = "")
cat("DATA DICTIONARY (Excel)\n")
cat(rep("=", 70), "\n", sep = "")

tryCatch({
  dict_sheets <- readxl::excel_sheets("data/raw/emovi/Diccionario ESRU EMOVI 2023.xlsx")
  cat("Dictionary sheets:", paste(dict_sheets, collapse = ", "), "\n\n")

  for (sheet in dict_sheets[1:min(3, length(dict_sheets))]) {
    cat("\n--- Sheet:", sheet, "---\n")
    dict_data <- readxl::read_excel("data/raw/emovi/Diccionario ESRU EMOVI 2023.xlsx",
                                     sheet = sheet, n_max = 20)
    print(head(dict_data, 10))
  }
}, error = function(e) {
  cat("Error reading dictionary:", e$message, "\n")
})

# ============================================================================
# 7. Quick look at key variables
# ============================================================================

cat("\n" , rep("=", 70), "\n", sep = "")
cat("SAMPLE VALUES FOR KEY VARIABLES\n")
cat(rep("=", 70), "\n", sep = "")

show_var <- function(df, varname) {
  if (varname %in% names(df)) {
    cat("\n", varname, ":\n", sep = "")
    x <- df[[varname]]
    if (haven::is.labelled(x)) {
      cat("  Labels:", paste(names(attr(x, "labels")), collapse = ", "), "\n")
      cat("  Values:", paste(head(unique(as.numeric(x)), 10), collapse = ", "), "\n")
    } else {
      cat("  Values:", paste(head(unique(x), 10), collapse = ", "), "\n")
    }
    cat("  Type:", class(x)[1], "\n")
  }
}

# Try to show some key variables
potential_vars <- c("p1", "p2", "p3", "p4", "p5", "sexo", "edad", "factor",
                    "ing_total", "decil", "quintil", "nse", "region")
for (v in potential_vars) {
  show_var(entrevistado, v)
}

cat("\n\nScript completed.\n")

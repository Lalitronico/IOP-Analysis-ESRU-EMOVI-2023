# Check available variables
df <- readRDS("data/processed/entrevistado_clean.rds")

cat("=== Variables de ingreso ===\n")
income_vars <- names(df)[grepl("ing|income", names(df), ignore.case = TRUE)]
print(income_vars)

cat("\n=== Variables que contienen 'ln' ===\n")
ln_vars <- names(df)[grepl("^ln|_ln", names(df), ignore.case = TRUE)]
print(ln_vars)

cat("\n=== Verificar variables de circunstancias ===\n")
circ_check <- c("educp", "educm", "clasep", "sexo", "indigenous", "p111",
                "skin_tone", "p112", "region_14", "cohorte", "rural_14", "p21")
for (v in circ_check) {
  exists <- v %in% names(df)
  cat(sprintf("  %-15s: %s\n", v, ifelse(exists, "EXISTS", "MISSING")))
}

cat("\n=== Primeras 30 variables del dataset ===\n")
print(head(names(df), 30))

cat("\n=== Variables que empiezan con 'p1' ===\n")
p1_vars <- names(df)[grepl("^p1", names(df))]
print(head(p1_vars, 20))

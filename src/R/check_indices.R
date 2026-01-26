# Quick script to check the new indices
df <- readRDS("data/processed/entrevistado_clean.rds")

cat("=== Variables p33 disponibles ===\n")
p33_vars <- names(df)[grepl("p33", names(df))]
print(p33_vars)

cat("\n=== Resumen de Nuevos Índices ===\n\n")

cat("1. household_economic_index:\n")
print(summary(df$household_economic_index))
cat("   Non-NA:", sum(!is.na(df$household_economic_index)), "\n\n")

cat("2. neighborhood_index:\n")
print(summary(df$neighborhood_index))
cat("   Non-NA:", sum(!is.na(df$neighborhood_index)), "\n\n")

cat("3. crowding_index:\n")
print(summary(df$crowding_index))
cat("   Non-NA:", sum(!is.na(df$crowding_index)), "\n\n")

cat("4. financial_inclusion_index:\n")
print(summary(df$financial_inclusion_index))
cat("   Non-NA:", sum(!is.na(df$financial_inclusion_index)), "\n\n")

cat("5. cultural_capital_index:\n")
print(summary(df$cultural_capital_index))
cat("   Non-NA:", sum(!is.na(df$cultural_capital_index)), "\n\n")

# Check why neighborhood_index might be all NA
cat("=== Diagnóstico neighborhood_index ===\n")
if (length(p33_vars) == 0) {
  cat("PROBLEMA: No hay variables p33 en el dataset\n")
} else {
  cat("Muestra de", p33_vars[1], ":\n")
  print(table(df[[p33_vars[1]]], useNA = "ifany"))
}

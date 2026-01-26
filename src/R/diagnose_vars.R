# Diagnose variable types
df <- readRDS("data/processed/entrevistado_clean.rds")

cat("=== Tipo de variables p33a ===\n")
print(class(df$p33a))
cat("Valores únicos:\n")
print(unique(df$p33a))

cat("\n=== Tipo de variables p31k (computadora) ===\n")
print(class(df$p31k))
print(table(df$p31k, useNA = "ifany"))

cat("\n=== Tipo de variables p32e (cuenta ahorro) ===\n")
print(class(df$p32e))
print(table(df$p32e, useNA = "ifany"))

cat("\n=== Verificar si el problema es que son factores ===\n")
cat("p33a es factor:", is.factor(df$p33a), "\n")
cat("p31k es factor:", is.factor(df$p31k), "\n")

# Test conversion
cat("\n=== Test: p33a como numeric ===\n")
test <- as.numeric(df$p33a)
print(table(test, useNA = "ifany"))

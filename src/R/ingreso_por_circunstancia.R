# ==============================================================================
# ingreso_por_circunstancia.R - Ingreso promedio por cada circunstancia
# ==============================================================================

# Asegurarse de que los datos estén cargados
if (!exists("df_analysis")) {
  stop("Primero ejecuta: source('src/R/visualize_trees.R')")
}

library(dplyr)
library(knitr)

cat("\n")
cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║     INGRESO PROMEDIO POR CIRCUNSTANCIA - EMOVI 2023              ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n")

# Calcular ingreso en pesos (no en logaritmo)
df_analysis$ingreso_pesos <- exp(df_analysis$ln_income)

# ==============================================================================
# 1. EDUCACIÓN DE LA MADRE
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("1. EDUCACIÓN DE LA MADRE (educm)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

educm_tabla <- df_analysis %>%
  group_by(educm) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1),
    vs_Base = round((Ingreso_Promedio / first(Ingreso_Promedio) - 1) * 100, 0)
  )

print(educm_tabla)

# ==============================================================================
# 2. EDUCACIÓN DEL PADRE
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("2. EDUCACIÓN DEL PADRE (educp)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

educp_tabla <- df_analysis %>%
  group_by(educp) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1),
    vs_Base = round((Ingreso_Promedio / first(Ingreso_Promedio) - 1) * 100, 0)
  )

print(educp_tabla)

# ==============================================================================
# 3. SEXO
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("3. SEXO\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

sexo_tabla <- df_analysis %>%
  group_by(sexo) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1),
    Brecha = round((Ingreso_Promedio / max(Ingreso_Promedio) - 1) * 100, 0)
  )

print(sexo_tabla)

brecha_genero <- sexo_tabla$Ingreso_Promedio[sexo_tabla$sexo == "Hombre"] -
                 sexo_tabla$Ingreso_Promedio[sexo_tabla$sexo == "Mujer"]
cat("\n  → Brecha de género: $", format(brecha_genero, big.mark = ","), " pesos menos para mujeres\n", sep = "")

# ==============================================================================
# 4. REGIÓN A LOS 14 AÑOS
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("4. REGIÓN A LOS 14 AÑOS (region_14)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

region_tabla <- df_analysis %>%
  group_by(region_14) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1)
  ) %>%
  arrange(desc(Ingreso_Promedio))

print(region_tabla)

# ==============================================================================
# 5. RURAL / URBANO A LOS 14 AÑOS
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("5. RURAL / URBANO A LOS 14 AÑOS (p21)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

rural_tabla <- df_analysis %>%
  group_by(p21) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1)
  ) %>%
  arrange(desc(Ingreso_Promedio))

print(rural_tabla)

# ==============================================================================
# 6. OCUPACIÓN DEL PADRE
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("6. OCUPACIÓN DEL PADRE (clasep)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

clasep_tabla <- df_analysis %>%
  group_by(clasep) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1)
  ) %>%
  arrange(desc(Ingreso_Promedio))

print(clasep_tabla)

# ==============================================================================
# 7. COHORTE DE NACIMIENTO
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("7. COHORTE DE NACIMIENTO\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

cohorte_tabla <- df_analysis %>%
  group_by(cohorte) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1)
  )

print(cohorte_tabla)

# ==============================================================================
# 8. HABLA LENGUA INDÍGENA
# ==============================================================================
cat("\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
cat("8. HABLA LENGUA INDÍGENA (p111)\n")
cat("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

indigena_tabla <- df_analysis %>%
  group_by(p111) %>%
  summarise(
    N = n(),
    Ingreso_Promedio = round(mean(ingreso_pesos), 0),
    .groups = "drop"
  ) %>%
  mutate(
    Porcentaje = round(N / sum(N) * 100, 1)
  )

print(indigena_tabla)

# ==============================================================================
# GUARDAR TODAS LAS TABLAS EN CSV
# ==============================================================================

output_tables <- file.path(project_root, "outputs", "tables")

# Crear tabla resumen completa
todas_circunstancias <- bind_rows(
  educm_tabla %>% mutate(Circunstancia = "Educación madre", Categoria = as.character(educm)) %>% select(Circunstancia, Categoria, N, Ingreso_Promedio, Porcentaje),
  educp_tabla %>% mutate(Circunstancia = "Educación padre", Categoria = as.character(educp)) %>% select(Circunstancia, Categoria, N, Ingreso_Promedio, Porcentaje),
  sexo_tabla %>% mutate(Circunstancia = "Sexo", Categoria = as.character(sexo)) %>% select(Circunstancia, Categoria, N, Ingreso_Promedio, Porcentaje),
  region_tabla %>% mutate(Circunstancia = "Región a los 14", Categoria = as.character(region_14)) %>% select(Circunstancia, Categoria, N, Ingreso_Promedio, Porcentaje),
  rural_tabla %>% mutate(Circunstancia = "Rural/Urbano", Categoria = as.character(p21)) %>% select(Circunstancia, Categoria, N, Ingreso_Promedio, Porcentaje),
  clasep_tabla %>% mutate(Circunstancia = "Ocupación padre", Categoria = as.character(clasep)) %>% select(Circunstancia, Categoria, N, Ingreso_Promedio, Porcentaje),
  indigena_tabla %>% mutate(Circunstancia = "Lengua indígena", Categoria = as.character(p111)) %>% select(Circunstancia, Categoria, N, Ingreso_Promedio, Porcentaje)
)

write.csv(todas_circunstancias,
          file.path(output_tables, "ingreso_por_circunstancia.csv"),
          row.names = FALSE)

cat("\n")
cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║  Tabla guardada: outputs/tables/ingreso_por_circunstancia.csv    ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n")

# ==============================================================================
# RESUMEN FINAL
# ==============================================================================

cat("\n")
cat("┌──────────────────────────────────────────────────────────────────┐\n")
cat("│                    RESUMEN DE BRECHAS                            │\n")
cat("├──────────────────────────────────────────────────────────────────┤\n")

# Calcular brechas
brecha_educm <- max(educm_tabla$Ingreso_Promedio) / min(educm_tabla$Ingreso_Promedio)
brecha_region <- max(region_tabla$Ingreso_Promedio) / min(region_tabla$Ingreso_Promedio)
brecha_rural <- max(rural_tabla$Ingreso_Promedio) / min(rural_tabla$Ingreso_Promedio)
brecha_sexo <- max(sexo_tabla$Ingreso_Promedio) / min(sexo_tabla$Ingreso_Promedio)

cat(sprintf("│  Educ. madre (universidad vs sin primaria): %.1fx más ingreso    │\n", brecha_educm))
cat(sprintf("│  Región (mejor vs peor):                    %.1fx más ingreso    │\n", brecha_region))
cat(sprintf("│  Ciudad vs Ranchería:                       %.1fx más ingreso    │\n", brecha_rural))
cat(sprintf("│  Hombre vs Mujer:                           %.1fx más ingreso    │\n", brecha_sexo))
cat("└──────────────────────────────────────────────────────────────────┘\n")

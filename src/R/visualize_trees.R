# ==============================================================================
# visualize_trees.R - Visualización de Árboles para IOp Analysis
# ==============================================================================
# Proyecto: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Propósito: Crear visualizaciones interpretables de árboles de decisión
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. INSTALACIÓN DE PAQUETES (ejecutar solo la primera vez)
# ------------------------------------------------------------------------------

install_if_missing <- function(packages) {
  new_packages <- packages[!(packages %in% installed.packages()[,"Package"])]
  if(length(new_packages)) {
    message("Instalando paquetes: ", paste(new_packages, collapse = ", "))
    install.packages(new_packages, dependencies = TRUE)
  }
}

# Paquetes necesarios
required_packages <- c(
  "haven",        # Leer archivos .dta (Stata)
  "partykit",     # Conditional Inference Trees (ctree) - MEJOR visualización
  "rpart",        # Árboles de decisión clásicos
  "rpart.plot",   # Visualización mejorada de rpart
  "ggplot2",      # Gráficos

  "dplyr",        # Manipulación de datos
  "tidyr",        # Limpieza de datos
  "viridis",      # Paletas de colores
  "gridExtra"     # Múltiples gráficos
)

install_if_missing(required_packages)

# Cargar paquetes
lapply(required_packages, library, character.only = TRUE)

# ------------------------------------------------------------------------------
# 2. CONFIGURACIÓN DE RUTAS
# ------------------------------------------------------------------------------

# Detectar directorio del proyecto automáticamente
# Si estás en RStudio, usar el directorio del proyecto
if (Sys.getenv("RSTUDIO") == "1") {
  project_root <- rstudioapi::getActiveProject()
  if (is.null(project_root)) {
    project_root <- dirname(rstudioapi::getActiveDocumentContext()$path)
    project_root <- dirname(dirname(project_root))  # Subir dos niveles desde src/R
  }
} else {
  # Si no estás en RStudio, definir manualmente
  project_root <- "C:/Users/HP ZBOOK/Desktop/Inequality of Opportunity"
}

# Rutas
data_path <- file.path(project_root, "data", "raw", "emovi", "Data", "entrevistado_2023.dta")
output_figures <- file.path(project_root, "outputs", "figures")
output_tables <- file.path(project_root, "outputs", "tables")

# Crear directorios si no existen
dir.create(output_figures, recursive = TRUE, showWarnings = FALSE)
dir.create(output_tables, recursive = TRUE, showWarnings = FALSE)

cat("Directorio del proyecto:", project_root, "\n")
cat("Archivo de datos:", data_path, "\n")

# ------------------------------------------------------------------------------
# 3. CARGAR Y PREPARAR DATOS
# ------------------------------------------------------------------------------

cat("\n--- Cargando datos EMOVI 2023 ---\n")

# Leer datos de Stata
df <- haven::read_dta(data_path)
cat("Observaciones cargadas:", nrow(df), "\n")

# Variables de circunstancias (mismo conjunto que en Python)
circumstance_vars <- c("educp", "educm", "clasep", "sexo", "p111", "p112",
                       "region_14", "cohorte", "p21")

# Variable de resultado
outcome_var <- "ingc_pc"

# Seleccionar variables relevantes
df_analysis <- df %>%
  select(all_of(c(outcome_var, circumstance_vars, "factor"))) %>%
  # Transformar a log del ingreso
  mutate(ln_income = log(ingc_pc)) %>%
  # Eliminar valores faltantes e infinitos
  filter(!is.na(ln_income) & !is.infinite(ln_income)) %>%
  # Convertir variables a factores con etiquetas descriptivas
  mutate(
    sexo = factor(sexo, levels = c(1, 2), labels = c("Hombre", "Mujer")),
    educp = factor(educp, levels = 1:4,
                   labels = c("Sin/Primaria", "Secundaria", "Preparatoria", "Universidad")),
    educm = factor(educm, levels = 1:4,
                   labels = c("Sin/Primaria", "Secundaria", "Preparatoria", "Universidad")),
    clasep = factor(clasep, levels = 1:6,
                    labels = c("I-Alta", "II", "IIIa", "IIIb", "IVa-c", "V-VII")),
    p111 = factor(p111, levels = c(1, 2), labels = c("Sí", "No")),
    region_14 = factor(region_14, levels = 1:5,
                       labels = c("Norte", "Centro-Norte", "Centro", "Centro-Sur", "Sur")),
    p21 = factor(p21, levels = 1:4,
                 labels = c("Ciudad", "Pueblo", "Ranchería", "NS"))
  ) %>%
  # Eliminar filas con NA en cualquier variable
  drop_na()

cat("Casos completos para análisis:", nrow(df_analysis), "\n")

# ------------------------------------------------------------------------------
# 4. ÁRBOL DE INFERENCIA CONDICIONAL (ctree) - RECOMENDADO
# ------------------------------------------------------------------------------

cat("\n--- Ajustando Conditional Inference Tree (ctree) ---\n")

# Fórmula del modelo
formula_iop <- as.formula(paste("ln_income ~", paste(circumstance_vars, collapse = " + ")))

# Configuración del árbol
ctrl_ctree <- ctree_control(
  mincriterion = 0.95,    # Nivel de significancia para splits (1 - alpha)
  minsplit = 100,         # Mínimo de observaciones para intentar split
  minbucket = 50,         # Mínimo de observaciones en nodos terminales
  maxdepth = 5            # Profundidad máxima (para visualización legible)
)

# Ajustar el árbol
ctree_model <- ctree(formula_iop, data = df_analysis, control = ctrl_ctree)

# Información del modelo
cat("Número de nodos terminales (tipos):", length(nodeids(ctree_model, terminal = TRUE)), "\n")

# ------------------------------------------------------------------------------
# 5. VISUALIZACIÓN DEL CTREE
# ------------------------------------------------------------------------------

cat("\n--- Generando visualizaciones ---\n")

# 5.1 Gráfico principal del árbol
png(file.path(output_figures, "ctree_visualization.png"),
    width = 1600, height = 1000, res = 100)
plot(ctree_model,
     main = "Árbol de Inferencia Condicional - IOp México (EMOVI 2023)",
     gp = gpar(fontsize = 9),
     inner_panel = node_inner(ctree_model, id = TRUE, pval = TRUE),
     terminal_panel = node_boxplot(ctree_model,
                                    col = "black",
                                    fill = viridis(length(nodeids(ctree_model, terminal = TRUE))),
                                    width = 0.5,
                                    yscale = NULL,
                                    ylines = 3,
                                    id = TRUE))
dev.off()
cat("Guardado: ctree_visualization.png\n")

# 5.2 Versión simplificada (solo estructura)
png(file.path(output_figures, "ctree_simple.png"),
    width = 1400, height = 800, res = 100)
plot(ctree_model,
     main = "Estructura del Árbol - Partición en Tipos",
     type = "simple",
     gp = gpar(fontsize = 10),
     inner_panel = node_inner(ctree_model, id = TRUE, pval = FALSE))
dev.off()
cat("Guardado: ctree_simple.png\n")

# ------------------------------------------------------------------------------
# 6. ÁRBOL CON RPART (alternativa clásica)
# ------------------------------------------------------------------------------

cat("\n--- Ajustando árbol rpart (alternativa) ---\n")

# Convertir factores a numéricos para rpart (maneja mejor)
df_rpart <- df_analysis %>%
  mutate(across(where(is.factor), as.numeric))

# Ajustar rpart
rpart_model <- rpart(
  ln_income ~ educp + educm + clasep + sexo + p111 + p112 + region_14 + cohorte + p21,
  data = df_rpart,
  method = "anova",
  control = rpart.control(
    minsplit = 100,
    minbucket = 50,
    maxdepth = 5,
    cp = 0.005  # Complexity parameter
  )
)

# Visualización con rpart.plot
png(file.path(output_figures, "rpart_tree.png"),
    width = 1400, height = 1000, res = 120)
rpart.plot(rpart_model,
           main = "Árbol de Decisión (rpart) - IOp México",
           type = 4,           # Estilo de nodos
           extra = 101,        # Mostrar % y n
           under = TRUE,       # Etiquetas debajo
           faclen = 0,         # No abreviar nombres
           cex = 0.8,          # Tamaño de texto
           box.palette = "RdYlGn",  # Paleta de colores
           shadow.col = "gray")
dev.off()
cat("Guardado: rpart_tree.png\n")

# Versión con más detalle
png(file.path(output_figures, "rpart_tree_detailed.png"),
    width = 1600, height = 1200, res = 120)
rpart.plot(rpart_model,
           main = "Árbol de Decisión Detallado - IOp México (EMOVI 2023)",
           type = 2,
           extra = 101,
           fallen.leaves = TRUE,
           branch.lty = 3,
           box.palette = "BuGn",
           cex = 0.75)
dev.off()
cat("Guardado: rpart_tree_detailed.png\n")

# ------------------------------------------------------------------------------
# 7. CALCULAR MÉTRICAS IOp
# ------------------------------------------------------------------------------

cat("\n--- Calculando métricas IOp ---\n")

# Predicciones (medias de tipo)
df_analysis$predicted_ctree <- predict(ctree_model)
df_analysis$predicted_rpart <- predict(rpart_model, df_rpart)

# Función para calcular Gini
gini_coefficient <- function(x, weights = NULL) {
  if (is.null(weights)) weights <- rep(1, length(x))

  # Ordenar por x
  ord <- order(x)
  x <- x[ord]
  weights <- weights[ord]

  # Calcular Gini ponderado
  n <- length(x)
  cum_w <- cumsum(weights)
  cum_wx <- cumsum(weights * x)

  total_w <- sum(weights)
  total_wx <- sum(weights * x)

  gini <- 1 - 2 * sum(cum_wx[-n] * diff(cum_w)) / (total_w * total_wx)
  return(max(0, gini))
}

# Métricas para ctree
y_true <- exp(df_analysis$ln_income)  # Volver a escala original
y_pred_ctree <- exp(df_analysis$predicted_ctree)

gini_total <- gini_coefficient(y_true)
gini_between_ctree <- gini_coefficient(y_pred_ctree)
iop_ctree <- gini_between_ctree / gini_total

# R-squared
r2_ctree <- 1 - sum((df_analysis$ln_income - df_analysis$predicted_ctree)^2) /
               sum((df_analysis$ln_income - mean(df_analysis$ln_income))^2)

# Métricas para rpart
y_pred_rpart <- exp(df_analysis$predicted_rpart)
gini_between_rpart <- gini_coefficient(y_pred_rpart)
iop_rpart <- gini_between_rpart / gini_total

r2_rpart <- 1 - sum((df_analysis$ln_income - df_analysis$predicted_rpart)^2) /
               sum((df_analysis$ln_income - mean(df_analysis$ln_income))^2)

# Mostrar resultados
cat("\n========================================\n")
cat("RESULTADOS IOp (R)\n")
cat("========================================\n")
cat("\nConditional Inference Tree (ctree):\n")
cat("  - Número de tipos:", length(nodeids(ctree_model, terminal = TRUE)), "\n")
cat("  - IOp Share (Gini):", round(iop_ctree * 100, 1), "%\n")
cat("  - R²:", round(r2_ctree * 100, 1), "%\n")

cat("\nÁrbol rpart:\n")
cat("  - Número de tipos:", sum(rpart_model$frame$var == "<leaf>"), "\n")
cat("  - IOp Share (Gini):", round(iop_rpart * 100, 1), "%\n")
cat("  - R²:", round(r2_rpart * 100, 1), "%\n")
cat("========================================\n")

# Guardar resultados
results_r <- data.frame(
  Model = c("ctree (R)", "rpart (R)"),
  IOp_Gini = c(iop_ctree, iop_rpart),
  IOp_R2 = c(r2_ctree, r2_rpart),
  N_Types = c(length(nodeids(ctree_model, terminal = TRUE)),
              sum(rpart_model$frame$var == "<leaf>"))
)
write.csv(results_r, file.path(output_tables, "iop_results_R.csv"), row.names = FALSE)
cat("\nResultados guardados en: iop_results_R.csv\n")

# ------------------------------------------------------------------------------
# 8. IMPORTANCIA DE VARIABLES
# ------------------------------------------------------------------------------

cat("\n--- Importancia de variables ---\n")

# Para ctree, usar varimp de partykit (si está disponible)
# Alternativa: contar splits por variable
get_ctree_varimp <- function(tree) {
  # Extraer información de splits
  nodes <- nodeids(tree)
  inner_nodes <- nodes[!nodes %in% nodeids(tree, terminal = TRUE)]

  split_vars <- sapply(inner_nodes, function(id) {
    node <- nodeapply(tree, id)[[1]]
    if (!is.null(node$split)) {
      return(names(node$split$varid))
    }
    return(NA)
  })

  # Contar frecuencia de cada variable
  var_counts <- table(unlist(split_vars))
  var_importance <- var_counts / sum(var_counts)

  return(sort(var_importance, decreasing = TRUE))
}

# Importancia de rpart (incorporada)
rpart_varimp <- rpart_model$variable.importance
rpart_varimp_norm <- rpart_varimp / sum(rpart_varimp)

cat("\nImportancia de variables (rpart):\n")
print(round(rpart_varimp_norm * 100, 1))

# Guardar
varimp_df <- data.frame(
  variable = names(rpart_varimp_norm),
  importance = as.numeric(rpart_varimp_norm)
)
write.csv(varimp_df, file.path(output_tables, "varimp_rpart.csv"), row.names = FALSE)

# ------------------------------------------------------------------------------
# 9. GRÁFICO DE IMPORTANCIA DE VARIABLES
# ------------------------------------------------------------------------------

# Gráfico de barras de importancia
png(file.path(output_figures, "varimp_rpart_R.png"),
    width = 800, height = 600, res = 120)
par(mar = c(5, 10, 4, 2))
barplot(sort(rpart_varimp_norm),
        horiz = TRUE,
        las = 1,
        main = "Importancia de Variables (rpart)",
        xlab = "Importancia Relativa",
        col = viridis(length(rpart_varimp_norm)),
        border = NA)
dev.off()
cat("Guardado: varimp_rpart_R.png\n")

# ------------------------------------------------------------------------------
# 10. RESUMEN FINAL
# ------------------------------------------------------------------------------

cat("\n")
cat("╔══════════════════════════════════════════════════════════════════╗\n")
cat("║           ANÁLISIS COMPLETADO EXITOSAMENTE                       ║\n")
cat("╠══════════════════════════════════════════════════════════════════╣\n")
cat("║ Archivos generados en outputs/figures/:                          ║\n")
cat("║   • ctree_visualization.png  - Árbol ctree con boxplots          ║\n")
cat("║   • ctree_simple.png         - Estructura simplificada           ║\n")
cat("║   • rpart_tree.png           - Árbol rpart coloreado             ║\n")
cat("║   • rpart_tree_detailed.png  - Árbol rpart detallado             ║\n")
cat("║   • varimp_rpart_R.png       - Importancia de variables          ║\n")
cat("╠══════════════════════════════════════════════════════════════════╣\n")
cat("║ Archivos generados en outputs/tables/:                           ║\n")
cat("║   • iop_results_R.csv        - Métricas IOp de R                 ║\n")
cat("║   • varimp_rpart.csv         - Importancia de variables          ║\n")
cat("╚══════════════════════════════════════════════════════════════════╝\n")

cat("\n¡Listo! Puedes ver los árboles en la carpeta outputs/figures/\n")

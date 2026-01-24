# ==============================================================================
# visualize_trees_mejorado.R - Visualizaciones MEJORADAS de Árboles
# ==============================================================================

library(partykit)
library(rpart)
library(rpart.plot)
library(viridis)

# Usar datos ya cargados del script anterior
# Si no están cargados, ejecutar primero: source("src/R/visualize_trees.R")

project_root <- getwd()
output_figures <- file.path(project_root, "outputs", "figures")

cat("Generando visualizaciones mejoradas...\n\n")

# ==============================================================================
# 1. ÁRBOL MÁS PEQUEÑO (más fácil de ver)
# ==============================================================================

cat("1. Creando árbol simplificado (profundidad 3)...\n")

# Árbol con menos profundidad para que sea más legible
ctrl_simple <- ctree_control(
  mincriterion = 0.99,
  minsplit = 200,
  minbucket = 100,
  maxdepth = 3  # Solo 3 niveles
)

ctree_simple <- ctree(formula_iop, data = df_analysis, control = ctrl_simple)

# Guardar en tamaño grande
png(file.path(output_figures, "arbol_simplificado.png"),
    width = 2000, height = 1200, res = 150)
plot(ctree_simple,
     main = "Árbol de Desigualdad de Oportunidad (Simplificado)",
     gp = gpar(fontsize = 11))
dev.off()
cat("   Guardado: arbol_simplificado.png\n")

# ==============================================================================
# 2. ÁRBOL RPART MUY LEGIBLE
# ==============================================================================

cat("2. Creando árbol rpart legible...\n")

# Árbol rpart más simple
rpart_simple <- rpart(
  ln_income ~ sexo + educp + educm + clasep + region_14 + cohorte + p21,
  data = df_rpart,
  method = "anova",
  control = rpart.control(
    minsplit = 200,
    minbucket = 100,
    maxdepth = 4,
    cp = 0.01
  )
)

# Versión 1: Estilo clásico muy legible
png(file.path(output_figures, "arbol_rpart_legible.png"),
    width = 1600, height = 1200, res = 150)
rpart.plot(rpart_simple,
           main = "Árbol de Decisión - IOp México",
           type = 2,
           extra = 101,
           under = TRUE,
           cex = 1.1,
           box.palette = "RdYlGn",
           shadow.col = "gray70",
           nn = TRUE,  # Mostrar número de nodo
           fallen.leaves = FALSE)
dev.off()
cat("   Guardado: arbol_rpart_legible.png\n")

# Versión 2: Con hojas alineadas abajo
png(file.path(output_figures, "arbol_rpart_hojas.png"),
    width = 1800, height = 1000, res = 150)
rpart.plot(rpart_simple,
           main = "Árbol IOp - Hojas Alineadas",
           type = 4,
           extra = 101,
           fallen.leaves = TRUE,
           cex = 1.0,
           box.palette = "BuGn",
           tweak = 1.2)
dev.off()
cat("   Guardado: arbol_rpart_hojas.png\n")

# ==============================================================================
# 3. ÁRBOL COMPLETO EN TAMAÑO MUY GRANDE (para zoom)
# ==============================================================================

cat("3. Creando árbol completo en alta resolución (para hacer zoom)...\n")

# Árbol completo
ctrl_full <- ctree_control(
  mincriterion = 0.95,
  minsplit = 100,
  minbucket = 50,
  maxdepth = 5
)

ctree_full <- ctree(formula_iop, data = df_analysis, control = ctrl_full)

# Guardar en resolución muy alta (para abrir y hacer zoom)
png(file.path(output_figures, "arbol_completo_zoom.png"),
    width = 4000, height = 2500, res = 150)
plot(ctree_full,
     main = "Árbol Completo - IOp México (Abrir imagen y hacer zoom)",
     gp = gpar(fontsize = 8),
     inner_panel = node_inner(ctree_full, id = TRUE, pval = FALSE),
     terminal_panel = node_boxplot(ctree_full,
                                    col = "black",
                                    fill = "lightblue",
                                    width = 0.5,
                                    id = TRUE))
dev.off()
cat("   Guardado: arbol_completo_zoom.png (abrir y hacer zoom para ver detalles)\n")

# ==============================================================================
# 4. GUARDAR ÁRBOL COMO PDF (mejor para zoom)
# ==============================================================================

cat("4. Creando versión PDF (mejor calidad para zoom)...\n")

pdf(file.path(output_figures, "arbol_completo.pdf"),
    width = 20, height = 12)
plot(ctree_full,
     main = "Árbol de Desigualdad de Oportunidad - EMOVI 2023",
     gp = gpar(fontsize = 7))
dev.off()
cat("   Guardado: arbol_completo.pdf\n")

# PDF del árbol simple
pdf(file.path(output_figures, "arbol_simple.pdf"),
    width = 14, height = 8)
plot(ctree_simple,
     main = "Árbol Simplificado - IOp México",
     gp = gpar(fontsize = 10))
dev.off()
cat("   Guardado: arbol_simple.pdf\n")

# ==============================================================================
# 5. INFORMACIÓN DE LOS ÁRBOLES
# ==============================================================================

cat("\n========================================\n")
cat("RESUMEN DE ÁRBOLES GENERADOS\n")
cat("========================================\n")
cat("\nÁrbol simplificado (profundidad 3):\n")
cat("  - Nodos terminales:", length(nodeids(ctree_simple, terminal = TRUE)), "\n")

cat("\nÁrbol completo (profundidad 5):\n")
cat("  - Nodos terminales:", length(nodeids(ctree_full, terminal = TRUE)), "\n")

cat("\nÁrbol rpart:\n")
cat("  - Nodos terminales:", sum(rpart_simple$frame$var == "<leaf>"), "\n")

cat("\n========================================\n")
cat("ARCHIVOS GENERADOS EN outputs/figures/:\n")
cat("========================================\n")
cat("  • arbol_simplificado.png  - Fácil de leer (3 niveles)\n")
cat("  • arbol_rpart_legible.png - Colores claros\n")
cat("  • arbol_rpart_hojas.png   - Hojas alineadas\n")
cat("  • arbol_completo_zoom.png - Alta resolución (hacer zoom)\n")
cat("  • arbol_completo.pdf      - PDF (mejor para zoom)\n")
cat("  • arbol_simple.pdf        - PDF simplificado\n")
cat("========================================\n")

cat("\nTIP: Los archivos PDF se pueden abrir y hacer zoom sin perder calidad.\n")

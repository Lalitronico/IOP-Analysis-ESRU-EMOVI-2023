# Guía Rápida: Usar el Proyecto en RStudio

## 1. Abrir el Proyecto

**Opción A (Recomendada):** Haz doble clic en el archivo `IOp_Analysis.Rproj`

**Opción B:** En RStudio: File → Open Project → Seleccionar `IOp_Analysis.Rproj`

## 2. Instalar Paquetes Necesarios

Ejecuta esto en la consola de R (solo la primera vez):

```r
install.packages(c(
  "haven",        # Leer archivos Stata
  "partykit",     # Árboles de inferencia condicional
  "rpart",        # Árboles de decisión
  "rpart.plot",   # Visualización de árboles
  "ggplot2",      # Gráficos
  "dplyr",        # Manipulación de datos
  "tidyr",        # Limpieza de datos
  "viridis"       # Paletas de colores
))
```

## 3. Visualizar los Árboles

Abre y ejecuta el script de visualización:

```r
source("src/R/visualize_trees.R")
```

O bien, abre el archivo `src/R/visualize_trees.R` y ejecuta sección por sección con `Ctrl+Enter`.

## 4. Archivos Generados

Después de ejecutar el script, encontrarás en `outputs/figures/`:

| Archivo | Descripción |
|---------|-------------|
| `ctree_visualization.png` | Árbol ctree con boxplots en cada nodo terminal |
| `ctree_simple.png` | Estructura simplificada del árbol |
| `rpart_tree.png` | Árbol rpart con colores (más legible) |
| `rpart_tree_detailed.png` | Árbol rpart con hojas caídas |
| `varimp_rpart_R.png` | Gráfico de importancia de variables |

## 5. Estructura del Proyecto

```
Inequality of Opportunity/
├── IOp_Analysis.Rproj      ← Abrir este archivo
├── config/
│   ├── config.yaml         # Configuración general
│   └── variable_roles.yaml # Mapeo de variables
├── data/
│   └── raw/emovi/Data/     # Datos EMOVI 2023
├── src/
│   ├── R/
│   │   ├── visualize_trees.R   ← Script principal de visualización
│   │   ├── 00_setup.R
│   │   └── ...
│   └── python/
│       ├── iop_analysis.py     # Análisis principal
│       └── xgboost_shap_analysis.py
├── outputs/
│   ├── figures/            # Gráficos generados
│   └── tables/             # Tablas de resultados
└── FOR_EDUARDO.md          # Documentación del proyecto
```

## 6. Interpretar los Árboles

### Árbol ctree (Conditional Inference Tree)

- **Nodos internos**: Muestran la variable de split y el p-valor del test estadístico
- **Nodos terminales**: Boxplots del log(ingreso) para cada "tipo"
- **Interpretación**: Cada nodo terminal representa un grupo de personas con circunstancias similares

### Árbol rpart

- **Colores**: Verde = mayor ingreso promedio, Rojo = menor ingreso
- **Números en nodos**: Media del log(ingreso) y % de la muestra
- **Splits**: Condiciones que dividen la muestra

## 7. Ejemplo de Interpretación

Si ves un split como:
```
educm = Sin/Primaria, Secundaria
        ↓
    n = 5000
    media = 8.2
```

Significa: Las personas cuya madre tiene educación primaria o secundaria (n=5000) tienen un log(ingreso) promedio de 8.2.

## 8. Modificar el Análisis

Para cambiar la profundidad máxima del árbol:

```r
# En visualize_trees.R, modifica:
ctrl_ctree <- ctree_control(
  maxdepth = 5  # Cambiar a 4, 6, etc.
)
```

Para usar otras variables:

```r
# Modifica el vector de circunstancias:
circumstance_vars <- c("educp", "educm", "sexo", "region_14")  # Tu selección
```

## 9. Resultados Principales

Los resultados del análisis muestran:

- **IOp Share ≈ 52-57%**: Más de la mitad de la desigualdad de ingresos se debe a circunstancias fuera del control individual
- **Factores más importantes**: Educación de la madre, región, sexo
- **~50-60 tipos**: El árbol identifica grupos con diferentes expectativas de ingreso

## 10. Recursos Adicionales

- Documentación completa: `FOR_EDUARDO.md`
- Metodología: `docs/methodology.md`
- Resultados Python: `outputs/tables/iop_main_results.csv`
- SHAP analysis: `outputs/figures/shap_summary.png`

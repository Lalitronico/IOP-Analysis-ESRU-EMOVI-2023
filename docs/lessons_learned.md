# Lecciones Aprendidas - Proyecto IOp

## Fecha: 2026-01-25

Este documento registra errores encontrados durante el desarrollo para evitar repetirlos en el futuro.

---

## 1. Codificación de Variables Categóricas

### Problema
La variable `p112` (tono de piel, escala PERLA) estaba codificada como STRING con letras A-K en lugar de números 1-11. Esto causó:
- **Python:** `pd.to_numeric(errors='coerce')` la convertía a NaN → SHAP = 0%
- **R:** Error "cannot handle objects of class 'character'"

### Lección
**SIEMPRE verificar el tipo de dato de cada variable antes del análisis.**

```python
# Python - Verificación
print(df['p112'].dtype)
print(df['p112'].value_counts())
```

```r
# R - Verificación
class(df$p112)
table(df$p112)
```

### Solución Implementada
```python
# Python
perla_map = {chr(65+i): i+1 for i in range(11)}  # A=1, B=2, ..., K=11
df['p112'] = df['p112'].map(perla_map)
```

```r
# R
df$p112 <- match(df$p112, LETTERS[1:11])
```

---

## 2. Formato haven_labelled de Stata

### Problema
Variables importadas de archivos .dta (Stata) tienen clase `haven_labelled` que muchas funciones de R no pueden manejar.

### Lección
**Convertir variables labelled a tipos nativos inmediatamente después de importar.**

### Solución
```r
library(haven)
df <- read_dta("archivo.dta") %>%
  mutate(across(where(is.labelled), ~as.numeric(.)))
```

---

## 3. Dependencias de Paquetes (renv)

### Problema
`renv` intentó instalar `ALEPlot` que no está disponible para R 4.5, bloqueando todo el entorno.

### Lección
- **No asumir que todos los paquetes están disponibles para la versión actual de R**
- **Mantener lista de paquetes mínimos necesarios vs opcionales**
- **Probar el entorno renv en una instalación limpia antes de compartir**

### Solución
```r
# Desactivar renv temporalmente si hay problemas
renv::deactivate()

# O excluir paquetes problemáticos del lockfile
```

---

## 4. Incompatibilidad de API de Paquetes

### Problema
`ineq::Gini()` en algunas versiones no acepta el argumento `weights`.

### Lección
**No asumir que la API de un paquete es estable entre versiones.**

### Solución
Implementar funciones críticas manualmente o con verificación de versión:

```r
calc_gini <- function(x) {
  x <- x[!is.na(x) & x > 0]
  n <- length(x)
  x <- sort(x)
  G <- sum((2 * seq_along(x) - n - 1) * x)
  G / (n * sum(x))
}
```

---

## 5. Archivos Intermedios No Generados

### Problema
Scripts asumen que archivos como `entrevistado_clean.rds` existen, pero el pipeline de preprocesamiento no se había ejecutado.

### Lección
**Scripts deben ser ejecutables de forma independiente o documentar claramente sus dependencias.**

### Solución
Opción A: Verificar existencia y dar instrucciones claras
```r
if (!file.exists("data/processed/entrevistado_clean.rds")) {
  stop("Ejecutar primero: source('src/R/02_preprocess.R')")
}
```

Opción B: Cargar datos crudos si no existen procesados
```r
if (file.exists("data/processed/entrevistado_clean.rds")) {
  df <- readRDS("data/processed/entrevistado_clean.rds")
} else {
  df <- read_dta("data/raw/emovi/Data/entrevistado_2023.dta")
  # ... preprocesamiento básico ...
}
```

---

## 6. Inconsistencia en Nombres de Variables

### Problema
- Scripts usan nombres descriptivos: `indigenous`, `skin_tone`, `rural_14`
- Datos originales usan códigos: `p111`, `p112`, `p21`

### Lección
**Definir un único diccionario de nombres y usarlo consistentemente.**

### Solución
Usar `variable_roles.yaml` como fuente única de verdad:

```yaml
# config/variable_roles.yaml
circumstances:
  demographic:
    - name: "indigenous"
      source_var: "p111"  # <- Nombre original en datos
```

```r
# Cargar mapeo
var_roles <- yaml::read_yaml("config/variable_roles.yaml")
# Usar source_var para cargar, name para análisis
```

---

## Checklist Pre-Análisis

Antes de ejecutar cualquier análisis, verificar:

- [ ] Tipos de datos de todas las variables (`str()`, `dtypes`)
- [ ] Valores únicos de variables categóricas (`table()`, `value_counts()`)
- [ ] Porcentaje de missing por variable
- [ ] Que archivos intermedios necesarios existen
- [ ] Que paquetes necesarios están instalados y son compatibles
- [ ] Que nombres de variables coinciden entre scripts y datos

---

## Herramientas de Diagnóstico Creadas

1. **`src/python/diagnose_p112.py`** - Diagnóstico completo de variable p112
2. **`src/R/07_simple_sensitivity.R`** - Script independiente sin dependencias complejas

---

*Documento creado para mejorar la reproducibilidad y evitar errores recurrentes.*

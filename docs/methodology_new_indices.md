# Metodología: Nuevos Índices de Circunstancias para el Análisis IOp

## 1. Introducción

Este documento describe la metodología para la construcción de cinco nuevos índices de circunstancias diseñados para capturar de manera más comprehensiva los factores fuera del control individual que afectan los resultados económicos. Estos índices complementan las variables tradicionales de circunstancias (educación parental, clase ocupacional del padre, etc.) siguiendo el marco teórico de Roemer (1998) y las recomendaciones metodológicas de Brunori, Ferreira y Peragine (2013).

## 2. Marco Teórico

### 2.1 Circunstancias en el Marco de Roemer

Según Roemer (1998), la desigualdad de oportunidades (IOp) surge de factores que están fuera del control del individuo. Estos factores, denominados **circunstancias**, incluyen:

1. **Origen familiar**: Educación y ocupación de los padres
2. **Características adscritas**: Sexo, etnicidad, tono de piel
3. **Contexto geográfico**: Región, ruralidad
4. **Condiciones materiales del hogar de origen**: Recursos económicos disponibles durante la infancia

Los nuevos índices expanden la captura de la dimensión (4), que tradicionalmente ha sido subestimada en los análisis de IOp.

### 2.2 Justificación para Índices Compuestos

Ferreira y Gignoux (2011) argumentan que las estimaciones de IOp son **cotas inferiores** del verdadero nivel de desigualdad de oportunidades, debido a:
- Omisión de circunstancias no observadas
- Error de medición en circunstancias observadas
- Agregación inadecuada de información multidimensional

Los índices compuestos permiten:
1. Reducir dimensionalidad sin perder información sustantiva
2. Capturar constructos latentes (ej. "nivel socioeconómico")
3. Evitar problemas de multicolinealidad al incluir múltiples indicadores correlacionados

---

## 3. Índice de Condiciones Económicas del Hogar (MCA)

### 3.1 Fundamentación del Método

**Multiple Correspondence Analysis (MCA)** es la técnica apropiada para variables categóricas/binarias, análoga al PCA para variables continuas (Greenacre, 2017).

#### ¿Por qué MCA y no PCA?

| Aspecto | PCA | MCA |
|---------|-----|-----|
| Tipo de variables | Continuas | Categóricas/Binarias |
| Supuesto de linealidad | Requiere | No requiere |
| Métrica | Correlación de Pearson | Chi-cuadrado |
| Variables de activos (Sí/No) | **Inapropiado** | **Apropiado** |

Las variables P31a-l (posesión de bienes) son binarias (1=Sí, 2=No), por lo que MCA es metodológicamente superior.

### 3.2 Variables Incluidas

```
BIENES DURABLES (P31):
├── p31a: Estufa               → Necesidad básica
├── p31b: Lavadora             → Ahorro de tiempo doméstico
├── p31c: Refrigerador         → Preservación de alimentos
├── p31d: Teléfono fijo        → Conectividad
├── p31e: Televisor            → Acceso a información
├── p31g: Aspiradora           → Indicador de clase media-alta
├── p31h: TV por cable         → Contenido diverso
├── p31i: Microondas           → Modernidad del hogar
├── p31k: Computadora          → Capital digital
└── p31l: Internet             → Conectividad global

SERVICIOS BÁSICOS (P26):
├── p26a: Agua entubada        → Infraestructura sanitaria
├── p26b: Electricidad         → Acceso energético
├── p26c: Baño dentro          → Condiciones sanitarias
├── p26d: Calentador de agua   → Confort básico
└── p26e: Servicio doméstico   → Indicador de nivel alto

VIVIENDA:
└── p25: Material del piso     → Calidad estructural
```

### 3.3 Implementación en R

```r
create_household_economic_index <- function(df) {
  # Variables de entrada (todas binarias/categóricas)
  asset_vars <- c("p31a", "p31b", "p31c", "p31d", "p31e",
                  "p31g", "p31h", "p31i", "p31k", "p31l")
  service_vars <- c("p26a", "p26b", "p26c", "p26d", "p26e")

  # Preparar como factores para MCA
  df_mca <- df %>%
    select(all_of(c(asset_vars, service_vars, "p25"))) %>%
    mutate(across(everything(), as.factor))

  # Ejecutar MCA (FactoMineR)
  mca_result <- FactoMineR::MCA(df_mca[complete.cases(df_mca), ],
                                 ncp = 2,        # 2 dimensiones
                                 graph = FALSE)

  # Dimensión 1 captura el gradiente socioeconómico
  # Estandarizar a escala 0-100
  dim1 <- mca_result$ind$coord[, 1]
  index <- (dim1 - min(dim1)) / (max(dim1) - min(dim1)) * 100

  return(index)
}
```

### 3.4 Interpretación

- **Dimensión 1 del MCA**: Típicamente captura el gradiente principal de variación, que en datos de activos corresponde al nivel socioeconómico.
- **Inercia explicada**: Porcentaje de varianza total capturada (análogo a % varianza en PCA).
- **Valores altos del índice**: Mayor nivel socioeconómico del hogar de origen.

---

## 4. Índice de Calidad del Vecindario

### 4.1 Fundamentación

El contexto comunitario afecta las oportunidades a través de:
- **Efecto de pares** (Wilson, 1987): Exposición a modelos de rol
- **Recursos institucionales**: Escuelas, centros de salud
- **Seguridad**: Capacidad de acumular capital humano sin disrupción

### 4.2 Variables Incluidas (P33a-h)

| Variable | Indicador | Codificación Original |
|----------|-----------|----------------------|
| p33a | Alumbrado público | 1=Sí, 2=Más o menos, 3=No |
| p33b | Escuelas/bibliotecas cercanas | " |
| p33c | Centros médicos accesibles | " |
| p33d | Guarderías disponibles | " |
| p33e | Espacios de esparcimiento | " |
| p33f | Seguridad en la zona | " |
| p33g | Transporte público | " |
| p33h | Limpieza de calles | " |

### 4.3 Método de Construcción

Suma ponderada con recodificación:
- 1 (Sí) → 2 puntos
- 2 (Más o menos) → 1 punto
- 3 (No) → 0 puntos

```r
create_neighborhood_index <- function(df) {
  neigh_vars <- paste0("p33", letters[1:8])

  df_neigh <- df %>%
    select(all_of(neigh_vars)) %>%
    mutate(across(everything(), ~case_when(
      . == 1 ~ 2,  # Sí = 2
      . == 2 ~ 1,  # Más o menos = 1
      . == 3 ~ 0,  # No = 0
      TRUE ~ NA_real_
    )))

  # Rango: 0-16, estandarizado a 0-100
  index <- rowSums(df_neigh, na.rm = FALSE) / 16 * 100
  return(index)
}
```

### 4.4 Validez del Constructo

Este índice captura el concepto de **neighborhood effects** de la literatura sociológica (Sampson et al., 2002), relevante porque:
- Las condiciones del vecindario a los 14 años son exógenas al individuo
- Afectan acceso a educación, salud y oportunidades laborales
- Correlacionan con pero no son idénticas a ruralidad (capturan variación intra-rural e intra-urbana)

---

## 5. Índice de Hacinamiento (Crowding)

### 5.1 Fundamentación

El hacinamiento es un indicador clásico de privación material (Townsend, 1979) que afecta:
- Capacidad de estudio en el hogar
- Salud física y mental
- Desarrollo cognitivo infantil (Evans, 2006)

### 5.2 Cálculo

```r
create_crowding_index <- function(df) {
  # Personas por cuarto de dormir
  crowding <- df$p22 / pmax(df$p24, 1)  # Mínimo 1 para evitar división por 0
  return(crowding)
}
```

Donde:
- `p22`: Número de personas en el hogar a los 14 años
- `p24`: Número de cuartos usados para dormir

### 5.3 Interpretación

| Valor | Interpretación | Referencia |
|-------|----------------|------------|
| ≤ 2.0 | Sin hacinamiento | INEGI |
| 2.1 - 2.5 | Hacinamiento leve | |
| 2.6 - 3.0 | Hacinamiento moderado | |
| > 3.0 | Hacinamiento severo | |

**Nota**: A diferencia de otros índices, valores **altos** indican **peores** condiciones.

---

## 6. Índice de Inclusión Financiera

### 6.1 Fundamentación

El acceso a servicios financieros del hogar de origen afecta:
- Capacidad de inversión en capital humano (educación)
- Resiliencia ante shocks económicos
- Transmisión intergeneracional de riqueza (Chetty et al., 2014)

### 6.2 Variables Incluidas

| Variable | Indicador |
|----------|-----------|
| p32e | Familia tenía cuenta de ahorro |
| p32f | Familia tenía tarjeta de crédito |
| p32n | Familia tenía seguros |

### 6.3 Implementación

```r
create_financial_inclusion_index <- function(df) {
  fin_vars <- c("p32e", "p32f", "p32n")

  df_fin <- df %>%
    select(all_of(fin_vars)) %>%
    mutate(across(everything(), ~ifelse(. == 1, 1, 0)))  # 1=Sí, 0=No

  # Suma (0-3), estandarizada a 0-100
  index <- rowSums(df_fin, na.rm = FALSE) / 3 * 100
  return(index)
}
```

---

## 7. Índice de Capital Cultural

### 7.1 Fundamentación Teórica

Siguiendo a Bourdieu (1986), el **capital cultural** en su forma objetivada incluye el acceso a recursos que facilitan la adquisición de conocimiento y cultura legítima. En el contexto contemporáneo, esto incluye recursos digitales.

### 7.2 Variables Incluidas

| Variable | Recurso | Justificación |
|----------|---------|---------------|
| p31k | Computadora | Acceso a conocimiento digital |
| p31l | Internet | Conectividad global, información |
| p31e | Televisor | Acceso a información/cultura |
| p31h | TV por cable | Contenido diverso/educativo |
| p31m | DVD/Videocasetera | Material audiovisual |

### 7.3 Implementación

```r
create_cultural_capital_index <- function(df) {
  cultural_vars <- c("p31k", "p31l", "p31e", "p31h", "p31m")

  df_cult <- df %>%
    select(all_of(cultural_vars)) %>%
    mutate(across(everything(), ~ifelse(. == 1, 1, 0)))

  # Suma (0-5), estandarizada a 0-100
  index <- rowSums(df_cult, na.rm = FALSE) / 5 * 100
  return(index)
}
```

### 7.4 Distinción del Índice Económico

Aunque hay solapamiento de variables (p31k, p31l, p31e, p31h), el índice de capital cultural:
- Se enfoca específicamente en recursos de acceso a información
- Puede usarse independientemente cuando se quiere aislar esta dimensión
- Complementa el análisis de transmisión intergeneracional de capital cultural

---

## 8. Conjuntos de Circunstancias para Análisis de Sensibilidad

### 8.1 Especificaciones Definidas

| Conjunto | # Variables | Descripción | Propósito |
|----------|-------------|-------------|-----------|
| `minimal` | 5 | Circunstancias básicas | Cota inferior conservadora |
| `standard` | 9 | Brunori et al. (2013) | Comparabilidad internacional |
| `extended` | 13 | + variables hogar individual | Especificación tradicional expandida |
| `extended_household` | 11 | Standard + índice económico + hacinamiento | Foco en condiciones materiales |
| `extended_neighborhood` | 10 | Standard + índice vecindario | Foco en contexto geográfico |
| `extended_cultural` | 10 | Standard + capital cultural | Foco en recursos informativos |
| `maximum` | 14 | Todos los índices | Cota superior |

### 8.2 Resultados Esperados

Siguiendo Brunori et al. (2013), esperamos:

```
IOp(minimal) < IOp(standard) < IOp(extended) ≈ IOp(maximum)
```

La diferencia entre `standard` y `maximum` indica cuánta desigualdad de oportunidades adicional capturan los nuevos índices.

---

## 9. Consideraciones Metodológicas

### 9.1 Multicolinealidad

**Correlaciones esperadas**:
- `neighborhood_index` ↔ `rural_14`: Correlación negativa alta
- `household_economic_index` ↔ `cultural_capital_index`: Correlación positiva alta
- `crowding_index` ↔ `household_economic_index`: Correlación negativa

**Mitigación**:
- Calcular VIF (Variance Inflation Factor) antes de incluir múltiples índices
- Usar regularización (ridge/lasso) en modelos paramétricos
- En ctree/cforest, la multicolinealidad afecta interpretación pero no predicción

### 9.2 Datos Faltantes

Todos los índices manejan casos incompletos retornando `NA`. El análisis final usa solo casos completos (listwise deletion) para mantener comparabilidad entre especificaciones.

### 9.3 Interpretación de IOp

Recordar que todas las estimaciones de IOp son **cotas inferiores** porque:
1. Existen circunstancias no observadas
2. Los índices son proxies imperfectos de constructos latentes
3. Error de medición atenúa estimaciones

---

## 10. Referencias

- Bourdieu, P. (1986). The forms of capital. In J. Richardson (Ed.), *Handbook of Theory and Research for the Sociology of Education*.
- Brunori, P., Ferreira, F. H., & Peragine, V. (2013). Inequality of opportunity, income inequality, and economic mobility. *Review of Income and Wealth*, 59(3), 395-428.
- Chetty, R., Hendren, N., Kline, P., & Saez, E. (2014). Where is the land of opportunity? *Quarterly Journal of Economics*, 129(4), 1553-1623.
- Evans, G. W. (2006). Child development and the physical environment. *Annual Review of Psychology*, 57, 423-451.
- Ferreira, F. H., & Gignoux, J. (2011). The measurement of inequality of opportunity. *Review of Income and Wealth*, 57(4), 622-657.
- Greenacre, M. (2017). *Correspondence Analysis in Practice* (3rd ed.). CRC Press.
- Roemer, J. E. (1998). *Equality of Opportunity*. Harvard University Press.
- Sampson, R. J., Morenoff, J. D., & Gannon-Rowley, T. (2002). Assessing "neighborhood effects". *Annual Review of Sociology*, 28, 443-478.
- Townsend, P. (1979). *Poverty in the United Kingdom*. Penguin Books.
- Wilson, W. J. (1987). *The Truly Disadvantaged*. University of Chicago Press.

# Auditoría Metodológica del Proyecto IOp
## ESRU-EMOVI 2023

| Campo | Valor |
|-------|-------|
| **Proyecto** | Inequality of Opportunity Analysis |
| **Fuente de datos** | ESRU-EMOVI 2023 |
| **Métodos** | ctree, cforest, Random Forest, XGBoost + SHAP |
| **Fecha de auditoría** | 2026-01-25 |

---

## 1. Evaluación de Autenticidad de Datos

### 1.1 Verificación de Fuente

| Criterio | Estado | Evidencia |
|----------|--------|-----------|
| Fuente oficial identificada | ✅ | ESRU-EMOVI 2023 (Centro de Estudios Espinosa Yglesias) |
| Documentación disponible | ✅ | Diccionario ESRU EMOVI 2023.xlsx |
| Tamaño muestral plausible | ✅ | 17,843 observaciones |
| Variables coinciden con codebook | ✅ | variable_roles.yaml documenta mapeo completo |

### 1.2 Veredicto: ✅ AUTÉNTICO

---

## 2. Rigor Metodológico: ✅ Excelente

- Framework Roemer bien implementado
- Múltiples métodos (ctree, cforest, RF, XGBoost)
- Caveats de interpretación añadidos
- Bootstrap CIs implementados

---

## 3. Reproducibilidad: ⚠️ Bueno

### Fortalezas
- Seeds documentados (config.yaml)
- Configuración externalizada
- Documentación completa

### Issues a corregir
- Falta renv.lock / requirements.txt
- Variable p112 (skin_tone) SHAP = 0
- Sensitivity analysis no ejecutado

---

## 4. Resultados IOp

| Método | IOp (Gini) | IOp (R²) |
|--------|------------|----------|
| Decision Tree | 55.4% | 28.3% |
| Random Forest | 52.6% | 25.9% |
| XGBoost | 53.5% | 34.5% |

### Top Circunstancias (SHAP)
1. Sexo: 21.7%
2. Región: 14.8%
3. Educación madre: 12.9%
4. Educación padre: 12.5%
5. Cohorte: 12.4%

---

## 5. Próximos Pasos

1. [ ] Enriquecer con análisis de procesos culturales (Lamont et al.)
2. [ ] Corregir issues de reproducibilidad
3. [ ] Ejecutar sensitivity analysis
4. [ ] Auditoría final para calificación "Excelente"

---

*Generado con skill: academic-research*

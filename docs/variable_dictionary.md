# Variable Dictionary - ESRU-EMOVI 2023

This document describes the variables used in the IOp analysis. Update the source variable names after examining the EMOVI codebook.

## 1. Outcome Variables

### Primary Outcomes

| Analysis Variable | Description | Source Variable | Type | Notes |
|-------------------|-------------|-----------------|------|-------|
| `income_decile` | Current household income decile (1-10) | TBD | Ordinal | Main outcome |
| `ln_income` | Log of household income | TBD | Continuous | Alternative |
| `education_years` | Years of completed schooling | TBD | Continuous | Human capital outcome |

### Secondary Outcomes

| Analysis Variable | Description | Source Variable | Type | Notes |
|-------------------|-------------|-----------------|------|-------|
| `wealth_index` | Asset-based wealth score | Constructed | Continuous | PCA of assets |
| `occupation_prestige` | ISEI occupational prestige | TBD | Continuous | Labor market outcome |
| `social_class_subj` | Self-perceived social class | TBD | Ordinal 1-10 | Subjective outcome |

## 2. Circumstance Variables

### Parental Background

| Analysis Variable | Description | Source Variable | Type | Notes |
|-------------------|-------------|-----------------|------|-------|
| `father_education` | Father's years of schooling at age 14 | TBD | Continuous | Key circumstance |
| `mother_education` | Mother's years of schooling at age 14 | TBD | Continuous | Key circumstance |
| `father_occupation` | Father's occupation at age 14 | TBD | Categorical | ISCO-based |
| `mother_occupation` | Mother's occupation at age 14 | TBD | Categorical | Often missing |
| `parent_class_origin` | Parental social class at age 14 | TBD | Categorical | Summary measure |

### Household of Origin (at Age 14)

| Analysis Variable | Description | Source Variable | Type | Notes |
|-------------------|-------------|-----------------|------|-------|
| `household_wealth_14` | Asset index at age 14 | Constructed | Continuous | Retrospective |
| `housing_quality_14` | Housing conditions at age 14 | Constructed | Continuous | Floor/walls/roof |
| `n_books_14` | Books in household at age 14 | TBD | Ordinal | Cultural capital |
| `n_siblings` | Number of siblings | TBD | Continuous | Resource dilution |
| `birth_order` | Birth order among siblings | TBD | Continuous | First/middle/last |

### Demographics

| Analysis Variable | Description | Source Variable | Type | Notes |
|-------------------|-------------|-----------------|------|-------|
| `sex` | Biological sex | TBD | Binary | Male/Female |
| `ethnicity` | Indigenous heritage | TBD | Categorical | Based on language/self-ID |
| `skin_tone` | Skin tone (PERLA scale) | TBD | Ordinal 1-11 | Colorism measure |
| `birth_region` | Region of birth | TBD | Categorical | 5 regions |
| `birth_cohort` | Birth decade | Derived | Categorical | 1950s-1990s |
| `rural_urban_14` | Rural/urban at age 14 | TBD | Binary | Geographic origin |

### Financial Background

| Analysis Variable | Description | Source Variable | Type | Notes |
|-------------------|-------------|-----------------|------|-------|
| `financial_inclusion_14` | Parents' financial access | TBD | Categorical | From inclusion module |
| `parent_savings_14` | Parents had savings | TBD | Binary | From inclusion module |

## 3. Effort Variables

| Analysis Variable | Description | Source Variable | Type | Notes |
|-------------------|-------------|-----------------|------|-------|
| `own_education` | Respondent's education | TBD | Categorical | May be endogenous |
| `hours_worked` | Weekly work hours | TBD | Continuous | Current effort |
| `migration` | Migrated from birth region | TBD | Binary | Geographic mobility |
| `formal_employment` | Formal vs informal work | TBD | Binary | Labor market status |

**Note on effort**: Following Roemer, effort correlated with circumstances may itself be considered circumstance. We run sensitivity analyses treating education both ways.

## 4. Survey Design Variables

| Variable | Description | Source Variable | Notes |
|----------|-------------|-----------------|-------|
| `weight` | Survey expansion factor | TBD | For weighted estimates |
| `strata` | Stratification variable | TBD | For SE estimation |
| `cluster` | Primary sampling unit | TBD | For SE estimation |
| `household_id` | Household identifier | TBD | For merging |

## 5. Constructed Indices

### Wealth Index (at age 14)

**Method**: Principal Component Analysis on retrospective asset ownership

**Candidate items:**
- Refrigerator at age 14
- Car at age 14
- Television at age 14
- Telephone at age 14
- Indoor plumbing
- etc.

**Output**: First principal component, standardized to 0-100 scale

### Housing Quality Index

**Method**: Sum of quality scores for:
- Floor material (dirt=1, cement=2, tile/wood=3)
- Wall material (waste=1, adobe=2, brick=3)
- Roof material (waste=1, lamina=2, concrete=3)

**Output**: Standardized to 0-100 scale

### Birth Cohort

**Derivation**: From birth year
```
1950-1959 → "1950s"
1960-1969 → "1960s"
1970-1979 → "1970s"
1980-1989 → "1980s"
1990-1999 → "1990s"
```

## 6. Variable Updates Needed

After examining the EMOVI 2023 codebook, update the following:

- [ ] Outcome variable names
- [ ] Parental education variables
- [ ] Parental occupation variables
- [ ] Demographic variables (sex, ethnicity, region)
- [ ] Household asset variables (for wealth index)
- [ ] Survey design variables

## 7. Missing Data Patterns

Document expected missingness:

| Variable Category | Expected Missingness | Strategy |
|-------------------|---------------------|----------|
| Income | 5-10% | Multiple imputation or complete case |
| Parental education | 10-15% | Median imputation |
| Father's occupation | 15-20% | Mode imputation or separate category |
| Skin tone | 5-10% | Median imputation |

## 8. References

- EMOVI 2023 Codebook: `data/codebook/`
- Survey methodology: `data/codebook/metodologia/`
- Questionnaire: `data/codebook/cuestionario/`

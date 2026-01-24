# Guide for Eduardo: Inequality of Opportunity Project

This document explains the IOp analysis project in plain language, providing context for the methodology and code.

---

## KEY RESULTS (EMOVI 2023)

| Metric | Value | Interpretation |
|--------|-------|----------------|
| **IOp Share (Random Forest)** | **52.6%** | Over half of income inequality is due to circumstances |
| IOp Share (Decision Tree) | 55.4% | Interpretable partition into 58 types |
| IOp Share (Gradient Boosting) | 56.8% | Most predictive model |
| 5-Fold CV | 51.5% ± 1.7% | Robust estimate with uncertainty |

### Top Circumstances Driving Inequality:
1. **Mother's education** (24.5%) - Most important factor
2. **Region at age 14** (20.5%) - Geographic disparities
3. **Sex** (19.4%) - Gender inequality
4. **Father's education** (11.2%) - Parental background
5. **Rural/urban at age 14** (7.9%) - Urban advantage

**Comparison with literature**: Monroy-Gómez-Franco (2023) found IOp ≥ 48% using EMOVI 2017, which is consistent with our findings of ~52-57%.

---

## Table of Contents

1. [What is Inequality of Opportunity?](#what-is-inequality-of-opportunity)
2. [The Roemer Framework](#the-roemer-framework)
3. [Our Methodology](#our-methodology)
4. [Understanding the Code](#understanding-the-code)
5. [Key Results to Look For](#key-results-to-look-for)
6. [Common Questions](#common-questions)

---

## What is Inequality of Opportunity?

**Inequality of Opportunity (IOp)** measures how much of the inequality we observe in society is due to factors people cannot control—things like:

- Who your parents are (parental education, occupation)
- Where you were born (region, urban/rural)
- Your demographic characteristics (sex, ethnicity, skin tone)
- Your family's economic situation when you were a child

These are called **circumstances**. The key insight is:

> If two people have the same circumstances but different outcomes, that's "fair" inequality (due to effort, luck, choices).
>
> If two people have different outcomes *because* of their circumstances, that's "unfair" inequality—Inequality of Opportunity.

**IOp Share** = (Inequality due to circumstances) / (Total inequality)

For example, if IOp = 45%, it means 45% of income inequality is due to circumstances outside individual control.

---

## The Roemer Framework

John Roemer's framework (which we follow) works like this:

### 1. Define "Types"

A **type** is a group of people who share the same circumstances. For example:
- Type 1: Males, indigenous, father with primary education, born in the South
- Type 2: Females, non-indigenous, father with university education, born in the North
- etc.

### 2. Calculate Type Means

For each type, calculate the average outcome (e.g., average income). The differences between these averages represent **inequality due to circumstances**.

### 3. Measure IOp

IOp = How much total inequality is explained by differences *between* types (vs. differences *within* types).

---

## Our Methodology

### Why Conditional Inference Trees?

Instead of manually creating types (which would be arbitrary), we use **machine learning** to find the best way to group people based on their circumstances.

**Conditional Inference Trees (ctree)** automatically:
1. Find which circumstances matter most
2. Create optimal groupings (types)
3. Provide statistical tests for each split

This is the approach recommended by Brunori et al. (2023) and used by Monroy-Gómez-Franco (2023) for Mexico.

### The Analysis Pipeline

```
Raw Data → Clean/Preprocess → Fit ctree → Calculate IOp Metrics
                                    ↓
                              Fit cforest → Variable Importance
                                    ↓
                              XGBoost → SHAP (comparison)
```

1. **ctree**: Creates a single tree that partitions people into types
2. **cforest**: Creates 500 trees for more stable results (like a "wisdom of crowds")
3. **XGBoost + SHAP**: A different method for comparison and additional insights

---

## Understanding the Code

### Configuration Files

**`config/config.yaml`**: Controls the analysis
```yaml
seeds:
  global: 42      # For reproducibility
cv:
  outer_folds: 5  # 5-fold cross-validation
ctree:
  maxdepth: 6     # Maximum tree depth
```

**`config/variable_roles.yaml`**: Maps survey variables to their roles
```yaml
outcomes:
  - income_decile
circumstances:
  parental:
    - father_education
    - mother_education
  demographic:
    - sex
    - ethnicity
```

### R Scripts (in order)

| Script | Purpose |
|--------|---------|
| `00_setup.R` | Load packages, set seeds |
| `01_load_validate.R` | Import EMOVI data, check quality |
| `02_preprocess.R` | Clean data, recode variables |
| `03_ctree_model.R` | Fit conditional inference tree |
| `04_cforest_model.R` | Fit forest, compute variable importance |
| `05_iop_metrics.R` | Calculate IOp indices |
| `06_interpretability.R` | PDP, ICE plots |

### Python Scripts

| Script | Purpose |
|--------|---------|
| `xgboost_benchmark.py` | Alternative model with SHAP explanations |
| `comparison_report.py` | Compare ctree vs XGBoost results |

### Notebooks

| Notebook | Purpose |
|----------|---------|
| `01_eda.Rmd` | Explore the data |
| `02_modeling.Rmd` | Run full analysis |
| `03_results.Rmd` | Final figures and tables |

---

## Key Results to Look For

### 1. IOp Share

The main result! Look in `outputs/tables/iop_main_results.csv`:

| Metric | Interpretation |
|--------|----------------|
| IOp Share (Gini) | % of Gini inequality due to circumstances |
| IOp Share (MLD) | % of Mean Log Deviation due to circumstances |
| IOp Share (R²) | Variance explained by circumstances |

**Benchmark**: Previous studies for Mexico find IOp around 40-50%.

### 2. Variable Importance

Which circumstances matter most? Look in `outputs/tables/varimp_bootstrap_ci.csv`:

```
Variable            Mean_Importance    95% CI
father_education    0.0234            [0.018, 0.029]
skin_tone           0.0189            [0.014, 0.024]
birth_region        0.0156            [0.011, 0.021]
...
```

Higher importance = that circumstance explains more of the outcome differences.

### 3. Tree Plot

The ctree visualization (`outputs/figures/ctree_final.png`) shows:
- Which circumstances create the splits
- How the sample is divided into types
- Outcome distributions for each type

### 4. SHAP Summary

From XGBoost (`outputs/figures/shap_summary.png`):
- Feature importance
- Direction of effects (does higher parental education increase or decrease your income?)
- Interactions between circumstances

---

## Common Questions

### Q: What's the difference between ctree and XGBoost?

| Aspect | ctree | XGBoost |
|--------|-------|---------|
| Transparency | High - you can see the tree | Low - "black box" |
| Statistical tests | Built-in | None |
| Predictive accuracy | Good | Often better |
| Interpretability | Tree visualization | SHAP values |

We use both for robustness—if they agree, we're more confident.

### Q: Why multiple IOp measures (Gini, MLD, R²)?

Different measures capture different aspects of inequality:
- **Gini**: Sensitive to the middle of the distribution
- **MLD**: Sensitive to the bottom (useful for poverty analysis)
- **R²**: Easy to interpret (% of variance explained)

If they all point in the same direction, our results are robust.

### Q: What if a circumstance has high importance but wide confidence intervals?

This means the importance is uncertain. Could be:
- Not enough data
- High correlation with other circumstances
- True effect varies across the population

Focus on circumstances with high importance AND narrow CIs.

### Q: How do I update the analysis for different outcomes?

1. Edit `config/variable_roles.yaml` to change the outcome variable
2. Re-run the pipeline from `02_preprocess.R`

### Q: The code gives an error about missing variables

The variable names in the config files are **placeholders**. You need to:
1. Check the data dictionary (`data/raw/emovi/Diccionario ESRU EMOVI 2023.xlsx`)
2. Update `config/variable_roles.yaml` with actual EMOVI variable names
3. Re-run the pipeline

---

## Next Steps

1. **Review the EDA notebook** (`notebooks/01_eda.Rmd`) to understand the data
2. **Update variable mappings** in `config/variable_roles.yaml`
3. **Run the modeling pipeline** and examine results
4. **Compare with Monroy-Gómez-Franco (2023)** results for validation

---

## Getting Help

- **R packages**: See `environment.yml` for versions
- **Methodology**: See `docs/methodology.md`
- **Data dictionary**: See `data/codebook/`

---

*This guide was created to help you navigate the IOp analysis project. Feel free to modify the code and analysis as needed for your research goals.*

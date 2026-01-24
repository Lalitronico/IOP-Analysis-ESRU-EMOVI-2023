# Methodology: Inequality of Opportunity Analysis

## 1. Theoretical Framework

### 1.1 Roemer's Equality of Opportunity

Following Roemer (1998) and Roemer & Trannoy (2016), we distinguish between:

- **Circumstances (C)**: Factors beyond individual control
  - Parental background (education, occupation, wealth)
  - Demographics (sex, ethnicity, region of birth)
  - Family structure (number of siblings, birth order)

- **Effort (E)**: Factors within individual control
  - Own education (partially endogenous)
  - Work hours, job search intensity
  - Migration decisions

### 1.2 The IOp Measure

Total outcome inequality can be decomposed as:

```
Total Inequality = IOp (between types) + Residual (within types)
```

**IOp Share** = IOp / Total Inequality

This represents the fraction of inequality attributable to circumstances.

### 1.3 Ex-Ante vs Ex-Post

We use the **ex-ante** approach:
- Measure inequality of *expected* outcomes across types
- Each type's expected outcome = mean outcome for that type
- IOp = inequality of these type means

## 2. Empirical Strategy

### 2.1 Conditional Inference Trees (ctree)

**Why trees?** They solve the "curse of dimensionality" in IOp measurement. With many circumstance variables, the number of possible types explodes. Trees automatically select relevant circumstances and create optimal partitions.

**The ctree algorithm** (Hothorn et al., 2006):

1. Test all possible splits on all circumstances
2. Use permutation tests to assess statistical significance
3. Select the split with lowest p-value (if below threshold)
4. Recursively partition until stopping criteria are met

**Key parameters:**
- `mincriterion`: Significance level for splits (0.95 = only splits with p < 0.05)
- `maxdepth`: Maximum tree depth (prevents overfitting)
- `minsplit`: Minimum observations required to attempt a split
- `minbucket`: Minimum observations in terminal nodes

### 2.2 Conditional Inference Forests (cforest)

**Why forests?** Single trees can be unstable. Small changes in data can lead to different tree structures. Forests provide:
- More stable variable importance estimates
- Bootstrap confidence intervals
- Better out-of-sample predictions

**The cforest algorithm** (Strobl et al., 2007):

1. Draw B bootstrap samples
2. Fit a ctree to each sample
3. Aggregate predictions across all trees
4. Compute permutation-based variable importance

**Conditional variable importance** handles correlated predictors by permuting within strata defined by other predictors.

### 2.3 IOp Metrics

#### Gini-based IOp

```
IOp_Gini = Gini(μ_types) / Gini(Y)
```

Where μ_types is the vector of type means.

#### MLD-based IOp (Theil L)

```
IOp_MLD = MLD(μ_types) / MLD(Y)
```

MLD is more sensitive to inequality at the bottom of the distribution.

#### R²-based IOp

```
IOp_R² = Var(μ_types) / Var(Y)
```

Interpretable as "variance explained by circumstances."

### 2.4 Inference

**Bootstrap confidence intervals:**

1. Draw B bootstrap samples from data
2. For each sample:
   - Fit ctree/cforest
   - Calculate IOp metric
3. Compute percentile CIs from bootstrap distribution

**Standard**: B = 100 replications, 95% CIs

## 3. XGBoost Benchmark

### 3.1 Why XGBoost?

- Often achieves higher predictive accuracy
- SHAP provides individual-level explanations
- Different algorithmic approach serves as robustness check

### 3.2 SHAP Values

SHAP (SHapley Additive exPlanations) decomposes each prediction:

```
f(x) = φ_0 + Σ φ_i
```

Where φ_i is the contribution of feature i to that prediction.

**Key SHAP outputs:**
- Mean |SHAP| = global feature importance
- SHAP dependence plots = feature effects
- Individual SHAP values = local explanations

## 4. Sensitivity Analyses

### 4.1 Circumstance Set Variations

| Set | Variables | Purpose |
|-----|-----------|---------|
| Minimal | Parent education, sex, region | Lower bound (likely) |
| Standard | + occupation, ethnicity, skin tone | Main specification |
| Extended | + all available circumstances | Upper bound (possible over-control) |

### 4.2 Outcome Robustness

- Primary: Income decile
- Secondary: Log income, wealth index, education years

### 4.3 Subgroup Analysis

- By region (North, Center, South)
- By gender
- By birth cohort (generational trends)

## 5. Data Requirements

### 5.1 Outcome Variables

- Must be continuous or ordinal
- Preferably measured at adult age
- Should reflect long-term welfare (not transitory shocks)

### 5.2 Circumstance Variables

- Must be **determined before age of responsibility** (~18)
- Should be **exogenous to individual effort**
- Examples: parental characteristics, region of birth, demographics at birth

### 5.3 Sample Restrictions

- Adults only (18+)
- Exclude top/bottom 1% of income (trim outliers)
- Complete cases on key circumstances (or impute)

## 6. Interpretation Guidelines

### 6.1 IOp Share

| IOp Share | Interpretation |
|-----------|----------------|
| < 20% | Low inequality of opportunity |
| 20-40% | Moderate IOp |
| 40-60% | High IOp (common in Latin America) |
| > 60% | Very high IOp |

### 6.2 Variable Importance

Importance reflects **marginal contribution** to explaining outcomes, conditional on other circumstances. High importance doesn't necessarily mean high policy relevance—consider feasibility of intervention.

### 6.3 Caveats

1. **Lower bound**: We likely underestimate IOp because:
   - Not all circumstances are measured
   - Effort may be correlated with unmeasured circumstances

2. **Measurement error**: Survey recall of circumstances at age 14 may be imprecise

3. **Selectivity**: Working-age sample may not represent full population

## 7. References

- Brunori, P., Ferrara, D., & Guiliano, A. (2023). Regression trees and forests for inequality of opportunity. *Scandinavian Journal of Economics*.

- Hothorn, T., Hornik, K., & Zeileis, A. (2006). Unbiased recursive partitioning: A conditional inference framework. *Journal of Computational and Graphical Statistics*.

- Roemer, J. E. (1998). *Equality of Opportunity*. Harvard University Press.

- Roemer, J. E., & Trannoy, A. (2016). Equality of opportunity: Theory and measurement. *Journal of Economic Literature*.

- Strobl, C., Boulesteix, A.-L., Zeileis, A., & Hothorn, T. (2007). Bias in random forest variable importance measures. *BMC Bioinformatics*.

- Monroy-Gómez-Franco, L. (2023). A note on ex-ante inequality of opportunity across Mexican regions. *Economics Bulletin*.

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

### 6.3 Critical Caveats

#### 6.3.1 Association vs Causation

> **WARNING**: IOp analysis measures *association*, NOT causation.

IOp estimates tell us how much outcome variation is *associated with* circumstances, not how much would change if we intervened on circumstances. For example:

- Finding that parental education "explains" 15% of income inequality does NOT mean that increasing parental education by one level would reduce inequality by 15%
- High importance of skin tone does NOT mean that changing skin tone would change outcomes

**Why this matters:**
- Circumstances may proxy for unmeasured factors
- Reverse causation is possible (e.g., high-earning parents invest more in children's appearance)
- General equilibrium effects could change relationships

**Recommended language:**
- Use: "is associated with", "correlates with", "predicts"
- Avoid: "causes", "affects", "leads to", "is responsible for"

#### 6.3.2 SHAP vs Shapley IOp Decomposition

> **IMPORTANT**: SHAP feature importance ≠ Shapley decomposition of inequality.

These are conceptually different methods:

| Aspect | SHAP (ML Explainability) | Shapley IOp Decomposition |
|--------|--------------------------|---------------------------|
| **What it measures** | Feature contribution to individual predictions | Circumstance contribution to aggregate inequality |
| **Unit of analysis** | Individual observation | Population distribution |
| **Question answered** | "Why did person X get predicted value Y?" | "How much does circumstance C contribute to total IOp?" |
| **Reference** | Lundberg & Lee (2017) | Ferreira & Gignoux (2011) |

SHAP values tell us which features are important for *prediction*, not which circumstances contribute most to *inequality*. A circumstance can be highly predictive but contribute little to inequality if it affects everyone similarly.

**For proper Shapley decomposition of inequality:**
- Compute IOp for all subsets of circumstances
- Calculate each circumstance's marginal contribution
- Average over all possible orderings
- Use Ferreira & Gignoux (2011) methodology

#### 6.3.3 Lower Bound Interpretation

Our IOp estimates are **lower bounds** because:

1. **Unmeasured circumstances**: Many circumstances are unobserved (parental health, early childhood nutrition, neighborhood effects, etc.)

2. **Effort endogeneity**: What we call "effort" (education choices, work intensity) may itself be shaped by circumstances

3. **Measurement error**: Circumstances measured retrospectively (at age 14) contain recall error, attenuating estimates

#### 6.3.4 Cultural Process Interpretation (Optional Framework)

Following Lamont, Beljean & Clair (2014), circumstances can be interpreted through cultural processes:

| Circumstance | Cultural Process | Mechanism |
|--------------|------------------|-----------|
| Indigenous language | Racialization + Stigmatization | Ethnic boundary marking |
| Skin tone | Racialization | Colorism, visual categorization |
| Parental education | Standardization | Credential as merit signal |
| Parental occupation | Evaluation | Occupational prestige hierarchy |
| Rural origin | Stigmatization | Urban/rural status divide |
| Sex | Identification (gender) | Gender role expectations |

This framework enriches quantitative findings by connecting them to sociological mechanisms, but should be clearly marked as *interpretive* rather than causal.

#### 6.3.5 Policy Implications Caveat

High IOp does NOT automatically imply that policies targeting specific circumstances will be effective:

1. **Feasibility**: Some circumstances cannot be changed (sex, ethnicity, birth region)
2. **Indirect effects**: Policies may need to target discrimination rather than circumstances themselves
3. **General equilibrium**: Large-scale interventions may change the relationships we observe
4. **Trade-offs**: Reducing IOp may have other costs (efficiency, fiscal, political)

**Recommended approach:**
- IOp analysis identifies *where* inequality is concentrated
- Separate causal analysis is needed to identify *effective interventions*
- Policy should target mechanisms, not circumstances directly

## 7. References

### Inequality of Opportunity

- Brunori, P., Ferrara, D., & Guiliano, A. (2023). Regression trees and forests for inequality of opportunity. *Scandinavian Journal of Economics*.

- Ferreira, F. H., & Gignoux, J. (2011). The measurement of inequality of opportunity: Theory and an application to Latin America. *Review of Income and Wealth*, 57(4), 622-657.

- Monroy-Gómez-Franco, L. (2023). A note on ex-ante inequality of opportunity across Mexican regions. *Economics Bulletin*.

- Roemer, J. E. (1998). *Equality of Opportunity*. Harvard University Press.

- Roemer, J. E., & Trannoy, A. (2016). Equality of opportunity: Theory and measurement. *Journal of Economic Literature*, 54(4), 1288-1332.

### Tree-Based Methods

- Hothorn, T., Hornik, K., & Zeileis, A. (2006). Unbiased recursive partitioning: A conditional inference framework. *Journal of Computational and Graphical Statistics*, 15(3), 651-674.

- Strobl, C., Boulesteix, A.-L., Zeileis, A., & Hothorn, T. (2007). Bias in random forest variable importance measures. *BMC Bioinformatics*, 8(1), 25.

### Machine Learning Interpretability

- Lundberg, S. M., & Lee, S.-I. (2017). A unified approach to interpreting model predictions. *Advances in Neural Information Processing Systems*, 30.

### Cultural Processes

- Lamont, M., Beljean, S., & Clair, M. (2014). What is missing? Cultural processes and causal pathways to inequality. *Socio-Economic Review*, 12(3), 573-608.

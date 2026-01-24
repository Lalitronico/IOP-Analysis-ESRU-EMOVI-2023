# Inequality of Opportunity Analysis - ESRU-EMOVI 2023

This project measures Inequality of Opportunity (IOp) in Mexico using the ESRU-EMOVI 2023 social mobility survey. Following the Roemer framework, we separate "circumstances" (factors outside individual control) from "effort" variables and quantify how much outcome inequality is attributable to circumstances.

## Quick Start

### 1. Set Up Environment

```bash
# Create conda environment with R + Python
conda env create -f environment.yml
conda activate iop-analysis
```

### 2. Run Analysis Pipeline

```bash
# Step 1: Load and validate data
Rscript src/R/01_load_validate.R

# Step 2: Preprocess data
Rscript src/R/02_preprocess.R

# Step 3: Fit ctree model
Rscript src/R/03_ctree_model.R

# Step 4: Fit cforest and compute variable importance
Rscript src/R/04_cforest_model.R

# Step 5: Calculate IOp metrics
Rscript src/R/05_iop_metrics.R

# Step 6: XGBoost benchmark (Python)
python src/python/xgboost_benchmark.py
```

### 3. Generate Reports

```bash
# Render R Markdown notebooks
Rscript -e "rmarkdown::render('notebooks/01_eda.Rmd')"
Rscript -e "rmarkdown::render('notebooks/02_modeling.Rmd')"
Rscript -e "rmarkdown::render('notebooks/03_results.Rmd')"
```

## Project Structure

```
inequality-of-opportunity/
├── config/
│   ├── config.yaml           # Paths, seeds, hyperparameters
│   └── variable_roles.yaml   # Circumstance/outcome mapping
├── data/
│   ├── raw/                  # Original EMOVI files
│   ├── processed/            # Cleaned datasets
│   └── codebook/             # Documentation
├── src/
│   ├── R/                    # R scripts (ctree, cforest, IOp)
│   └── python/               # Python scripts (XGBoost, SHAP)
├── notebooks/                # R Markdown analysis notebooks
├── outputs/
│   ├── figures/              # Generated plots
│   ├── tables/               # Results tables
│   └── models/               # Saved model objects
├── docs/                     # Methodology documentation
└── tests/                    # Unit tests
```

## Methodology

We use **Conditional Inference Trees and Forests** (Brunori et al., 2023) as the primary method:

1. **ctree**: Partitions sample into "types" based on circumstances
2. **cforest**: Provides stable variable importance with confidence intervals
3. **IOp Metrics**: Gini-based, MLD-based, and R² measures

**XGBoost + SHAP** serves as a benchmark for comparison.

See `docs/methodology.md` for detailed methodology.

## Key References

- Brunori, P., Ferrara, D., & Guiliano, A. (2023). Regression trees and forests for IOp. *Scandinavian Journal of Economics*.
- Roemer, J. E., & Trannoy, A. (2016). Equality of opportunity: Theory and measurement. *Journal of Economic Literature*.
- Monroy-Gómez-Franco, L. (2023). Ex-ante IOp across Mexican regions. *Economics Bulletin*.

## Data

This project uses the **ESRU-EMOVI 2023** survey from CEEY (Centro de Estudios Espinosa Yglesias).

- [EMOVI 2023 Information](https://ceey.org.mx/encuesta-esru-emovi-2023/)
- Data files should be placed in `data/raw/`

## For Eduardo

See `FOR_EDUARDO.md` for a plain-language guide to the project.

## License

[Add appropriate license]

## Contact

[Add contact information]

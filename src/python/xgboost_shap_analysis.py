"""
xgboost_shap_analysis.py - XGBoost with SHAP Analysis
===============================================================================
Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
Purpose: Run XGBoost model with SHAP explanations for interpretability
===============================================================================
"""

import matplotlib
matplotlib.use('Agg')

import os
import sys
import numpy as np
import pandas as pd
from pathlib import Path
import warnings
warnings.filterwarnings('ignore')

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT = Path(__file__).parent.parent.parent
DATA_PATH = PROJECT_ROOT / "data" / "raw" / "emovi" / "Data" / "entrevistado_2023.dta"
OUTPUT_FIGURES = PROJECT_ROOT / "outputs" / "figures"
OUTPUT_TABLES = PROJECT_ROOT / "outputs" / "tables"
OUTPUT_MODELS = PROJECT_ROOT / "outputs" / "models"

# Ensure output directories exist
OUTPUT_FIGURES.mkdir(parents=True, exist_ok=True)
OUTPUT_TABLES.mkdir(parents=True, exist_ok=True)
OUTPUT_MODELS.mkdir(parents=True, exist_ok=True)

# Variable configuration (same as iop_analysis.py)
OUTCOME_VAR = 'ingc_pc'
CIRCUMSTANCE_VARS = ['educp', 'educm', 'clasep', 'sexo', 'p111', 'p112', 'region_14', 'cohorte', 'p21']
WEIGHT_VAR = 'factor'

# Variable labels for better visualization
VAR_LABELS = {
    'educm': "Mother's Education",
    'educp': "Father's Education",
    'clasep': "Father's Occupation",
    'sexo': 'Sex',
    'p111': 'Indigenous Language',
    'p112': 'Skin Tone',
    'region_14': 'Region at 14',
    'cohorte': 'Birth Cohort',
    'p21': 'Rural/Urban at 14'
}

# =============================================================================
# Data Loading
# =============================================================================

def load_and_prepare_data():
    """Load EMOVI data and prepare for XGBoost."""
    print("Loading EMOVI 2023 data...")

    df = pd.read_stata(DATA_PATH, convert_categoricals=False)
    print(f"  Loaded {len(df):,} observations")

    # Select relevant variables
    all_vars = [OUTCOME_VAR] + CIRCUMSTANCE_VARS + [WEIGHT_VAR]
    df = df[all_vars].copy()

    # Transform outcome (log of income)
    df['ln_income'] = np.log(df[OUTCOME_VAR].replace(0, np.nan))

    # Drop missing values
    df_clean = df.dropna()
    print(f"  Complete cases: {len(df_clean):,}")

    return df_clean


def prepare_features(df):
    """Prepare features for XGBoost (handle categorical encoding)."""
    X = df[CIRCUMSTANCE_VARS].copy()
    y = df['ln_income'].copy()
    weights = df[WEIGHT_VAR].copy()

    # Convert all to numeric (already should be, but ensure)
    for col in X.columns:
        X[col] = pd.to_numeric(X[col], errors='coerce')

    return X, y, weights


# =============================================================================
# XGBoost Model
# =============================================================================

def train_xgboost(X, y, tune=False):
    """Train XGBoost model with optional hyperparameter tuning."""
    import xgboost as xgb
    from sklearn.model_selection import cross_val_score, KFold

    if tune:
        print("\nTuning XGBoost hyperparameters with Optuna...")
        try:
            import optuna
            optuna.logging.set_verbosity(optuna.logging.WARNING)

            def objective(trial):
                params = {
                    'n_estimators': trial.suggest_int('n_estimators', 100, 400),
                    'max_depth': trial.suggest_int('max_depth', 3, 7),
                    'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.15, log=True),
                    'subsample': trial.suggest_float('subsample', 0.6, 0.95),
                    'colsample_bytree': trial.suggest_float('colsample_bytree', 0.6, 0.95),
                    'min_child_weight': trial.suggest_int('min_child_weight', 1, 7),
                    'random_state': 42,
                    'n_jobs': -1
                }
                model = xgb.XGBRegressor(**params)
                cv = KFold(n_splits=5, shuffle=True, random_state=42)
                scores = cross_val_score(model, X, y, cv=cv, scoring='r2')
                return scores.mean()

            study = optuna.create_study(direction='maximize')
            study.optimize(objective, n_trials=30, show_progress_bar=True)
            best_params = study.best_params
            best_params['random_state'] = 42
            best_params['n_jobs'] = -1
            print(f"  Best CV R²: {study.best_value:.4f}")
            print(f"  Best params: {best_params}")

        except ImportError:
            print("  Optuna not available, using default parameters")
            best_params = {
                'n_estimators': 300,
                'max_depth': 5,
                'learning_rate': 0.05,
                'subsample': 0.8,
                'colsample_bytree': 0.8,
                'random_state': 42,
                'n_jobs': -1
            }
    else:
        best_params = {
            'n_estimators': 300,
            'max_depth': 5,
            'learning_rate': 0.05,
            'subsample': 0.8,
            'colsample_bytree': 0.8,
            'random_state': 42,
            'n_jobs': -1
        }

    print("\nTraining final XGBoost model...")
    model = xgb.XGBRegressor(**best_params)
    model.fit(X, y)

    # Cross-validation
    cv = KFold(n_splits=5, shuffle=True, random_state=42)
    cv_scores = cross_val_score(model, X, y, cv=cv, scoring='r2')
    print(f"  CV R²: {cv_scores.mean():.4f} ± {cv_scores.std():.4f}")

    return model, best_params, cv_scores


# =============================================================================
# SHAP Analysis
# =============================================================================

def compute_shap_analysis(model, X):
    """Compute SHAP values and generate visualizations."""
    import shap
    import matplotlib.pyplot as plt

    print("\nComputing SHAP values...")
    explainer = shap.TreeExplainer(model)
    shap_values = explainer.shap_values(X)
    print(f"  SHAP values computed for {len(X):,} observations")

    # Rename columns for better visualization
    X_display = X.rename(columns=VAR_LABELS)

    # 1. SHAP Summary Plot (beeswarm)
    print("\nGenerating SHAP summary plot...")
    plt.figure(figsize=(12, 8))
    shap.summary_plot(shap_values, X_display, show=False)
    plt.title("SHAP Summary: Impact of Circumstances on Income", fontsize=14)
    plt.tight_layout()
    plt.savefig(OUTPUT_FIGURES / "shap_summary.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {OUTPUT_FIGURES / 'shap_summary.png'}")

    # 2. SHAP Bar Plot (mean absolute values)
    print("\nGenerating SHAP importance bar plot...")
    plt.figure(figsize=(10, 6))
    shap.summary_plot(shap_values, X_display, plot_type="bar", show=False)
    plt.title("Mean Absolute SHAP Values by Circumstance", fontsize=14)
    plt.tight_layout()
    plt.savefig(OUTPUT_FIGURES / "shap_importance_bar.png", dpi=300, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {OUTPUT_FIGURES / 'shap_importance_bar.png'}")

    # 3. Calculate and save SHAP importance table
    shap_importance = pd.DataFrame({
        'variable': X.columns,
        'variable_label': [VAR_LABELS.get(v, v) for v in X.columns],
        'mean_abs_shap': np.abs(shap_values).mean(axis=0),
        'std_shap': np.abs(shap_values).std(axis=0)
    }).sort_values('mean_abs_shap', ascending=False)

    # Normalize to percentages
    total_shap = shap_importance['mean_abs_shap'].sum()
    shap_importance['importance_pct'] = (shap_importance['mean_abs_shap'] / total_shap * 100).round(2)

    shap_importance.to_csv(OUTPUT_TABLES / "shap_importance.csv", index=False)
    print(f"  Saved: {OUTPUT_TABLES / 'shap_importance.csv'}")

    # 4. Dependence plots for top 3 circumstances
    top_vars = shap_importance.head(3)['variable'].tolist()
    print("\nGenerating SHAP dependence plots for top variables...")

    for var in top_vars:
        plt.figure(figsize=(10, 6))
        var_idx = list(X.columns).index(var)
        shap.dependence_plot(var_idx, shap_values, X_display, show=False)
        plt.title(f"SHAP Dependence: {VAR_LABELS.get(var, var)}", fontsize=14)
        plt.tight_layout()
        plt.savefig(OUTPUT_FIGURES / f"shap_dependence_{var}.png", dpi=300, bbox_inches='tight')
        plt.close()
        print(f"  Saved: {OUTPUT_FIGURES / f'shap_dependence_{var}.png'}")

    return shap_values, shap_importance


# =============================================================================
# IOp Metrics
# =============================================================================

def calculate_iop_xgboost(y_true, y_pred, weights=None):
    """Calculate IOp metrics using XGBoost predictions."""
    from sklearn.metrics import r2_score

    def weighted_gini(x, w=None):
        """Calculate weighted Gini coefficient."""
        if w is None:
            w = np.ones(len(x))
        x = np.array(x)
        w = np.array(w)

        # Sort by x
        sorted_idx = np.argsort(x)
        x_sorted = x[sorted_idx]
        w_sorted = w[sorted_idx]

        # Calculate weighted Gini
        n = len(x)
        cum_w = np.cumsum(w_sorted)
        cum_wx = np.cumsum(w_sorted * x_sorted)

        total_w = cum_w[-1]
        total_wx = cum_wx[-1]

        gini = 1 - 2 * np.sum(cum_wx[:-1] * np.diff(cum_w)) / (total_w * total_wx)
        return max(0, gini)

    # R-squared
    r2 = r2_score(y_true, y_pred)

    # Gini-based IOp
    gini_total = weighted_gini(np.exp(y_true), weights)  # Use original scale for Gini
    gini_between = weighted_gini(np.exp(y_pred), weights)
    iop_gini = gini_between / gini_total if gini_total > 0 else 0

    # Variance-based IOp
    var_total = np.var(y_true)
    var_predicted = np.var(y_pred)
    iop_variance = var_predicted / var_total if var_total > 0 else 0

    return {
        'r2': r2,
        'gini_total': gini_total,
        'gini_between': gini_between,
        'iop_gini': iop_gini,
        'iop_variance': iop_variance
    }


# =============================================================================
# Main Pipeline
# =============================================================================

def main():
    """Run complete XGBoost + SHAP analysis pipeline."""
    print("=" * 70)
    print("XGBoost + SHAP Analysis for Inequality of Opportunity")
    print("ESRU-EMOVI 2023")
    print("=" * 70)

    # Load data
    df = load_and_prepare_data()
    X, y, weights = prepare_features(df)

    # Train XGBoost (set tune=True for hyperparameter optimization)
    model, best_params, cv_scores = train_xgboost(X, y, tune=True)

    # Get predictions
    y_pred = model.predict(X)

    # Calculate IOp metrics
    print("\nCalculating IOp metrics...")
    iop_metrics = calculate_iop_xgboost(y.values, y_pred, weights.values)

    print("\n" + "-" * 50)
    print("XGBoost IOp Results:")
    print("-" * 50)
    print(f"  R² (variance explained):  {iop_metrics['r2']:.4f} ({iop_metrics['r2']*100:.1f}%)")
    print(f"  IOp Share (Gini-based):   {iop_metrics['iop_gini']:.4f} ({iop_metrics['iop_gini']*100:.1f}%)")
    print(f"  IOp Share (Variance):     {iop_metrics['iop_variance']:.4f} ({iop_metrics['iop_variance']*100:.1f}%)")
    print("-" * 50)

    # SHAP analysis
    shap_values, shap_importance = compute_shap_analysis(model, X)

    # Print top circumstances
    print("\n" + "-" * 50)
    print("Top Circumstances by SHAP Importance:")
    print("-" * 50)
    for i, row in shap_importance.head(5).iterrows():
        print(f"  {row['variable_label']:25s} {row['importance_pct']:5.1f}%")
    print("-" * 50)

    # Save XGBoost-specific results
    xgb_results = pd.DataFrame([{
        'Model': 'XGBoost',
        'IOp_Gini': iop_metrics['iop_gini'],
        'IOp_R2': iop_metrics['r2'],
        'CV_R2_mean': cv_scores.mean(),
        'CV_R2_std': cv_scores.std()
    }])
    xgb_results.to_csv(OUTPUT_TABLES / "xgboost_results.csv", index=False)

    # Save model parameters
    params_df = pd.DataFrame([best_params])
    params_df.to_csv(OUTPUT_TABLES / "xgboost_best_params.csv", index=False)

    # Save model
    model.save_model(str(OUTPUT_MODELS / "xgboost_model.json"))
    print(f"\nModel saved: {OUTPUT_MODELS / 'xgboost_model.json'}")

    print("\n" + "=" * 70)
    print("XGBoost + SHAP analysis complete!")
    print("=" * 70)

    return {
        'model': model,
        'iop_metrics': iop_metrics,
        'shap_values': shap_values,
        'shap_importance': shap_importance,
        'cv_scores': cv_scores
    }


if __name__ == "__main__":
    results = main()

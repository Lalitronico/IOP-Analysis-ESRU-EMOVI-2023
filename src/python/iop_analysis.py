"""
iop_analysis.py - Complete IOp Analysis Pipeline in Python
===============================================================================
Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
Purpose: Run full IOp analysis using scikit-learn trees and gradient boosting
===============================================================================
"""

import os
import yaml
import numpy as np
import pandas as pd
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import warnings
warnings.filterwarnings('ignore')

# Use non-interactive backend for matplotlib
import matplotlib
matplotlib.use('Agg')

from sklearn.tree import DecisionTreeRegressor, plot_tree
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.model_selection import cross_val_score, KFold
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import r2_score, mean_squared_error
import matplotlib.pyplot as plt

# ============================================================================
# Configuration
# ============================================================================

os.chdir(r"C:\Users\HP ZBOOK\Desktop\Inequality of Opportunity")

def load_config():
    with open("config/config.yaml", 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)

def load_variable_roles():
    with open("config/variable_roles.yaml", 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)

# ============================================================================
# Data Loading
# ============================================================================

def load_emovi_data():
    """Load EMOVI 2023 data."""
    print("Loading EMOVI 2023 data...")
    df = pd.read_stata("data/raw/emovi/Data/entrevistado_2023.dta",
                       convert_categoricals=False)
    print(f"Loaded: {len(df)} observations, {len(df.columns)} variables")
    return df

# ============================================================================
# Data Preprocessing
# ============================================================================

def prepare_analysis_data(df: pd.DataFrame,
                          outcome_var: str,
                          circumstance_vars: List[str],
                          weight_var: str = 'factor') -> Tuple[pd.DataFrame, pd.Series, pd.Series]:
    """
    Prepare data for IOp analysis.

    Returns:
        X: circumstance variables (encoded)
        y: outcome variable
        weights: survey weights
    """
    print(f"\nPreparing analysis data...")
    print(f"  Outcome: {outcome_var}")
    print(f"  Circumstances: {circumstance_vars}")

    # Check variables exist
    all_vars = [outcome_var] + circumstance_vars + [weight_var]
    missing = [v for v in all_vars if v not in df.columns]
    if missing:
        print(f"  WARNING: Missing variables: {missing}")
        circumstance_vars = [v for v in circumstance_vars if v in df.columns]

    # Select variables
    df_analysis = df[[outcome_var] + circumstance_vars + [weight_var]].copy()

    # Create log income if using income
    if outcome_var == 'ingc_pc':
        df_analysis['ln_ingc_pc'] = np.log(df_analysis['ingc_pc'] + 1)
        outcome_var = 'ln_ingc_pc'

    # Drop missing outcomes
    df_analysis = df_analysis.dropna(subset=[outcome_var])
    print(f"  After dropping NA outcomes: {len(df_analysis)} obs")

    # Encode categorical variables
    label_encoders = {}
    for col in circumstance_vars:
        if col in df_analysis.columns:
            if df_analysis[col].dtype == 'object' or df_analysis[col].nunique() < 20:
                le = LabelEncoder()
                df_analysis[col] = df_analysis[col].fillna(-999)
                df_analysis[col] = le.fit_transform(df_analysis[col].astype(str))
                label_encoders[col] = le
            else:
                df_analysis[col] = df_analysis[col].fillna(df_analysis[col].median())

    X = df_analysis[circumstance_vars]
    y = df_analysis[outcome_var]
    weights = df_analysis[weight_var]

    print(f"  Final dataset: {len(X)} obs, {len(circumstance_vars)} circumstances")

    return X, y, weights, label_encoders

# ============================================================================
# Inequality Metrics
# ============================================================================

def gini(x, weights=None):
    """Calculate Gini coefficient."""
    x = np.array(x)
    x = x[~np.isnan(x)]

    if weights is None:
        weights = np.ones(len(x))
    else:
        weights = np.array(weights)
        weights = weights[~np.isnan(x)]

    # Sort by x
    sorted_idx = np.argsort(x)
    x_sorted = x[sorted_idx]
    w_sorted = weights[sorted_idx]

    # Cumulative sums
    cum_w = np.cumsum(w_sorted)
    cum_wx = np.cumsum(w_sorted * x_sorted)

    # Gini formula
    n = len(x)
    numerator = 2 * np.sum(cum_w * x_sorted * w_sorted) - cum_wx[-1] * cum_w[-1]
    denominator = cum_w[-1] * cum_wx[-1]

    if denominator == 0:
        return 0

    return numerator / denominator

def mld(x, weights=None):
    """Calculate Mean Log Deviation."""
    x = np.array(x)
    x = x[(~np.isnan(x)) & (x > 0)]

    if len(x) == 0:
        return np.nan

    if weights is None:
        weights = np.ones(len(x))
    else:
        weights = np.array(weights)
        weights = weights[(~np.isnan(x)) & (x > 0)]

    weights = weights / weights.sum()
    mu = np.sum(weights * x)

    return np.sum(weights * np.log(mu / x))

def calculate_iop_metrics(y_true, y_pred, weights=None):
    """
    Calculate IOp metrics from predictions.

    Returns dict with:
    - iop_gini: Gini-based IOp share
    - iop_mld: MLD-based IOp share
    - iop_r2: R²-based IOp share
    - gini_total: Total Gini
    - gini_between: Between-type Gini
    """
    y_true = np.array(y_true)
    y_pred = np.array(y_pred)

    # Gini-based
    gini_total = gini(y_true, weights)
    gini_between = gini(y_pred, weights)
    iop_gini = gini_between / gini_total if gini_total > 0 else 0

    # MLD-based (need positive values)
    if np.all(y_true > 0):
        mld_total = mld(y_true, weights)
        mld_between = mld(y_pred, weights)
        iop_mld = mld_between / mld_total if mld_total > 0 else 0
    else:
        mld_total = np.nan
        mld_between = np.nan
        iop_mld = np.nan

    # R²-based
    var_total = np.var(y_true)
    var_between = np.var(y_pred)
    iop_r2 = var_between / var_total if var_total > 0 else 0

    return {
        'iop_gini': iop_gini,
        'iop_mld': iop_mld,
        'iop_r2': iop_r2,
        'gini_total': gini_total,
        'gini_between': gini_between,
        'mld_total': mld_total,
        'mld_between': mld_between,
        'r2': r2_score(y_true, y_pred)
    }

# ============================================================================
# Tree-Based Models
# ============================================================================

def fit_decision_tree(X, y, max_depth=6, min_samples_leaf=50):
    """Fit decision tree for type partition."""
    model = DecisionTreeRegressor(
        max_depth=max_depth,
        min_samples_leaf=min_samples_leaf,
        random_state=42
    )
    model.fit(X, y)
    return model

def fit_random_forest(X, y, n_estimators=200, max_depth=6, min_samples_leaf=30):
    """Fit random forest for stable predictions."""
    model = RandomForestRegressor(
        n_estimators=n_estimators,
        max_depth=max_depth,
        min_samples_leaf=min_samples_leaf,
        random_state=42,
        n_jobs=-1
    )
    model.fit(X, y)
    return model

def fit_gradient_boosting(X, y, n_estimators=200, max_depth=4, learning_rate=0.05):
    """Fit gradient boosting for benchmark."""
    model = GradientBoostingRegressor(
        n_estimators=n_estimators,
        max_depth=max_depth,
        learning_rate=learning_rate,
        random_state=42
    )
    model.fit(X, y)
    return model

# ============================================================================
# Cross-Validation
# ============================================================================

def cross_validate_iop(X, y, model_fn, n_folds=5, seed=42):
    """
    Cross-validate IOp estimates.

    Returns dict with mean and std of IOp metrics across folds.
    """
    kf = KFold(n_splits=n_folds, shuffle=True, random_state=seed)

    iop_results = []

    for train_idx, test_idx in kf.split(X):
        X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
        y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]

        model = model_fn()
        model.fit(X_train, y_train)
        y_pred = model.predict(X_test)

        metrics = calculate_iop_metrics(y_test, y_pred)
        iop_results.append(metrics)

    # Aggregate results
    results_df = pd.DataFrame(iop_results)

    return {
        'mean': results_df.mean().to_dict(),
        'std': results_df.std().to_dict(),
        'all_folds': iop_results
    }

# ============================================================================
# Variable Importance
# ============================================================================

def compute_permutation_importance(model, X, y, n_repeats=10):
    """Compute permutation-based variable importance."""
    from sklearn.inspection import permutation_importance

    result = permutation_importance(
        model, X, y,
        n_repeats=n_repeats,
        random_state=42,
        n_jobs=-1
    )

    importance_df = pd.DataFrame({
        'variable': X.columns,
        'importance_mean': result.importances_mean,
        'importance_std': result.importances_std
    }).sort_values('importance_mean', ascending=False)

    return importance_df

def compute_forest_importance(model, X):
    """Get feature importance from tree-based model."""
    importance_df = pd.DataFrame({
        'variable': X.columns,
        'importance': model.feature_importances_
    }).sort_values('importance', ascending=False)

    return importance_df

# ============================================================================
# Visualization
# ============================================================================

def plot_variable_importance(importance_df, title="Variable Importance", filename=None):
    """Plot variable importance."""
    fig, ax = plt.subplots(figsize=(10, 6))

    importance_df_sorted = importance_df.sort_values('importance', ascending=True)

    ax.barh(importance_df_sorted['variable'], importance_df_sorted['importance'],
            color='steelblue')
    ax.set_xlabel('Importance')
    ax.set_title(title)

    plt.tight_layout()

    if filename:
        plt.savefig(f"outputs/figures/{filename}.png", dpi=300, bbox_inches='tight')
        print(f"Saved: outputs/figures/{filename}.png")

    plt.close()

def plot_iop_decomposition(metrics, filename=None):
    """Plot IOp decomposition."""
    fig, ax = plt.subplots(figsize=(8, 6))

    labels = ['Gini-based', 'MLD-based', 'R²-based']
    values = [metrics['iop_gini'] * 100,
              metrics['iop_mld'] * 100 if not np.isnan(metrics['iop_mld']) else 0,
              metrics['iop_r2'] * 100]

    bars = ax.bar(labels, values, color=['#0072B2', '#009E73', '#D55E00'])

    # Add value labels
    for bar, val in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1,
                f'{val:.1f}%', ha='center', va='bottom', fontsize=12)

    ax.set_ylabel('IOp Share (%)')
    ax.set_title('Inequality of Opportunity Share\n(Percentage of total inequality due to circumstances)')
    ax.set_ylim(0, max(values) * 1.2)

    plt.tight_layout()

    if filename:
        plt.savefig(f"outputs/figures/{filename}.png", dpi=300, bbox_inches='tight')
        print(f"Saved: outputs/figures/{filename}.png")

    plt.close()

def plot_tree_diagram(model, feature_names, filename=None):
    """Plot decision tree."""
    fig, ax = plt.subplots(figsize=(20, 12))

    plot_tree(model, feature_names=feature_names, filled=True, rounded=True,
              fontsize=8, ax=ax, max_depth=3)

    plt.tight_layout()

    if filename:
        plt.savefig(f"outputs/figures/{filename}.png", dpi=300, bbox_inches='tight')
        print(f"Saved: outputs/figures/{filename}.png")

    plt.close()

# ============================================================================
# Main Analysis Pipeline
# ============================================================================

def run_iop_analysis():
    """Run complete IOp analysis pipeline."""

    print("=" * 72)
    print("INEQUALITY OF OPPORTUNITY ANALYSIS - ESRU-EMOVI 2023")
    print("=" * 72)

    # Create output directories
    os.makedirs("outputs/figures", exist_ok=True)
    os.makedirs("outputs/tables", exist_ok=True)
    os.makedirs("outputs/models", exist_ok=True)

    # Load data
    df = load_emovi_data()

    # Load variable configuration
    var_roles = load_variable_roles()

    # Define analysis variables
    outcome_var = 'ingc_pc'  # Will be log-transformed

    # Standard circumstance set
    circumstance_vars = [
        'educp',      # Father's education
        'educm',      # Mother's education
        'clasep',     # Father's occupation
        'sexo',       # Sex
        'p111',       # Indigenous language
        'p112',       # Skin tone
        'region_14',  # Region at 14
        'cohorte',    # Birth cohort
        'p21',        # Rural/urban at 14
    ]

    # Prepare data
    X, y, weights, encoders = prepare_analysis_data(
        df, outcome_var, circumstance_vars
    )

    # =========================================================================
    # 1. Decision Tree (for interpretable type partition)
    # =========================================================================
    print("\n" + "=" * 72)
    print("1. DECISION TREE ANALYSIS")
    print("=" * 72)

    tree_model = fit_decision_tree(X, y, max_depth=6, min_samples_leaf=50)
    tree_pred = tree_model.predict(X)
    tree_metrics = calculate_iop_metrics(y, tree_pred, weights)

    print(f"\nDecision Tree Results:")
    print(f"  Number of leaves (types): {tree_model.get_n_leaves()}")
    print(f"  IOp Share (Gini): {tree_metrics['iop_gini']*100:.2f}%")
    print(f"  IOp Share (R²):   {tree_metrics['iop_r2']*100:.2f}%")

    # Plot tree
    plot_tree_diagram(tree_model, X.columns, "decision_tree")

    # Variable importance
    tree_importance = compute_forest_importance(tree_model, X)
    print(f"\nTop circumstances (Decision Tree):")
    print(tree_importance.head(5).to_string(index=False))

    # =========================================================================
    # 2. Random Forest (for stable estimates)
    # =========================================================================
    print("\n" + "=" * 72)
    print("2. RANDOM FOREST ANALYSIS")
    print("=" * 72)

    rf_model = fit_random_forest(X, y, n_estimators=200, max_depth=6)
    rf_pred = rf_model.predict(X)
    rf_metrics = calculate_iop_metrics(y, rf_pred, weights)

    print(f"\nRandom Forest Results:")
    print(f"  IOp Share (Gini): {rf_metrics['iop_gini']*100:.2f}%")
    print(f"  IOp Share (R²):   {rf_metrics['iop_r2']*100:.2f}%")

    # Variable importance
    rf_importance = compute_forest_importance(rf_model, X)
    print(f"\nTop circumstances (Random Forest):")
    print(rf_importance.head(5).to_string(index=False))

    plot_variable_importance(rf_importance, "Variable Importance (Random Forest)",
                            "varimp_random_forest")

    # =========================================================================
    # 3. Gradient Boosting (benchmark)
    # =========================================================================
    print("\n" + "=" * 72)
    print("3. GRADIENT BOOSTING BENCHMARK")
    print("=" * 72)

    gb_model = fit_gradient_boosting(X, y, n_estimators=200)
    gb_pred = gb_model.predict(X)
    gb_metrics = calculate_iop_metrics(y, gb_pred, weights)

    print(f"\nGradient Boosting Results:")
    print(f"  IOp Share (Gini): {gb_metrics['iop_gini']*100:.2f}%")
    print(f"  IOp Share (R²):   {gb_metrics['iop_r2']*100:.2f}%")

    # Variable importance
    gb_importance = compute_forest_importance(gb_model, X)
    print(f"\nTop circumstances (Gradient Boosting):")
    print(gb_importance.head(5).to_string(index=False))

    plot_variable_importance(gb_importance, "Variable Importance (Gradient Boosting)",
                            "varimp_gradient_boosting")

    # =========================================================================
    # 4. Cross-Validation
    # =========================================================================
    print("\n" + "=" * 72)
    print("4. CROSS-VALIDATION")
    print("=" * 72)

    cv_results = cross_validate_iop(
        X, y,
        model_fn=lambda: RandomForestRegressor(n_estimators=100, max_depth=6,
                                               min_samples_leaf=30, random_state=42),
        n_folds=5
    )

    print(f"\n5-Fold CV Results (Random Forest):")
    print(f"  IOp (Gini): {cv_results['mean']['iop_gini']*100:.2f}% ± {cv_results['std']['iop_gini']*100:.2f}%")
    print(f"  IOp (R²):   {cv_results['mean']['iop_r2']*100:.2f}% ± {cv_results['std']['iop_r2']*100:.2f}%")

    # =========================================================================
    # 5. Summary and Save Results
    # =========================================================================
    print("\n" + "=" * 72)
    print("5. SUMMARY")
    print("=" * 72)

    # Create summary table
    summary_df = pd.DataFrame([
        {'Model': 'Decision Tree', 'IOp_Gini': tree_metrics['iop_gini'],
         'IOp_R2': tree_metrics['iop_r2'], 'N_Types': tree_model.get_n_leaves()},
        {'Model': 'Random Forest', 'IOp_Gini': rf_metrics['iop_gini'],
         'IOp_R2': rf_metrics['iop_r2'], 'N_Types': '-'},
        {'Model': 'Gradient Boosting', 'IOp_Gini': gb_metrics['iop_gini'],
         'IOp_R2': gb_metrics['iop_r2'], 'N_Types': '-'},
        {'Model': 'RF (CV mean)', 'IOp_Gini': cv_results['mean']['iop_gini'],
         'IOp_R2': cv_results['mean']['iop_r2'], 'N_Types': '-'}
    ])

    print("\nIOp Estimates Comparison:")
    print(summary_df.to_string(index=False))

    # Save results
    summary_df.to_csv("outputs/tables/iop_main_results.csv", index=False)
    rf_importance.to_csv("outputs/tables/varimp_random_forest.csv", index=False)
    gb_importance.to_csv("outputs/tables/varimp_gradient_boosting.csv", index=False)

    # Plot IOp decomposition
    plot_iop_decomposition(rf_metrics, "iop_decomposition")

    # Variable importance comparison
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))

    rf_sorted = rf_importance.sort_values('importance', ascending=True)
    axes[0].barh(rf_sorted['variable'], rf_sorted['importance'], color='steelblue')
    axes[0].set_title('Random Forest')
    axes[0].set_xlabel('Importance')

    gb_sorted = gb_importance.sort_values('importance', ascending=True)
    axes[1].barh(gb_sorted['variable'], gb_sorted['importance'], color='darkorange')
    axes[1].set_title('Gradient Boosting')
    axes[1].set_xlabel('Importance')

    plt.suptitle('Variable Importance Comparison', fontsize=14)
    plt.tight_layout()
    plt.savefig("outputs/figures/varimp_comparison.png", dpi=300, bbox_inches='tight')
    plt.close()

    print("\n" + "=" * 72)
    print("ANALYSIS COMPLETE")
    print("=" * 72)
    print(f"\nKey Finding: IOp Share (Random Forest) = {rf_metrics['iop_gini']*100:.1f}%")
    print(f"This means {rf_metrics['iop_gini']*100:.1f}% of income inequality")
    print("is attributable to circumstances outside individual control.")
    print("\nResults saved to:")
    print("  - outputs/tables/iop_main_results.csv")
    print("  - outputs/figures/iop_decomposition.png")
    print("  - outputs/figures/varimp_comparison.png")

    return {
        'tree_model': tree_model,
        'rf_model': rf_model,
        'gb_model': gb_model,
        'tree_metrics': tree_metrics,
        'rf_metrics': rf_metrics,
        'gb_metrics': gb_metrics,
        'cv_results': cv_results,
        'rf_importance': rf_importance
    }

# ============================================================================
# Entry Point
# ============================================================================

if __name__ == "__main__":
    results = run_iop_analysis()

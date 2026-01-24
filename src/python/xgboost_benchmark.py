"""
xgboost_benchmark.py - XGBoost Model for IOp Analysis with SHAP
===============================================================================
Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
Purpose: Benchmark XGBoost model with hyperparameter tuning and SHAP explanations
===============================================================================
"""

import os
import yaml
import numpy as np
import pandas as pd
from pathlib import Path
from typing import Dict, List, Tuple, Optional

import xgboost as xgb
from sklearn.model_selection import KFold, cross_val_score
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import r2_score, mean_squared_error

import shap
import optuna
from optuna.samplers import TPESampler
import matplotlib.pyplot as plt
import warnings

warnings.filterwarnings('ignore')

# =============================================================================
# Configuration
# =============================================================================

def get_project_root() -> Path:
    """Get project root directory."""
    # Assuming this script is in src/python/
    return Path(__file__).parent.parent.parent


def load_config() -> Dict:
    """Load project configuration."""
    root = get_project_root()
    with open(root / "config" / "config.yaml", 'r') as f:
        return yaml.safe_load(f)


def load_variable_roles() -> Dict:
    """Load variable role definitions."""
    root = get_project_root()
    with open(root / "config" / "variable_roles.yaml", 'r') as f:
        return yaml.safe_load(f)


# =============================================================================
# Data Loading
# =============================================================================

def load_data(config: Dict) -> pd.DataFrame:
    """
    Load preprocessed data for XGBoost analysis.

    Note: This expects a CSV file exported from R preprocessing.
    Update the path once the R pipeline has created this file.
    """
    root = get_project_root()
    data_path = root / config['paths']['data_processed'] / "emovi_for_python.csv"

    if not data_path.exists():
        raise FileNotFoundError(
            f"Data file not found: {data_path}\n"
            "Please run the R preprocessing pipeline first to export data."
        )

    df = pd.read_csv(data_path)
    print(f"Loaded data: {df.shape[0]} observations, {df.shape[1]} variables")

    return df


def prepare_features(
    df: pd.DataFrame,
    outcome_var: str,
    circumstance_vars: List[str],
    weight_var: Optional[str] = None
) -> Tuple[pd.DataFrame, pd.Series, Optional[pd.Series]]:
    """
    Prepare features for XGBoost.

    Args:
        df: Input DataFrame
        outcome_var: Name of outcome variable
        circumstance_vars: List of circumstance variable names
        weight_var: Optional weight variable name

    Returns:
        Tuple of (X, y, weights)
    """
    # Check variables exist
    missing = [v for v in [outcome_var] + circumstance_vars if v not in df.columns]
    if missing:
        raise ValueError(f"Missing variables: {missing}")

    # Select and prepare data
    X = df[circumstance_vars].copy()
    y = df[outcome_var].copy()
    weights = df[weight_var] if weight_var and weight_var in df.columns else None

    # Encode categorical variables
    label_encoders = {}
    for col in X.select_dtypes(include=['object', 'category']).columns:
        le = LabelEncoder()
        X[col] = le.fit_transform(X[col].astype(str))
        label_encoders[col] = le

    # Remove missing values
    valid_idx = X.notna().all(axis=1) & y.notna()
    X = X[valid_idx]
    y = y[valid_idx]
    if weights is not None:
        weights = weights[valid_idx]

    print(f"Prepared features: {X.shape[0]} complete cases, {X.shape[1]} features")

    return X, y, weights, label_encoders


# =============================================================================
# XGBoost Model
# =============================================================================

def create_xgb_model(params: Optional[Dict] = None) -> xgb.XGBRegressor:
    """Create XGBoost regressor with given parameters."""
    default_params = {
        'n_estimators': 300,
        'max_depth': 5,
        'learning_rate': 0.05,
        'subsample': 0.8,
        'colsample_bytree': 0.8,
        'random_state': 42,
        'n_jobs': -1
    }

    if params:
        default_params.update(params)

    return xgb.XGBRegressor(**default_params)


def cross_validate_model(
    model: xgb.XGBRegressor,
    X: pd.DataFrame,
    y: pd.Series,
    n_folds: int = 5,
    seed: int = 123
) -> Dict:
    """
    Cross-validate XGBoost model.

    Returns dict with mean and std of R² scores.
    """
    cv = KFold(n_splits=n_folds, shuffle=True, random_state=seed)

    scores = cross_val_score(model, X, y, cv=cv, scoring='r2')

    return {
        'mean_r2': scores.mean(),
        'std_r2': scores.std(),
        'scores': scores
    }


# =============================================================================
# Hyperparameter Tuning with Optuna
# =============================================================================

def objective(trial: optuna.Trial, X: pd.DataFrame, y: pd.Series) -> float:
    """Optuna objective function for XGBoost tuning."""

    params = {
        'n_estimators': trial.suggest_int('n_estimators', 100, 500),
        'max_depth': trial.suggest_int('max_depth', 3, 8),
        'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.2, log=True),
        'subsample': trial.suggest_float('subsample', 0.6, 1.0),
        'colsample_bytree': trial.suggest_float('colsample_bytree', 0.6, 1.0),
        'min_child_weight': trial.suggest_int('min_child_weight', 1, 10),
        'random_state': 42,
        'n_jobs': -1
    }

    model = xgb.XGBRegressor(**params)

    # 5-fold CV
    cv = KFold(n_splits=5, shuffle=True, random_state=123)
    scores = cross_val_score(model, X, y, cv=cv, scoring='r2')

    return scores.mean()


def tune_hyperparameters(
    X: pd.DataFrame,
    y: pd.Series,
    n_trials: int = 50,
    seed: int = 42
) -> Dict:
    """
    Tune XGBoost hyperparameters using Optuna.

    Returns best parameters and study object.
    """
    print(f"Starting hyperparameter tuning with {n_trials} trials...")

    sampler = TPESampler(seed=seed)
    study = optuna.create_study(direction='maximize', sampler=sampler)

    study.optimize(
        lambda trial: objective(trial, X, y),
        n_trials=n_trials,
        show_progress_bar=True
    )

    print(f"\nBest trial:")
    print(f"  R² = {study.best_trial.value:.4f}")
    print(f"  Best params: {study.best_trial.params}")

    return {
        'best_params': study.best_trial.params,
        'best_score': study.best_trial.value,
        'study': study
    }


# =============================================================================
# SHAP Analysis
# =============================================================================

def compute_shap_values(
    model: xgb.XGBRegressor,
    X: pd.DataFrame
) -> Tuple[shap.Explainer, np.ndarray]:
    """
    Compute SHAP values for XGBoost model.

    Returns explainer and SHAP values array.
    """
    print("Computing SHAP values...")

    explainer = shap.TreeExplainer(model)
    shap_values = explainer.shap_values(X)

    print(f"SHAP values computed for {X.shape[0]} observations")

    return explainer, shap_values


def plot_shap_summary(
    shap_values: np.ndarray,
    X: pd.DataFrame,
    output_path: Path,
    max_display: int = 10
) -> None:
    """Generate and save SHAP summary plot."""

    plt.figure(figsize=(10, 8))
    shap.summary_plot(shap_values, X, max_display=max_display, show=False)
    plt.tight_layout()
    plt.savefig(output_path / "shap_summary.png", dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Saved SHAP summary plot: {output_path / 'shap_summary.png'}")


def plot_shap_bar(
    shap_values: np.ndarray,
    X: pd.DataFrame,
    output_path: Path,
    max_display: int = 10
) -> None:
    """Generate and save SHAP bar plot (mean absolute SHAP values)."""

    plt.figure(figsize=(10, 6))
    shap.summary_plot(
        shap_values, X,
        plot_type="bar",
        max_display=max_display,
        show=False
    )
    plt.tight_layout()
    plt.savefig(output_path / "shap_importance.png", dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Saved SHAP importance plot: {output_path / 'shap_importance.png'}")


def plot_shap_dependence(
    shap_values: np.ndarray,
    X: pd.DataFrame,
    feature: str,
    output_path: Path,
    interaction_feature: Optional[str] = None
) -> None:
    """Generate SHAP dependence plot for a specific feature."""

    plt.figure(figsize=(8, 6))
    shap.dependence_plot(
        feature,
        shap_values,
        X,
        interaction_index=interaction_feature,
        show=False
    )
    plt.tight_layout()

    filename = f"shap_dependence_{feature}.png"
    plt.savefig(output_path / filename, dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Saved SHAP dependence plot: {output_path / filename}")


def get_shap_importance(
    shap_values: np.ndarray,
    X: pd.DataFrame
) -> pd.DataFrame:
    """
    Calculate feature importance from SHAP values.

    Returns DataFrame with mean absolute SHAP values.
    """
    importance = pd.DataFrame({
        'feature': X.columns,
        'mean_abs_shap': np.abs(shap_values).mean(axis=0)
    }).sort_values('mean_abs_shap', ascending=False)

    return importance


# =============================================================================
# IOp Calculation
# =============================================================================

def calculate_iop_metrics(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    weights: Optional[np.ndarray] = None
) -> Dict:
    """
    Calculate IOp metrics from XGBoost predictions.

    Args:
        y_true: Observed outcome values
        y_pred: Predicted (type mean) values
        weights: Optional sample weights

    Returns:
        Dict with IOp metrics
    """
    from scipy.stats import spearmanr

    # R-squared
    r2 = r2_score(y_true, y_pred)

    # Gini coefficient function
    def gini(x, w=None):
        if w is None:
            w = np.ones(len(x))
        sorted_idx = np.argsort(x)
        x_sorted = x[sorted_idx]
        w_sorted = w[sorted_idx]
        cum_w = np.cumsum(w_sorted)
        cum_wx = np.cumsum(w_sorted * x_sorted)
        return 1 - 2 * np.sum(cum_wx[:-1] * w_sorted[1:]) / (cum_w[-1] * cum_wx[-1])

    # Gini-based IOp
    gini_total = gini(y_true, weights)
    gini_between = gini(y_pred, weights)
    iop_gini = gini_between / gini_total if gini_total > 0 else 0

    # Variance-based IOp
    var_total = np.var(y_true)
    var_between = np.var(y_pred)
    iop_var = var_between / var_total if var_total > 0 else 0

    return {
        'r2': r2,
        'gini_total': gini_total,
        'gini_between': gini_between,
        'iop_gini': iop_gini,
        'iop_variance': iop_var,
        'rmse': np.sqrt(mean_squared_error(y_true, y_pred))
    }


# =============================================================================
# Main Pipeline
# =============================================================================

def run_xgboost_pipeline(
    outcome_var: str = "income_decile",
    circumstance_vars: Optional[List[str]] = None,
    tune: bool = True,
    n_tune_trials: int = 50
) -> Dict:
    """
    Run complete XGBoost pipeline.

    Args:
        outcome_var: Name of outcome variable
        circumstance_vars: List of circumstance variables (or None for defaults)
        tune: Whether to run hyperparameter tuning
        n_tune_trials: Number of Optuna trials

    Returns:
        Dict with model, metrics, and SHAP results
    """
    print("=" * 60)
    print("XGBoost Benchmark for IOp Analysis")
    print("=" * 60)

    # Load config and data
    config = load_config()
    root = get_project_root()

    # Default circumstance variables
    if circumstance_vars is None:
        circumstance_vars = [
            'father_education', 'mother_education', 'father_occupation',
            'sex', 'ethnicity', 'skin_tone', 'birth_region', 'birth_cohort'
        ]

    # Try to load data
    try:
        df = load_data(config)
    except FileNotFoundError as e:
        print(f"\nError: {e}")
        print("\nCreating placeholder results...")
        return {'status': 'data_not_available'}

    # Prepare features
    X, y, weights, encoders = prepare_features(
        df, outcome_var, circumstance_vars
    )

    # Hyperparameter tuning or default params
    if tune:
        tuning_results = tune_hyperparameters(X, y, n_trials=n_tune_trials)
        best_params = tuning_results['best_params']
    else:
        best_params = {
            'n_estimators': config['xgboost']['n_estimators']['default'],
            'max_depth': config['xgboost']['max_depth']['default'],
            'learning_rate': config['xgboost']['learning_rate']['default'],
            'subsample': config['xgboost']['subsample']['default'],
            'colsample_bytree': config['xgboost']['colsample_bytree']['default']
        }

    # Fit final model
    print("\nFitting final model with best parameters...")
    model = create_xgb_model(best_params)
    model.fit(X, y)

    # Cross-validation
    cv_results = cross_validate_model(model, X, y)
    print(f"CV R²: {cv_results['mean_r2']:.4f} ± {cv_results['std_r2']:.4f}")

    # IOp metrics
    y_pred = model.predict(X)
    iop_metrics = calculate_iop_metrics(y.values, y_pred,
                                         weights.values if weights is not None else None)

    print("\nIOp Metrics:")
    print(f"  R² (variance explained): {iop_metrics['r2']:.4f}")
    print(f"  IOp share (Gini): {iop_metrics['iop_gini']:.4f}")
    print(f"  IOp share (Variance): {iop_metrics['iop_variance']:.4f}")

    # SHAP analysis
    output_path = root / config['paths']['figures']
    output_path.mkdir(parents=True, exist_ok=True)

    explainer, shap_values = compute_shap_values(model, X)

    # Generate plots
    plot_shap_summary(shap_values, X, output_path)
    plot_shap_bar(shap_values, X, output_path)

    # Dependence plots for top 3 features
    shap_importance = get_shap_importance(shap_values, X)
    top_features = shap_importance.head(3)['feature'].tolist()

    for feature in top_features:
        plot_shap_dependence(shap_values, X, feature, output_path)

    # Save SHAP importance
    tables_path = root / config['paths']['tables']
    tables_path.mkdir(parents=True, exist_ok=True)
    shap_importance.to_csv(tables_path / "xgboost_shap_importance.csv", index=False)

    # Save model
    models_path = root / config['paths']['models']
    models_path.mkdir(parents=True, exist_ok=True)
    model.save_model(str(models_path / "xgboost_model.json"))

    print("\n" + "=" * 60)
    print("XGBoost pipeline complete!")
    print("=" * 60)

    return {
        'status': 'success',
        'model': model,
        'cv_results': cv_results,
        'iop_metrics': iop_metrics,
        'shap_values': shap_values,
        'shap_importance': shap_importance,
        'best_params': best_params
    }


# =============================================================================
# Entry Point
# =============================================================================

if __name__ == "__main__":
    results = run_xgboost_pipeline(tune=False)  # Set tune=True for full optimization

    if results['status'] == 'success':
        print("\nFinal Results Summary:")
        print(f"  CV R²: {results['cv_results']['mean_r2']:.4f}")
        print(f"  IOp (Gini): {results['iop_metrics']['iop_gini']:.4f}")
        print("\nTop circumstances by SHAP importance:")
        print(results['shap_importance'].head(5).to_string(index=False))

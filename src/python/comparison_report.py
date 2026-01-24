"""
comparison_report.py - Compare ctree/cforest vs XGBoost Results
===============================================================================
Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
Purpose: Generate comparison tables and figures for tree methods vs XGBoost
===============================================================================
"""

import os
import yaml
import numpy as np
import pandas as pd
from pathlib import Path
from typing import Dict, List, Optional
import matplotlib.pyplot as plt
import seaborn as sns

# =============================================================================
# Configuration
# =============================================================================

def get_project_root() -> Path:
    """Get project root directory."""
    return Path(__file__).parent.parent.parent


def load_config() -> Dict:
    """Load project configuration."""
    root = get_project_root()
    with open(root / "config" / "config.yaml", 'r') as f:
        return yaml.safe_load(f)


# =============================================================================
# Load Results
# =============================================================================

def load_r_results(root: Path, config: Dict) -> Dict:
    """
    Load results from R analysis (ctree/cforest).

    Returns dict with IOp metrics and variable importance.
    """
    tables_path = root / config['paths']['tables']

    results = {}

    # Load IOp results
    iop_file = tables_path / "iop_main_results.csv"
    if iop_file.exists():
        results['iop'] = pd.read_csv(iop_file)
    else:
        results['iop'] = None
        print(f"Warning: R IOp results not found at {iop_file}")

    # Load variable importance
    varimp_file = tables_path / "varimp_bootstrap_ci.csv"
    if varimp_file.exists():
        results['varimp'] = pd.read_csv(varimp_file)
    else:
        results['varimp'] = None
        print(f"Warning: R variable importance not found at {varimp_file}")

    # Load CV results
    cv_file = tables_path / "ctree_cv_results.csv"
    if cv_file.exists():
        results['cv'] = pd.read_csv(cv_file)
    else:
        results['cv'] = None

    return results


def load_python_results(root: Path, config: Dict) -> Dict:
    """
    Load results from Python analysis (XGBoost).

    Returns dict with SHAP importance and metrics.
    """
    tables_path = root / config['paths']['tables']

    results = {}

    # Load SHAP importance
    shap_file = tables_path / "xgboost_shap_importance.csv"
    if shap_file.exists():
        results['shap'] = pd.read_csv(shap_file)
    else:
        results['shap'] = None
        print(f"Warning: XGBoost SHAP results not found at {shap_file}")

    return results


# =============================================================================
# Comparison Analysis
# =============================================================================

def compare_variable_importance(
    r_varimp: Optional[pd.DataFrame],
    xgb_shap: Optional[pd.DataFrame]
) -> Optional[pd.DataFrame]:
    """
    Compare variable importance rankings between cforest and XGBoost.

    Returns merged DataFrame with both rankings.
    """
    if r_varimp is None or xgb_shap is None:
        print("Cannot compare: missing data from one or both methods")
        return None

    # Normalize importance scores to 0-100 scale
    r_varimp = r_varimp.copy()
    xgb_shap = xgb_shap.copy()

    # Assume columns are named 'variable' and 'mean_importance' / 'mean_abs_shap'
    r_varimp['importance_normalized'] = (
        r_varimp['mean_importance'] / r_varimp['mean_importance'].max() * 100
    )
    r_varimp['rank_cforest'] = range(1, len(r_varimp) + 1)

    xgb_shap['importance_normalized'] = (
        xgb_shap['mean_abs_shap'] / xgb_shap['mean_abs_shap'].max() * 100
    )
    xgb_shap['rank_xgboost'] = range(1, len(xgb_shap) + 1)

    # Merge
    comparison = pd.merge(
        r_varimp[['variable', 'importance_normalized', 'rank_cforest']],
        xgb_shap[['feature', 'importance_normalized', 'rank_xgboost']],
        left_on='variable',
        right_on='feature',
        how='outer',
        suffixes=('_cforest', '_xgboost')
    )

    # Calculate rank correlation
    valid = comparison.dropna(subset=['rank_cforest', 'rank_xgboost'])
    if len(valid) > 2:
        from scipy.stats import spearmanr
        corr, pval = spearmanr(valid['rank_cforest'], valid['rank_xgboost'])
        print(f"Rank correlation (Spearman): {corr:.3f} (p={pval:.4f})")

    return comparison


def compare_iop_estimates(
    r_iop: Optional[pd.DataFrame],
    xgb_metrics: Optional[Dict]
) -> pd.DataFrame:
    """
    Compare IOp estimates between methods.

    Returns DataFrame with side-by-side comparison.
    """
    results = []

    # R results
    if r_iop is not None:
        for _, row in r_iop.iterrows():
            if 'IOp Share' in row['metric']:
                results.append({
                    'metric': row['metric'],
                    'ctree_cforest': row['value'],
                    'source': 'R (ctree/cforest)'
                })

    # XGBoost results
    if xgb_metrics is not None:
        results.append({
            'metric': 'IOp Share (R²)',
            'xgboost': xgb_metrics.get('r2'),
            'source': 'Python (XGBoost)'
        })
        results.append({
            'metric': 'IOp Share (Gini)',
            'xgboost': xgb_metrics.get('iop_gini'),
            'source': 'Python (XGBoost)'
        })

    return pd.DataFrame(results)


# =============================================================================
# Visualization
# =============================================================================

def plot_importance_comparison(
    comparison: pd.DataFrame,
    output_path: Path
) -> None:
    """
    Create side-by-side bar plot of variable importance.
    """
    if comparison is None:
        print("No comparison data available for plotting")
        return

    # Prepare data for plotting
    plot_data = comparison.dropna(subset=['importance_normalized_cforest', 'importance_normalized_xgboost'])
    plot_data = plot_data.sort_values('importance_normalized_cforest', ascending=True)

    if len(plot_data) == 0:
        print("No overlapping variables for comparison plot")
        return

    # Create figure
    fig, ax = plt.subplots(figsize=(10, 8))

    y_pos = np.arange(len(plot_data))
    height = 0.35

    ax.barh(y_pos - height/2, plot_data['importance_normalized_cforest'],
            height, label='cforest', color='#0072B2', alpha=0.8)
    ax.barh(y_pos + height/2, plot_data['importance_normalized_xgboost'],
            height, label='XGBoost (SHAP)', color='#D55E00', alpha=0.8)

    ax.set_yticks(y_pos)
    ax.set_yticklabels(plot_data['variable'])
    ax.set_xlabel('Relative Importance (normalized to 100)')
    ax.set_title('Variable Importance Comparison: cforest vs XGBoost')
    ax.legend(loc='lower right')

    plt.tight_layout()
    plt.savefig(output_path / "varimp_comparison.png", dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Saved comparison plot: {output_path / 'varimp_comparison.png'}")


def plot_rank_correlation(
    comparison: pd.DataFrame,
    output_path: Path
) -> None:
    """
    Create scatter plot of variable importance rankings.
    """
    if comparison is None:
        return

    plot_data = comparison.dropna(subset=['rank_cforest', 'rank_xgboost'])

    if len(plot_data) < 3:
        return

    fig, ax = plt.subplots(figsize=(8, 8))

    ax.scatter(plot_data['rank_cforest'], plot_data['rank_xgboost'],
               s=100, alpha=0.7, color='#009E73')

    # Add variable labels
    for _, row in plot_data.iterrows():
        ax.annotate(
            row['variable'],
            (row['rank_cforest'], row['rank_xgboost']),
            xytext=(5, 5), textcoords='offset points',
            fontsize=8
        )

    # Add diagonal line (perfect agreement)
    max_rank = max(plot_data['rank_cforest'].max(), plot_data['rank_xgboost'].max())
    ax.plot([1, max_rank], [1, max_rank], 'k--', alpha=0.5, label='Perfect agreement')

    ax.set_xlabel('Rank (cforest)')
    ax.set_ylabel('Rank (XGBoost/SHAP)')
    ax.set_title('Variable Importance Rank Agreement')
    ax.legend()

    plt.tight_layout()
    plt.savefig(output_path / "rank_correlation.png", dpi=300, bbox_inches='tight')
    plt.close()

    print(f"Saved rank correlation plot: {output_path / 'rank_correlation.png'}")


# =============================================================================
# Report Generation
# =============================================================================

def generate_comparison_table(
    r_results: Dict,
    py_results: Dict,
    output_path: Path
) -> pd.DataFrame:
    """
    Generate comprehensive comparison table.
    """
    rows = []

    # Method comparison
    rows.append({
        'Aspect': 'Model Type',
        'ctree/cforest (R)': 'Conditional Inference Trees',
        'XGBoost (Python)': 'Gradient Boosted Trees'
    })

    rows.append({
        'Aspect': 'Interpretability',
        'ctree/cforest (R)': 'Tree visualization, permutation importance',
        'XGBoost (Python)': 'SHAP values, dependence plots'
    })

    rows.append({
        'Aspect': 'Statistical Tests',
        'ctree/cforest (R)': 'Built-in permutation tests for splits',
        'XGBoost (Python)': 'No built-in tests'
    })

    rows.append({
        'Aspect': 'Correlation Handling',
        'ctree/cforest (R)': 'Conditional importance available',
        'XGBoost (Python)': 'SHAP handles feature interactions'
    })

    # Add IOp estimates if available
    if r_results.get('iop') is not None:
        iop_df = r_results['iop']
        for _, row in iop_df.iterrows():
            if 'IOp' in str(row.get('metric', '')):
                rows.append({
                    'Aspect': row['metric'],
                    'ctree/cforest (R)': f"{row['value']:.4f}",
                    'XGBoost (Python)': '-'
                })

    comparison_df = pd.DataFrame(rows)
    comparison_df.to_csv(output_path / "model_comparison.csv", index=False)

    print(f"Saved comparison table: {output_path / 'model_comparison.csv'}")

    return comparison_df


def generate_markdown_report(
    r_results: Dict,
    py_results: Dict,
    comparison: Optional[pd.DataFrame],
    output_path: Path
) -> None:
    """
    Generate markdown comparison report.
    """
    report = []
    report.append("# IOp Analysis: Method Comparison Report\n")
    report.append("## Overview\n")
    report.append("This report compares Inequality of Opportunity (IOp) estimates ")
    report.append("from two methodological approaches:\n")
    report.append("1. **ctree/cforest** (R): Conditional Inference Trees and Forests\n")
    report.append("2. **XGBoost** (Python): Gradient Boosted Trees with SHAP explanations\n\n")

    # IOp estimates section
    report.append("## IOp Estimates\n")
    if r_results.get('iop') is not None:
        report.append("### ctree/cforest Results\n")
        report.append("| Metric | Value |\n")
        report.append("|--------|-------|\n")
        for _, row in r_results['iop'].iterrows():
            if 'IOp' in str(row.get('metric', '')):
                report.append(f"| {row['metric']} | {row['value']:.4f} |\n")
        report.append("\n")

    # Variable importance section
    report.append("## Variable Importance Comparison\n")
    if comparison is not None:
        report.append("### Top Circumstances by Importance\n")
        report.append("| Variable | cforest Rank | XGBoost Rank |\n")
        report.append("|----------|--------------|---------------|\n")
        top_vars = comparison.sort_values('rank_cforest').head(10)
        for _, row in top_vars.iterrows():
            var = row.get('variable', row.get('feature', 'N/A'))
            r_rank = int(row['rank_cforest']) if pd.notna(row.get('rank_cforest')) else '-'
            x_rank = int(row['rank_xgboost']) if pd.notna(row.get('rank_xgboost')) else '-'
            report.append(f"| {var} | {r_rank} | {x_rank} |\n")
        report.append("\n")

    # Recommendations
    report.append("## Recommendations\n")
    report.append("- Use **ctree** for transparent, interpretable type partitions\n")
    report.append("- Use **cforest** for stable variable importance with CIs\n")
    report.append("- Use **XGBoost + SHAP** for maximum predictive accuracy and ")
    report.append("individual-level explanations\n")
    report.append("- Report both approaches for robustness\n")

    # Write report
    with open(output_path / "comparison_report.md", 'w') as f:
        f.writelines(report)

    print(f"Saved markdown report: {output_path / 'comparison_report.md'}")


# =============================================================================
# Main Pipeline
# =============================================================================

def run_comparison_report() -> None:
    """
    Run complete comparison report generation.
    """
    print("=" * 60)
    print("Generating Method Comparison Report")
    print("=" * 60)

    root = get_project_root()
    config = load_config()

    # Load results
    print("\nLoading results...")
    r_results = load_r_results(root, config)
    py_results = load_python_results(root, config)

    # Output paths
    figures_path = root / config['paths']['figures']
    tables_path = root / config['paths']['tables']
    figures_path.mkdir(parents=True, exist_ok=True)
    tables_path.mkdir(parents=True, exist_ok=True)

    # Compare variable importance
    print("\nComparing variable importance...")
    comparison = compare_variable_importance(
        r_results.get('varimp'),
        py_results.get('shap')
    )

    # Generate visualizations
    print("\nGenerating visualizations...")
    plot_importance_comparison(comparison, figures_path)
    plot_rank_correlation(comparison, figures_path)

    # Generate tables
    print("\nGenerating comparison tables...")
    generate_comparison_table(r_results, py_results, tables_path)

    # Generate markdown report
    print("\nGenerating markdown report...")
    generate_markdown_report(r_results, py_results, comparison, tables_path)

    print("\n" + "=" * 60)
    print("Comparison report complete!")
    print("=" * 60)


# =============================================================================
# Entry Point
# =============================================================================

if __name__ == "__main__":
    run_comparison_report()

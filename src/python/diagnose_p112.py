# -*- coding: utf-8 -*-
"""
diagnose_p112.py - Diagnostico de la variable Skin Tone (p112)
===============================================================================
Investiga por que SHAP = 0 para esta variable
===============================================================================
"""

import pandas as pd
import numpy as np
from pathlib import Path
import sys

# Force UTF-8 output on Windows
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PROJECT_ROOT = Path(__file__).parent.parent.parent
DATA_PATH = PROJECT_ROOT / "data" / "raw" / "emovi" / "Data" / "entrevistado_2023.dta"
OUTPUT_PATH = PROJECT_ROOT / "outputs" / "tables" / "p112_diagnostic.txt"

def diagnose_p112():
    """Diagnostico completo de la variable p112."""

    print("=" * 70)
    print("DIAGNOSTICO: Variable p112 (Skin Tone)")
    print("=" * 70)

    # Cargar datos
    print("\n1. Cargando datos...")
    df = pd.read_stata(DATA_PATH, convert_categoricals=False)
    print(f"   Total observaciones: {len(df):,}")

    # Verificar si p112 existe
    if 'p112' not in df.columns:
        print("\n   ERROR: Variable p112 no existe en el dataset!")
        print("   Variables disponibles que contienen '112':")
        for col in df.columns:
            if '112' in col.lower():
                print(f"      - {col}")
        return

    p112 = df['p112']

    # 2. Estadisticas descriptivas
    print("\n2. Estadisticas descriptivas:")
    print(f"   - Tipo de dato: {p112.dtype}")
    print(f"   - Valores unicos: {p112.nunique()}")
    print(f"   - Valores faltantes: {p112.isna().sum()} ({p112.isna().mean()*100:.1f}%)")
    print(f"   - Minimo: {p112.min()}")
    print(f"   - Maximo: {p112.max()}")

    # Check if string type (PERLA scale A-K)
    is_string = p112.dtype == 'object' or str(p112.dtype) == 'str'
    if is_string:
        print("\n   [!] ALERTA: Variable es tipo STRING (A-K), no numerica!")
        print("   Esto causa que XGBoost no la procese correctamente.")
        print("\n   Mapeo PERLA esperado:")
        print("   A=1 (mas claro) ... K=11 (mas oscuro)")

        # Convert to numeric for analysis
        perla_map = {chr(65+i): i+1 for i in range(11)}  # A=1, B=2, ..., K=11
        p112_numeric = p112.map(perla_map)
        print(f"\n   Despues de conversion a numerico:")
        print(f"   - Media: {p112_numeric.mean():.2f}")
        print(f"   - Mediana: {p112_numeric.median()}")
        print(f"   - Desv. estandar: {p112_numeric.std():.2f}")
        variance = p112_numeric.var()
    else:
        print(f"   - Media: {p112.mean():.2f}")
        print(f"   - Mediana: {p112.median()}")
        print(f"   - Desv. estandar: {p112.std():.2f}")
        variance = p112.var()
        p112_numeric = p112

    # 3. Distribucion de frecuencias
    print("\n3. Distribucion de frecuencias:")
    value_counts = p112.value_counts(dropna=False).sort_index()
    total = len(p112)
    for val, count in value_counts.items():
        pct = count / total * 100
        bar = "#" * int(pct / 2)
        print(f"   {val:>5}: {count:>6,} ({pct:>5.1f}%) {bar}")

    # 4. Verificar varianza (usar p112_numeric si existe)
    print("\n4. Analisis de varianza:")
    print(f"   - Varianza: {variance:.4f}")
    if variance < 0.1:
        print("   [!] ALERTA: Varianza muy baja - posible causa de SHAP = 0")

    # 5. Verificar si es constante despues de preprocesamiento
    print("\n5. Despues de eliminar NAs:")
    p112_clean = p112_numeric.dropna()
    print(f"   - Observaciones validas: {len(p112_clean):,}")
    print(f"   - Valores unicos: {p112_clean.nunique()}")
    print(f"   - Varianza: {p112_clean.var():.4f}")

    # 6. Correlacion con income (usando p112_numeric)
    print("\n6. Correlacion con ingreso:")
    if 'ingc_pc' in df.columns:
        df_valid = df[['ingc_pc']].copy()
        df_valid['p112_num'] = p112_numeric
        df_valid = df_valid.dropna()
        corr = df_valid['p112_num'].corr(df_valid['ingc_pc'])
        print(f"   - Correlacion Pearson con ingc_pc: {corr:.4f}")

        # Correlacion con log-income
        df_valid['ln_income'] = np.log(df_valid['ingc_pc'].replace(0, np.nan))
        df_valid = df_valid.dropna()
        corr_log = df_valid['p112_num'].corr(df_valid['ln_income'])
        print(f"   - Correlacion Pearson con ln(ingc_pc): {corr_log:.4f}")

    # 7. Verificar colinealidad con otras variables
    print("\n7. Correlacion con otras circunstancias:")
    other_vars = ['sexo', 'p111', 'region_14', 'cohorte', 'p21', 'educp', 'educm', 'clasep']
    for var in other_vars:
        if var in df.columns:
            df_pair = pd.DataFrame({'p112': p112_numeric, 'other': df[var]}).dropna()
            if len(df_pair) > 100:
                # Convert other var to numeric if needed
                df_pair['other'] = pd.to_numeric(df_pair['other'], errors='coerce')
                df_pair = df_pair.dropna()
                if len(df_pair) > 100:
                    corr = df_pair['p112'].corr(df_pair['other'])
                    print(f"   - {var}: {corr:.4f}")

    # 8. Diagnostico final
    print("\n" + "=" * 70)
    print("DIAGNOSTICO FINAL:")
    print("=" * 70)

    issues = []

    if is_string:
        issues.append("Variable codificada como STRING (A-K) en lugar de numerico")

    if p112.nunique() <= 2:
        issues.append("Variable tiene muy pocos valores unicos")

    if variance < 0.5:
        issues.append("Varianza muy baja")

    mode_pct = value_counts.max() / total * 100
    if mode_pct > 70:
        issues.append(f"Valor modal representa {mode_pct:.1f}% de los datos")

    if p112.isna().mean() > 0.3:
        issues.append(f"Alto porcentaje de missing ({p112.isna().mean()*100:.1f}%)")

    if len(issues) > 0:
        print("\n[!] PROBLEMAS DETECTADOS:")
        for i, issue in enumerate(issues, 1):
            print(f"   {i}. {issue}")
        print("\n   SOLUCION APLICADA: xgboost_shap_analysis.py ahora convierte A-K -> 1-11")
    else:
        print("\n[OK] No se detectaron problemas obvios.")
        print("   El SHAP = 0 puede deberse a:")
        print("   - Efecto mediado por otras variables")
        print("   - Colinealidad con otras circunstancias")
        print("   - XGBoost no usa esta variable en splits")

    # Guardar resultados
    with open(OUTPUT_PATH, 'w', encoding='utf-8') as f:
        f.write("DIAGNOSTICO p112 (Skin Tone)\n")
        f.write("=" * 50 + "\n\n")
        f.write(f"Observaciones: {len(df):,}\n")
        f.write(f"Valores unicos: {p112.nunique()}\n")
        f.write(f"Tipo: {p112.dtype} {'(STRING - necesita conversion)' if is_string else ''}\n")
        f.write(f"Missing: {p112.isna().sum()} ({p112.isna().mean()*100:.1f}%)\n")
        f.write(f"Varianza (numerico): {variance:.4f}\n\n")
        f.write("Distribucion:\n")
        for val, count in value_counts.items():
            f.write(f"  {val}: {count:,} ({count/total*100:.1f}%)\n")
        f.write("\nProblemas detectados:\n")
        for issue in issues:
            f.write(f"  - {issue}\n")
        f.write("\nSolucion: Convertir A-K a 1-11 en xgboost_shap_analysis.py\n")

    print(f"\nResultados guardados en: {OUTPUT_PATH}")

    return {
        'n_unique': p112.nunique(),
        'variance': variance,
        'missing_pct': p112.isna().mean() * 100,
        'mode_pct': mode_pct,
        'issues': issues,
        'is_string': is_string
    }


if __name__ == "__main__":
    diagnose_p112()

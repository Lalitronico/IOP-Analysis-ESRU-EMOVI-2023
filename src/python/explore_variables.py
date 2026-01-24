"""
explore_variables.py - Quick exploration of EMOVI 2023 variables
===============================================================================
Run this script to identify variable names for IOp analysis
===============================================================================
"""

import pandas as pd
import os

# Set working directory
os.chdir(r"C:\Users\HP ZBOOK\Desktop\Inequality of Opportunity")

print("=" * 72)
print("EMOVI 2023 - Variable Exploration")
print("=" * 72)
print()

# ============================================================================
# 1. Load main dataset
# ============================================================================

print("Loading entrevistado_2023.dta...")
try:
    # Read without converting to categoricals to avoid label issues
    entrevistado = pd.read_stata("data/raw/emovi/Data/entrevistado_2023.dta",
                                  convert_categoricals=False)
    print(f"Loaded: {len(entrevistado)} observations, {len(entrevistado.columns)} variables\n")
except Exception as e:
    print(f"Error loading data: {e}")
    exit(1)

# ============================================================================
# 2. Get variable information
# ============================================================================

# Get variable labels from Stata file
try:
    import pyreadstat
    _, meta = pyreadstat.read_dta("data/raw/emovi/Data/entrevistado_2023.dta")
    var_labels = meta.column_names_to_labels
except ImportError:
    print("pyreadstat not available, using pandas metadata")
    var_labels = {}

# Create variable info dataframe
var_info = pd.DataFrame({
    'variable': entrevistado.columns,
    'label': [var_labels.get(col, '') for col in entrevistado.columns],
    'dtype': [str(entrevistado[col].dtype) for col in entrevistado.columns],
    'n_unique': [entrevistado[col].nunique() for col in entrevistado.columns],
    'pct_missing': [round(entrevistado[col].isna().mean() * 100, 1) for col in entrevistado.columns]
})

# ============================================================================
# 3. Search for key variables
# ============================================================================

def search_vars(df_info, pattern, description):
    print(f"\n--- {description} ---")
    mask = (df_info['variable'].str.contains(pattern, case=False, na=False) |
            df_info['label'].str.contains(pattern, case=False, na=False))
    matches = df_info[mask]

    if len(matches) > 0:
        for _, row in matches.head(30).iterrows():
            label = str(row['label'])[:60] if pd.notna(row['label']) else ''
            print(f"  {row['variable']:<15} : {label} (n={row['n_unique']}, miss={row['pct_missing']}%)")
    else:
        print("  No matches found")

    return matches

print("\n" + "=" * 72)
print("SEARCHING FOR KEY VARIABLES")
print("=" * 72)

# Income/outcome variables
search_vars(var_info, "ingreso|income|decil|quintil|sueldo|salario", "INCOME VARIABLES")
search_vars(var_info, "escol|educ|school|estudi|grado|nivel", "EDUCATION VARIABLES")
search_vars(var_info, "ocup|trabajo|empleo|job|work", "OCCUPATION VARIABLES")
search_vars(var_info, "riqueza|wealth|activo|asset|bien", "WEALTH/ASSETS")

# Circumstance variables
search_vars(var_info, "padre|papa|father", "FATHER VARIABLES")
search_vars(var_info, "madre|mama|mother", "MOTHER VARIABLES")
search_vars(var_info, "14|catorce", "AT AGE 14 VARIABLES")
search_vars(var_info, "sexo|sex|genero", "SEX/GENDER")
search_vars(var_info, "etni|indigen|lengua", "ETHNICITY/INDIGENOUS")
search_vars(var_info, "piel|skin|color|tono", "SKIN TONE")
search_vars(var_info, "region|estado|entidad|zona", "REGION/LOCATION")
search_vars(var_info, "nac|birth|año_nac", "BIRTH YEAR")
search_vars(var_info, "libro|book", "BOOKS")
search_vars(var_info, "hermano|sibling", "SIBLINGS")
search_vars(var_info, "factor|peso|weight|pond", "SURVEY WEIGHTS")
search_vars(var_info, "hogar|household|vivienda", "HOUSEHOLD")
search_vars(var_info, "clase|class|estrato|nse", "SOCIAL CLASS/SES")

# ============================================================================
# 4. Show all variables (first 150)
# ============================================================================

print("\n" + "=" * 72)
print("ALL VARIABLES (first 150)")
print("=" * 72)

for i, row in var_info.head(150).iterrows():
    label = str(row['label'])[:65] if pd.notna(row['label']) else ''
    print(f"{row['variable']:<15} : {label}")

if len(var_info) > 150:
    print(f"\n... and {len(var_info) - 150} more variables")

# ============================================================================
# 5. Save full variable list to CSV
# ============================================================================

os.makedirs("outputs/tables", exist_ok=True)
var_info.to_csv("outputs/tables/variable_inventory_full.csv", index=False)
print(f"\nFull variable inventory saved to: outputs/tables/variable_inventory_full.csv")

# ============================================================================
# 6. Load data dictionary
# ============================================================================

print("\n" + "=" * 72)
print("DATA DICTIONARY (Excel)")
print("=" * 72)

try:
    dict_file = "data/raw/emovi/Diccionario ESRU EMOVI 2023.xlsx"
    xl = pd.ExcelFile(dict_file)
    print(f"Dictionary sheets: {xl.sheet_names}\n")

    for sheet in xl.sheet_names[:3]:
        print(f"\n--- Sheet: {sheet} ---")
        df_dict = pd.read_excel(dict_file, sheet_name=sheet, nrows=15)
        print(df_dict.to_string())
        print()
except Exception as e:
    print(f"Error reading dictionary: {e}")

# ============================================================================
# 7. Quick look at key variables
# ============================================================================

print("\n" + "=" * 72)
print("SAMPLE VALUES FOR KEY VARIABLES")
print("=" * 72)

def show_var(df, varname):
    if varname in df.columns:
        print(f"\n{varname}:")
        values = df[varname].dropna().unique()
        print(f"  Unique values: {len(values)}")
        print(f"  Sample: {list(values[:10])}")
        print(f"  Type: {df[varname].dtype}")

# Try common variable names
potential_vars = ['p1', 'p2', 'p3', 'p4', 'p5', 'sexo', 'edad', 'factor',
                  'folio', 'region', 'entidad', 'decil', 'quintil', 'nse']

for v in potential_vars:
    show_var(entrevistado, v)

# Also check hogar dataset
print("\n" + "=" * 72)
print("HOGAR DATASET")
print("=" * 72)

try:
    hogar = pd.read_stata("data/raw/emovi/Data/hogar_2023.dta", convert_categoricals=False)
    print(f"Loaded hogar_2023: {len(hogar)} obs, {len(hogar.columns)} vars")
    print(f"Variables: {list(hogar.columns[:50])}")
except Exception as e:
    print(f"Error: {e}")

print("\n\nScript completed.")

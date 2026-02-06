#!/bin/bash

# ===========================
#       DATA EXTRACTION
# ===========================
source .venv/bin/activate

# <-- HANDLE OPTIONS -->
skip_extraction=false;
skip_generation=false;
for arg in "$@"; do
  case $arg in
    --extract)
      skip_generation=true
      shift
      ;;
    --generate)
      skip_extraction=true
      shift
      ;;
    *)
      ;;
  esac
done

if [ "${skip_extraction}" = false ]; then
    echo "Starting Data Extraction..."
    # 0. Extract data
    python3 data_extractor.py
    echo "Done. Data is ready."
fi

# ===========================
#     REPORT GENERATION
# ===========================

STAMP=$(ls -d ./dbhc_csv/* | sort | tail -n 1 | xargs basename)
mkdir -p "dbhc_manual/${STAMP}"
OUT_DIR="dbhc_reports/${STAMP}"
mkdir -p "$OUT_DIR"
SCRIPT_DIR="./dbhc_report_qmd"
cd "$SCRIPT_DIR"

if [ "${skip_generation}" = false ]; then
    echo "Starting Report Generation for REPORT $STAMP..."

    PDF_NAME="dbhc_report.pdf"
    HTML_NAME="dbhc_report.html"

    # 1. Render PDF
    quarto render pdf_generator.qmd --to pdf --output "$PDF_NAME"

    # 2. Render HTML
    quarto render html_generator.qmd --to html --output "$HTML_NAME"

    # 3. --- AUTOMATED CLEANUP ---
    echo "Cleaning up residual files..."

    # Remove the .tex file
    rm -f pdf_generator.tex

    # Remove the auxiliary directories created by Quarto
    rm -rf pdf_generator_files
    rm -rf html_generator_files

    # Optional: Remove the site_libs folder if generated for HTML
    rm -rf site_libs

    # 4. Move final outputs
    cd ..
    mv "${SCRIPT_DIR}/${PDF_NAME}" "$OUT_DIR"
    mv "${SCRIPT_DIR}/${HTML_NAME}" "$OUT_DIR"

    echo "Done. Reports are ready in $OUT_DIR"
fi
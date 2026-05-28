#!/bin/bash

# Only activate .venv if not running inside a Docker container
if [ ! -f /.dockerenv ]; then
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    fi
fi

# ================================
#       HELPER FUNCTIONS
# ================================
# Function to validate and format date
format_date() {
    local input_date=$1
    # Attempt to convert the input date to YYYYMMDD
    # 'date -d' is common in GNU/Linux. For macOS (BSD), use 'date -j -f'
    if [[ "$OSTYPE" == "darwin"* ]]; then
        formatted=$(date -j -f "%Y-%m-%d" "$input_date" "+%Y%m%d" 2>/dev/null)
    else
        formatted=$(date -d "$input_date" "+%Y%m%d" 2>/dev/null)
    fi
    echo "$formatted"
}

# ================================
#       ONEDRIVE DIR SETUP
# ================================

DATA_PATH="./dbhc_onedrive/dbhc_data"
EXTRACTED_DATA_PATH="./dbhc_onedrive/dbhc_extracted_data"
MANUAL_DATA_PATH="./dbhc_onedrive/dbhc_manual"
REPORTS_PATH="./dbhc_onedrive/dbhc_reports"

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

# ===========================
#       DATA EXTRACTION
# ===========================

if [ "${skip_extraction}" = false ]; then
  while true; do
    read -p "Enter Start Date of Alert Log Check (YYYY-MM-DD): " START_INPUT
    read -p "Enter End Date of Alert Log Check (YYYY-MM-DD): " END_INPUT

    START_TRANSFORMED=$(format_date "$START_INPUT")
    END_TRANSFORMED=$(format_date "$END_INPUT")

    if [[ -n "$START_TRANSFORMED" && -n "$END_TRANSFORMED" ]]; then
        echo "-------------------------------------"
        echo "Start Date: $START_TRANSFORMED"
        echo "End Date:   $END_TRANSFORMED"
        echo "-------------------------------------"
        break
    else
        echo "Error: One or both dates are invalid. Please use YYYY-MM-DD format."
        echo ""
    fi
  done
  echo "Starting Data Extraction..."
  python3 data_extractor.py ${DATA_PATH} ${EXTRACTED_DATA_PATH} ${START_TRANSFORMED} ${END_TRANSFORMED}
  echo "Done. Data is ready."
fi

# ===========================
#     REPORT GENERATION
# ===========================

if [ "${skip_generation}" = false ]; then
  # Directory and Variable Setup
  PDF_NAME="dbhc_report.pdf"
  HTML_NAME="dbhc_report.html"
  STAMP=$(ls -d ${EXTRACTED_DATA_PATH}/* | sort | tail -n 1 | xargs basename)

  mkdir -p "${MANUAL_DATA_PATH}/${STAMP}"

  if [[ ! -f "${MANUAL_DATA_PATH}/${STAMP}/findings.docx" ]]; then
    cp "${MANUAL_DATA_PATH}/template_findings.docx" "${MANUAL_DATA_PATH}/${STAMP}/findings.docx"
  fi
  if [[ ! -f "${MANUAL_DATA_PATH}/${STAMP}/alert_logs.xlsx" ]]; then
    cp "${MANUAL_DATA_PATH}/template_alert_logs.xlsx" "${MANUAL_DATA_PATH}/${STAMP}/alert_logs.xlsx"
  fi

  OUT_DIR="${REPORTS_PATH}/${STAMP}"
  mkdir -p "$OUT_DIR"
  SCRIPT_DIR="./dbhc_report_qmd"
  cd "$SCRIPT_DIR"

  echo "Starting Report Generation for REPORT $STAMP..."

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

  # Remove the site_libs folder if generated for HTML
  rm -rf site_libs

  # 4. Move final outputs
  cd ..
  mv "${SCRIPT_DIR}/${PDF_NAME}" "$OUT_DIR"
  mv "${SCRIPT_DIR}/${HTML_NAME}" "$OUT_DIR"

  echo "Done. Reports are ready in $OUT_DIR"
fi
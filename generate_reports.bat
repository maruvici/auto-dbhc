@echo off
setlocal enabledelayedexpansion

:: ===========================
::       DATA EXTRACTION
:: ===========================

:: Activate virtual environment (Windows uses \Scripts\activate)
call .venv\Scripts\activate

echo Starting Data Extraction...

:: 0. Extract data
python data_extractor.py

:: ===========================
::     REPORT GENERATION
:: ===========================

:: Get the last directory alphabetically
:: /O:N sorts by name, /B is bare format, /A:D filters for directories
for /f "delims=" %%i in ('dir "dbhc_csv" /b /ad /on') do (
    set "STAMP=%%i"
)

set "OUT_DIR=dbhc_reports\%STAMP%"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

set "SCRIPT_DIR=dbhc_report_qmd"
cd %SCRIPT_DIR%

echo Starting Report Generation for REPORT %STAMP%...

set "PDF_NAME=dbhc_report.pdf"
set "HTML_NAME=dbhc_report.html"

:: 1. Render PDF
quarto render pdf_generator.qmd --to pdf --output "%PDF_NAME%"

:: 2. Render HTML
quarto render html_generator.qmd --to html --output "%HTML_NAME%"

:: 3. --- AUTOMATED CLEANUP ---
echo Cleaning up residual files...

del /f /q pdf_generator.tex
if exist pdf_generator_files rmdir /s /q pdf_generator_files
if exist html_generator_files rmdir /s /q html_generator_files
if exist site_libs rmdir /s /q site_libs

:: 4. Move final outputs
cd ..
move "%SCRIPT_DIR%\%PDF_NAME%" "%OUT_DIR%"
move "%SCRIPT_DIR%\%HTML_NAME%" "%OUT_DIR%"

echo Done. Reports are ready in %OUT_DIR%
pause
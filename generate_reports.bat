@echo off
setlocal enabledelayedexpansion

:: 1. Get Date in YYYYMMDD format
for /f "tokens=2-4 delims=/ " %%a in ('echo %date%') do (
    set year=%%c
    set month=%%a
    set day=%%b
)
set STAMP=%year%%month%%day%

:: 2. Set Directories
set "OUT_DIR=dbhc_reports\!STAMP!"
set "SCRIPT_DIR=.\dbhc_report_qmd"

:: Create the output directory
if not exist "!OUT_DIR!" mkdir "!OUT_DIR!"

:: Move to the script directory
cd /d "%SCRIPT_DIR%"

echo Starting Report Generation for !STAMP!...

set "PDF_NAME=dbhc_report.pdf"
set "HTML_NAME=dbhc_report.html"

:: 3. Render PDF
quarto render pdf_generator.qmd --to pdf --output "!PDF_NAME!"

:: 4. Render HTML
quarto render html_generator.qmd --to html --output "!HTML_NAME!"

:: 5. --- AUTOMATED CLEANUP ---
echo Cleaning up residual files...

:: Remove the .tex file if it exists
if exist pdf_generator.tex del /f /q pdf_generator.tex

:: Remove auxiliary directories created by Quarto
if exist pdf_generator_files rd /s /q pdf_generator_files
if exist html_generator_files rd /s /q html_generator_files

:: Optional: Remove site_libs folder
if exist site_libs rd /s /q site_libs

:: 6. Move final outputs
echo Moving reports to !OUT_DIR!...
cd /d ".."
move "%SCRIPT_DIR%\!PDF_NAME!" "!OUT_DIR!"
move "%SCRIPT_DIR%\!HTML_NAME!" "!OUT_DIR!"

echo Done. Reports are ready in !OUT_DIR!
pause
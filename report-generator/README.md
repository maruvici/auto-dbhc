# automated-db-health-checkup
Scripts to automatically generate Oracle Database Health Checkup (DBHC) report. Created for one of SSI's clients' monthly DB health checkups.

## DBHC Data Analysis and Report Generation (SSI)
0. Ensure `data-collector` generated data is in `dbhc_data` directory (either locally or in OneDrive)
    - If using OneDrive: ensure `.env` file exists storing `DATA_PATH` and `EXTRACTED_DATA_PATH` variables
1. Install Dependencies (In-Order)
    - Python
        - Windows:
            - Visit the [Official Python Website](https://www.python.org/downloads/)
            - Download the latest version of Python
            - Run the `.exe` installer
        - Linux (Ubuntu/Debian):
            - Run the following code:
                ```bash
                sudo apt update
                sudo apt install python3 python3-pip python3-venv
                ```
    - (Optional) Create Virtual Environment
        - Windows:
            - Run the following code:
                ```python
                python -m venv .venv
                .venv\Scripts\activate
                ```
        - Linux (Ubuntu/Debian)
            - Run the following code:
                ```bash
                python3 -m venv .venv
                source .venv\bin\activate   
                ```
    - Quarto 
        - Windows:
            - Visit the [Official Quarto Website](https://quarto.org/)
            - Click `Get Started`
            - Select `Download Quarto CLI`
            - Run the `.exe` installer
        - Linux (Ubuntu/Debian):
            - Run the following code:
                ```bash 
                wget https://github.com/quarto-dev/quarto-cli/releases/download/v1.8.27/quarto-1.8.27-linux-amd64.deb
                sudo apt install ./quarto-1.8.27-linux-amd64.deb   
                ```
    - Tinytex
        - Run `quarto install tinytex`
    - Other Dependencies
        - If using `pip`:
            - Run `pip install -r requirements.txt`
3. Execute Report Generation script
    - Run `bash generate_reports.sh`
        - `--extract`: to extract data from raw data only
        - `--generate`: to generate reports only
4. Add human-generated data in `dbhc_manual` directory under the correct timestampped subdir
    - For images: `![Alt Text](./assets/image.jpg){width=70% style="display:block; margin:0 auto;"}`
5. Change callouts in `_core_content.qmd` to correspond with urgency level:
    - Callout Levels in increasing order of urgency:
        - .callout-tip
        - .callout-note
        - .callout-warning
        - .callout-caution
        - .callout-important
6. Execute Report Generation script again



## TODO
- ~~feat: Add Database Details Report part~~
- ~~feat: Add Server Details Report part~~
- ~~feat: Add AWR Report part~~
- ~~feat: Add color styling~~
- ~~feat: Add data extractor in automation scripts~~
- ~~feat: Implement manual input for findings~~
- feat: Add Executive Summary part
- docs: Generate completed README.md
- refactor: Make data compatible with OneDrive
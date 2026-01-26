# automated-db-health-checkup
Scripts to automatically generate Oracle Database Health Checkup (DBHC) report. Created for SSI-PDS monthly health checkups.

## DBHC Data Analysis and Report Generation (SSI)
0. Ensure `auto-dbhc` generated data is in `dbhc_data` directory
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

2. Execute Data Extractor script
    - Run `python3 data_extractor.py`
3. Execute Report Generation script
    - For Windows:
        Run `generate_reports.bat`
    - For Linux (Ubuntu/Debian):
        Run `bash generate_reports.sh`


## TODO
- ~~feat: Add Database Details Report part~~
- ~~feat: Add Server Details Report part~~
- ~~feat: Add AWR Report part~~
- ~~feat: Add color styling~~
- feat: Add Executive Summary part
- feat: Add data extractor in automation scripts
- docs: Generate completed README.md
- refactor: Make data compatible with OneDrive
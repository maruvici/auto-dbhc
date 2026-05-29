# auto-dbhc-report-generator
A Docker application that automatically generates Oracle Database Health Checkup (DBHC) reports from CSV data files produced by dbhc-data-collector and saves them to a Local/OneDrive folder.

## Prerequisites
- Docker Desktop / Docker Engine
- OneDrive / Local path directory with the following structure:
```
dbhc_onedrive/
├── dbhc_data/
├── dbhc_extracted_data/
├── dbhc_manual/
└── dbhc_reports/
```

## Usage
- Change working directory to report-generator: `cd report-generator`
- Build docker image using Dockerfile: `docker build -t <IMAGE_NAME> .`
- Run docker image with bind mount to OneDrive: `docker run -it -v "<LOCAL_ONEDRIVE_PATH>:/app/dbhc_onedrive" <IMAGE_NAME> [--extract | --generate]`
  - Use `--extract` to only generate extracted data files. Saves output files to `dbhc_extracted_data` folder.
    - When prompted, input the start and end date for the alert logs
  - Use `--generate` to only generate the html and pdf reports. Saves output files to `dbhc_reports` folder.
    - **Requires extracting data first to function properly**
  - Running the command with no options will trigger both data extraction and report generation.
- For manual sections of the report, update the corresponding .docx and .xlsx files in `dbhc_manual` then run the image again.
- To revise the report's metadata (e.g. author, date), update `dbhc_report_qmd/_metadata.qmd`.

## ARCHITECTURE & DESIGN
### Pipeline Lifecycle & Technology Stack
- The generation process executes across three distinct phases, transitioning seamlessly from programmatic extraction and structuring of raw data files to manual DBA review to final document compilation.
```mermaid
flowchart TD
    %% Phase 1: Data Extraction
    subgraph Phase1 [1. Data Extraction Phase]
        direction TB
        In1["Raw Oracle DB metrics<br><b>(dbhc_data/)</b>"] 
        --> Tech1["<b>data_extractor.py</b><br>(Python3 Processing Engine)"]
        --> Out1["Structured Data Files<br><b>(dbhc_extracted_data/)</b>"]
    end

    %% Phase 3: Manual Editing
    subgraph Phase3 [3. Manual Editing Phase]
        direction TB
        In2["DBA Evaluation & Findings"] 
        --> Tech2["<b>Microsoft Word & Excel</b><br>(Manual Document Adjustments)"]
        --> Out2["findings.docx & alert_logs.xlsx<br><b>(dbhc_manual/)</b>"]
    end

    %% Phase 2: Report Generation
    subgraph Phase2 [2. Report-Generation Phase]
        direction TB
        Core["<b>Quarto CLI Core</b><br>Processes .qmd files <br><b>(dbhc_report_qmd/)</b>"]
        
        subgraph Engines [Compilation Engines]
            direction LR
            PDF_Eng["<b>TinyTeX Engine</b><br>(via LuaLaTeX)"]
            HTML_Eng["<b>Python Ecosystem</b><br>(Dynamic ITables Layouts)"]
        end

        subgraph Deliverables [Final Target Output]
            direction LR
            P_Doc["<b>Production PDF Report</b>"]
            H_Doc["<b>Interactive HTML Report</b>"]
        end

        Core --> Engines
        PDF_Eng --> P_Doc
        HTML_Eng --> H_Doc
    end

    %% Flow links pointing to Report Generation
    Out1 -->|Reads extracted data <br><b>via pandas</b>| Core
    Out2 -->|Reads document content <br><b>via pandoc</b>| Core

    %% Phase Styling
    style Phase1 fill:#f9fbe7,stroke:#9e9d24,stroke-width:1px
    style Phase2 fill:#efebe9,stroke:#4e342e,stroke-width:1px
    style Phase3 fill:#e0f2f1,stroke:#00695c,stroke-width:1px
```

### Image Layer Architecture & Execution Flow
- The diagram below details how the layers specified in the Dockerfile assemble to form the runtime environment, and how it maps to host files during execution:
```mermaid
flowchart TD
    %% Host Sync Domain
    subgraph Host [Host System / OneDrive]
        OD_In["Input Volume<br><b>(dbhc_data/, dbhc_extracted_data/, dbhc_manual/)</b>"]
        OD_Out["Output Volume<br><b>(dbhc_reports/)</b>"]
    end

    %% Docker Build Layers
    subgraph DockerImage [Docker Image Layer Blueprints]
        direction TB
        L1["<b>Base OS Layer</b><br>ubuntu:22.04"] 
        --> L2["<b>System Tools & Runtimes</b><br>Python3, pip3, Pandoc, Perl & libfile modules<br><i>(Perl required natively by TeX Live manager)</i>"] 
        --> L3["<b>Quarto Engine Layer</b><br>Quarto CLI Installation (v1.9.38)"] 
        --> L4["<b>Isolated TeX (TinyTeX)</b><br>• Pre-installed packages: luatexbase, luaotfload<br>• Pre-compiled binary path added to system ENV"] 
        --> L5["<b>Optimized Font Cache</b><br>Bakes font maps into image to eliminate rendering delay for pdf</i>"]
        --> L6["<b>Python Dependencies</b><br>pip3 installation of dependencies"]
        --> L7["<b>Workspace Initialization</b><br>• Set WORKDIR to /app<br>• COPY scripts to /app<br>• Grant +x permissions to generate_reports.sh"]
    end

    %% Container Execution Active State
    subgraph ContainerRun [Container Runtime Instance]
        EP["<b>ENTRYPOINT</b><br>/bin/bash /app/generate_reports.sh"]
    end

    %% Mapping connections
    OD_In -->|Mounted to /app at runtime| EP
    L7 -->|Instantiates environment context| EP
    EP -->|Writes compiled PDF & HTML artifacts| OD_Out

    %% Styling
    style Host fill:#efebe9,stroke:#4e342e,stroke-width:1px
    style DockerImage fill:#e8f5e9,stroke:#2e7d32,stroke-width:1px
    style ContainerRun fill:#e1f5fe,stroke:#0277bd,stroke-width:1px
```
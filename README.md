# automated-db-health-checkup
Scripts to automatically generate Oracle Database Health Checkup (DBHC) files and report. Created for SSI-PDS monthly health checkups.

## Usage
### DBHC Data Generation (PDS)
#### DR Database
1. Store `dbhc_dr_collect.sh` in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_dr_collect.sh`
    - Add `--skip-check` to skip file checks

#### PROD Databases
1. Store `dbhc_prod_collect.sh` and sql scripts in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_prod_collect.sh` in node to be checked
    - Add `--skip-check` to skip file checks
    - Specify Production Node number at script start
    - Requires manual creation of AWR HTML Report

### DBHC Data Analysis and Report Generation (SSI)
1. PLACEHOLDER
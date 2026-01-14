# automated-db-health-checkup
Scripts to automatically generate Oracle Database Health Checkup (DBHC) files and report. Created for SSI-PDS monthly health checkups.

## Usage
### DBHC Data Generation (PDS)
#### DR Database
1. Store `dbhc_dr_gen.sh` in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_dr_gen.sh`
    - Add `--skip-check` to skip file checks

#### PROD Databases
1. Store `dbhc_dr_prod.sh` in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_dr_prod.sh`
    - Add `--skip-check` to skip file checks

### DBHC Data Analysis and Report Generation (SSI)
1. ENSURE
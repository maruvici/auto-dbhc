# automated-db-health-checkup
Scripts to automatically generate Oracle Database Health Checkup (DBHC) files. Created for SSI-PDS monthly health checkups.

## Usage

### MODULAR SCRIPTS (Generate each server's data per command)
#### DR Database
1. Store `dbhc_dr_collect.sh` in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_dr_collector.sh`
    - Add `--skip-check` to skip file checks

#### PROD Databases
1. Store `dbhc_prod_collect.sh` and sql scripts in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_prod_collector.sh` in node to be checked
    - Add `--skip-check` to skip file checks
    - Specify Production Node number at script start
    - Requires manual creation of AWR HTML Report

### UNIFIED SCRIPT (Generate everything all at once)
1. Store `dbhc_dr_collector.sh`, `dbhc_prod_collector.sh`, all sql scripts and `dbhc_master_collector.sh` in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_master_collector.sh`
    - Add `--skip-check` to skip file checks
    - Requires manual creation of AWR HTML Report
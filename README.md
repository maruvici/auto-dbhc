# automated-db-health-checkup
Scripts to automatically generate Oracle Database Health Checkup (DBHC) files. Created for SSI-PDS monthly health checkups.

## Usage

### MODULAR SCRIPTS (Generate each server's data per command)
#### DR Database
1. Store `dbhc_dr_collect.sh` in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_dr_collector.sh`
    - Add `-s` to skip file checks

#### PROD Databases
1. Store `dbhc_prod_collect.sh` and sql scripts in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_prod_collector.sh` in node to be checked
    - Add `-s` to skip file checks
    - Either add `-n <node_number>` OR Specify Production Node Numer at Script Start
    - Requires manual creation of AWR HTML Report

### UNIFIED SCRIPT (Generate everything all at once)
1. Store `dbhc_dr_collector.sh`, `dbhc_prod_collector.sh`, all sql scripts and `dbhc_master_collector.sh` in root oracle path (e.g. /home/oracle)
2. Run the script using `bash dbhc_master_collector.sh`
    - Add `-s` to skip file checks
    - Requires manual creation of AWR HTML Report
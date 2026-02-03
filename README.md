# automated-db-health-checkup
Scripts to automatically generate Oracle Database Health Checkup (DBHC) files. Created for SSI-PDS monthly health checkups.

## Usage

### MODULAR SCRIPTS (Generate each server's data per command)
#### DR Database
1. Store `dbhc_dr_collect.sh` in the project root inside the oracle user (e.g. /home/oracle/auto-dbhc-client)
2. Run the script using `bash dbhc_dr_collector.sh`
    - Add `-s` to skip file checks

#### PROD Databases
1. Store `dbhc_prod_collect.sh` and sql scripts in project root inside the oracle user (e.g. /home/oracle/auto-dbhc-client)
2. Run the script using `bash dbhc_prod_collector.sh` in node to be checked
    - Add `-s` to skip file checks
    - Either add `-n <node_number>` OR Specify Production Node Numer at Script Start
    - Requires manual creation of AWR HTML Report
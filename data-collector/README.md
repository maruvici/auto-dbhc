# auto-dbhc-data-collector
Scripts and binaries to automatically generate Oracle Database Health Checkup (DBHC) files. Created for automating one of SSI's clients monthly database health checkups.

## Test Environment
- Oracle DB Servers is simulated using Docker containers. 
- Directory and DB Binary setup is handled by `mock_setup.sh`
    - Data Collection binaries were compiled using Go

## Usage
- Build Mock Servers: `docker compose up -d --build`
- Connect to Node 1: `ssh oracle@172.20.0.11`
- Run Node 1 Collection Binary: `./binaries/prod_collector_bin -s -n 1`
- Disconnect from Node 1: `exit`
- Connect to Node 2: `ssh oracle@172.20.0.12`
- Run Node 2 Collection Binary: `./binaries/prod_collector_bin -s -n 2`
- Disconnect from Node 2: `exit`
- Connect to DR: `ssh oracle@172.20.0.13`
- Run DR Collection Binary: `./binaries/dr_collector_bin -s`
- Disconnect from DR: `exit`
- Copy Outputs from Containers:
```
docker cp pdsbancsv6db1p:/home/oracle/20260206_healthcheck_19C .
docker cp pdsbancsv6db2p:/home/oracle/20260206_healthcheck_19C .
docker cp pdsbancsv6db1d:/home/oracle/20260206_healthcheck_19C .
```
- Archive Outputs: `tar -czvf 20260206_healthcheck_19C.tar.gz 20260206_healthcheck_19C`
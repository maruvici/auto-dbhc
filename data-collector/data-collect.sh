#!/bin/bash

TIMESTAMP=$(date +%Y%m%d)
PASS="oracle"

# Define the variable here so we don't repeat ourselves
ENV_SET="export ORACLE_BASE=/tmp/oracle_mock"

# 1. Start Docker
docker compose up -d --build

# 2. Execute remote commands
# We pass the command as a string at the end of the ssh line
sshpass -p ${PASS} ssh oracle@172.20.0.11 "${ENV_SET} && ./binaries/prod_collector_bin -s -n 1"
sshpass -p ${PASS} ssh oracle@172.20.0.12 "${ENV_SET} && ./binaries/prod_collector_bin -s -n 2"
sshpass -p ${PASS} ssh oracle@172.20.0.13 "${ENV_SET} && ./binaries/dr_collector_bin -s"

# 3. Collect files from Docker containers
docker cp pdsbancsv6db1p:/home/oracle/${TIMESTAMP}_healthcheck_19C .
docker cp pdsbancsv6db2p:/home/oracle/${TIMESTAMP}_healthcheck_19C .
docker cp pdsbancsv6db1d:/home/oracle/${TIMESTAMP}_healthcheck_19C .

# 4. Cleanup and Compress
tar -czvf ${TIMESTAMP}_healthcheck_19C.tar.gz ${TIMESTAMP}_healthcheck_19C

#5 Stop all running docker containers
docker stop $(docker ps -aq)
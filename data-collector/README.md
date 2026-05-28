# auto-dbhc-data-collector
This project is a comprehensive toolkit comprising Go utilities, Shell scripts, and SQL queries designed to automatically gather diagnostic data from Oracle DB Servers. The collected information is structured into CSV files and packaged into a compressed `tar.gz` archive for easy transport.

## Key Features
* **Automated Data Gathering:** Uses a mix of Go binaries, Shell, and SQL to extract deep server diagnostics.
* **Standardized Output:** Saves all data in clean CSV formats, fully compatible with the report-generator for automated reporting.
* **Built-in Mock Lab:** Includes a local Docker-based testing environment to simulate Oracle DB servers without touching production.

## Prerequisites
- Bash/Git Bash
- Docker Desktop / Docker Engine (for testing)
- Docker Compose

## Usage
- Copy `prod_collector_bin` and `dr_collector_bin` to the production and DR servers' oracle home directory, respectively.
- As root user, run `chmod +x prod_collectr_bin` and `chmod +x dr_collector_bin` to grant execute permissions.
- Run the binaries.
- Alternatively, run the binary using ssh: `ssh <USER>@<SERVER> <BINARY>`
- Set timestamp: `TIMESTAMP=$(date +%Y%m%d)`
- Use scp to copy output directory to local host: `scp <USER>@<SERVER>:/home/oracle/${TIMESTAMP}_healthcheck_19C .`
- Archive outputs to a tar.gz archive: `tar -czvf ${TIMESTAMP}_healthcheck_19C.tar.gz ${TIMESTAMP}_healthcheck_19C`

## Testing
- Run `docker-compose up` in the data-collector directory
    - To change container or network configuration, update docker-compose.yml as needed
    - To replace the mock binaries, replace the content of `mock_setup.sh` or use a different script in the Dockerfile

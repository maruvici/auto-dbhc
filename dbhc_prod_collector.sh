#! /bin/bash

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# <-- HANDLE OPTIONS -->
skip_check=false
while getopts "sn:" opt; do
  case $opt in
    s) skip_check=true ;;
    n) node_num="$OPTARG" ;;
    *) exit 1 ;;
  esac
done

# <--- DATA VARIABLES --->
# <--- SHARED VARIABLES --->
timestamp=$(date +%Y%m%d)
odb_version="19C"

# <--- PROD-SPECIFIC VARIABLES --->
instance_arr=( {bancsarc,bancsdb,bancsrep}"${node_num}" )

# <--- NODES TO BE SKIPPED --->
crs_skip=(2)
sql_check_skip=(2)

# <--- PATHS AND DIRECTORIES --->
# <--- SHARED PATHS --->
oracle_path="/home/oracle"
main_dir="${oracle_path}/${timestamp}_healthcheck_${odb_version}"
alert_log_path="${ORACLE_BASE}/diag/rdbms"
crsctl_path="/u01/app/19.0.0/grid/bin/crsctl"

# <--- PROD-SPECIFIC PATHS --->
#ORACLE_BASE: assumed to already be set
node_dir="${main_dir}/NODE${node_num}"
crs_log_path="/u01/app/grid/diag/crs/pdsbancsv6db${node_num}p/crs/trace"
asm_log_path="/u01/app/grid/diag/asm/+asm/+ASM${node_num}/trace"
hc_all_nodes_path="auto-dbhc-collector/hc_all_nodes.sql"
hc_specific_nodes_path="auto-dbhc-collector/hc_specific_nodes.sql"
hc_global_report_path="auto-dbhc-collector/hc_global_reports.sql"

# Some Notes About Script Variables
# - timestamp was previously +"%d%^b%Y"
# - main_dir was previously healthcheck_${timestamp}_NODE${node_num}_${oracledb_version}

# ==========================================
#        MAIN SCRIPT (DO NOT EDIT)
# ==========================================

# <--- Directory Setup --->
cd ${oracle_path}
for instance in ${instance_arr[*]}; do
    mkdir -p "${node_dir}/${instance}"
done
cd "${node_dir}"

# <--- FS Utilization --->
df -h >FS.txt

# <--- CPU Utilization --->
top -b -n 1 >top.txt

# <--- Get Status of CRS Resources --->
if [[ " ${crs_skip[*]} " =~ " ${node_num} " ]]; then
    echo "Skipping CRS Log for Node ${node_num}"
else 
    ${crsctl_path} stat res -t > crs.txt
fi

# <--- Get Status of Listener --->
lsnrctl status > lstnr.txt

# <--- Copy Alert Logs --->
for instance in ${instance_arr[*]}; do
    cp -p "${alert_log_path}/${instance%?}/${instance}/trace/alert_${instance}.log" \
        "${node_dir}/${instance}"
done

# <--- Copy CRS Log --->
cp -p "${crs_log_path}/alert.log" "${node_dir}/crs${node_num}_alert.log"

# <--- Copy ASM Log --->
cp -p "${asm_log_path}/alert_+ASM${node_num}.log" "${node_dir}/asm${node_num}_alert.log"

# <--- Database SQL Checks --->
echo "Running Database SQL Health Checks..."

for instance in ${instance_arr[*]}; do
    echo "Processing Instance: ${instance}"

    export ORACLE_SID="${instance}"

    cd "${main_dir}"
    sqlplus -s / as sysdba "@${oracle_path}/${hc_global_report_path}"
    
    cd "${node_dir}/${instance}"
    sqlplus -s / as sysdba "@${hc_all_nodes_path}"
    
    # Manual AWR Step
    echo "Please generate the AWR report manually for ${instance} now."
    echo "Save it as: ${node_dir}/${instance}/awrrpt_..."
    read -p "Press [Enter] once the AWR HTML file is placed in the folder..."

    if [[ " ${sql_check_skip[*]} " =~ " ${node_num} " ]]; then
        echo "Skipping Some SQL checks for Node ${node_num}"
    else
        sqlplus -s / as sysdba "@${hc_specific_nodes_path}"
    fi
done

# <--- Sanity Check Logic --->
cd "${oracle_path}"
if [ "${skip_check}" = false ]; then
    echo "--- DIRECTORY TREE ---"
    ls -ltrh "${node_dir}"
    
    echo -e "\n--- FILE CONTENTS ---"
    find "${node_dir}" -type f \( -name "*.txt" -o -name "*.log" -o -name "*.csv" \) | while read -r file; do
        echo "--------------------------------------------------"
        echo "FILE: $file"
        echo "--------------------------------------------------"
        cat "$file"
        echo -e "\n"
    done

    while true; do
        read -p "Do the outputs look correct? [Y/N]: " sanity_check
        case "${sanity_check}" in
            [yY] | [yY][eE][sS])
                echo "Validation successful."
                break 
                ;;
            [nN] | [nN][oO])
                echo "Task cancelled by user."
                rm -rf "${node_dir}"
                exit 1
                ;;
            *)
                echo "Invalid input. Please enter yes or no."
                ;;
        esac
    done
else
    echo "Skipping sanity check as requested."
fi
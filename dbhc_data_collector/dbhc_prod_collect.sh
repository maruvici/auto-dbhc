#! /bin/bash

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# <--- DATA VARIABLES --->
read -p "Production Node Number:" node_num
timestamp=$(date +%Y%m%d)
odb_version="19C"
instance_arr=( {bancsarc,bancsdb,bancsrep}"${node_num}" )

# <--- NODES TO BE SKIPPED --->
crs_skip=(2)
sql_check_skip=(2)

# <--- PATHS AND DIRECTORIES --->
#ORACLE_BASE: assumed to already be set
oracle_path="/home/oracle"
main_dir="${timestamp}_healthcheck_NODE${node_num}_${odb_version}"
alert_log_path="${ORACLE_BASE}/diag/rdbms"
crs_log_path="/u01/app/grid/diag/crs/pdsbancsv6db${node_num}p/crs/trace"
asm_log_path="/u01/app/grid/diag/asm/+asm/+ASM${node_num}/trace"
crsctl_path="/u01/app/19.0.0/grid/bin/crsctl"
usr_path="/home/pdskdineros_dba"
hc_all_nodes_path="./hc_all_nodes.sql"
hc_specific_nodes_path="./hc_specific_nodes.sql"
hc_global_report_path="./hc_global_reports.sql"

# <--- ENABLING SANITY CHECK --->
skip_check=false
if [[ "$1" == "--skip-check" ]]; then
    skip_check=true
fi

# Some Notes About Script Variables
# - timestamp was previously +"%d%^b%Y"
# - main_dir was previously healthcheck_${timestamp}_NODE${node_num}_${oracledb_version}

# ==========================================
#        MAIN SCRIPT (DO NOT EDIT)
# ==========================================

# <--- Directory Setup --->
cd ${oracle_path}
for instance in ${instance_arr[*]}; do
    mkdir -p "${main_dir}/${instance}"
done
cd "${oracle_path}/${main_dir}"

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
        "${oracle_path}/${main_dir}/${instance}"
done

# <--- Copy CRS Log --->
cp -p "${crs_log_path}/alert.log" "${oracle_path}/${main_dir}/crs${node_num}_alert.log"

# <--- Copy ASM Log --->
cp -p "${asm_log_path}/alert_+ASM${node_num}.log" "${oracle_path}/${main_dir}/asm${node_num}_alert.log"

# <--- Database SQL Checks --->
echo "Running Database SQL Health Checks..."

for instance in ${instance_arr[*]}; do
    echo "Processing Instance: ${instance}"

    export ORACLE_SID="${instance}"

    cd "${oracle_path}"/"${main_dir}"
    sqlplus -s / as sysdba "@${oracle_path}/${hc_global_report_path}"
    
    cd "${oracle_path}/${main_dir}/${instance}"
    sqlplus -s / as sysdba "@${hc_all_nodes_path}"
    
    # Manual AWR Step
    echo "Please generate the AWR report manually for ${instance} now."
    echo "Save it as: ${oracle_path}/${main_dir}/${instance}/awrrpt_..."
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
    ls -ltrh "${oracle_path}/${main_dir}"
    
    echo -e "\n--- FILE CONTENTS ---"
    find "${main_dir}" -type f \( -name "*.txt" -o -name "*.log" -o -name "*.csv" \) | while read -r file; do
        echo "--------------------------------------------------"
        echo "FILE: $file"
        echo "--------------------------------------------------"
        cat "$file"
        echo -e "\n"
    done

    while true; do
        read -p "Does the outputs look correct? Proceed to compress? [Y/N]: " sanity_check
        case "${sanity_check}" in
            [yY] | [yY][eE][sS])
                echo "Validation successful. Proceeding to compress..."
                break 
                ;;
            [nN] | [nN][oO])
                echo "Task cancelled by user."
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

# <--- tar Archiving --->
tar -czvf "${main_dir}.tar.gz" ${main_dir}

# <--- Move tar File --->
mv ${oracle_path}/${main_dir}.tar.gz ${usr_path}
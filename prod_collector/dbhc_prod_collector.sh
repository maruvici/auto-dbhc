#! /bin/bash

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# <-- HANDLE OPTIONS -->
skip_check=false
while getopts "sn:" opt; do
  case $opt in
    s) interactive_mode=false ;;
    n) node_num="$OPTARG" ;;
    *) echo "Usage: $0 [-s] -n <node_num>"; exit 1 ;;
  esac
done

if [ -z "$node_num" ]; then
    echo "ERROR: Node number (-n) is required."
    exit 1
fi

# <--- DATA VARIABLES --->
# <--- SHARED VARIABLES --->
timestamp=$(date +%Y%m%d)
odb_version="19C"

# <--- PROD-SPECIFIC VARIABLES --->
instance_arr=( {bancsarc,bancsdb,bancsrep}"${node_num}" )

# <--- NODES TO BE SKIPPED --->
crs_skip=(2)
sql_check_skip=(2)

# <--- SPOOL FILES --->
all_nodes_files=(BLOCKING_1.txt BLOCKING_2.txt inactive_session.txt LONGOPS.txt parameter.txt session.txt)
specific_nodes_files=(dba_data_files.txt dba_segments.txt datafiles.txt table_usage.txt LOCKED_OBJECTS.txt tablespace_2.txt tablespace_with_temporaryTBS.txt ASM.txt asm_diskgroup.txt controlfile.txt dba_indexes.txt Vlog.txt uptime.txt invalid_objects.txt check_backup.txt check_if_sync.txt backup_status.txt archivelog_volume.txt select_all_redo_logs.txt)

# <--- VARIABLE CHECK --->  
if [ -z "$ORACLE_BASE" ]; then
    echo "ERROR: ORACLE_BASE is not set. Please export it before running."
    exit 1
fi

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
generate_awrrpt_path="auto-dbhc-collector/generate_awwrpt.sql"
get_snaps_path="auto-dbhc-collector/get_snaps.sql"

# ==========================================
#           HELPER FUNCTIONS
# ==========================================

verify_file() {
    local file_path="$1"
    [ "$interactive_mode" = false ] && return

    echo -e "\n=================================================="
    echo "REVIEWING FILE: ${file_path}"
    echo "=================================================="

    if [[ "${file_path}" == *.html ]]; then
        echo "[HTML File Detected: Content hidden to prevent terminal clutter]"
        echo "Check manually at: ${file_path}"
    elif [ -f "${file_path}" ]; then
        cat "${file_path}"
    else
        echo "Warning: File ${file_path} not found."
    fi

    echo -e "\n=================================================="
    echo "Action: [ENTER] to continue | [X] to abort and delete all"
    read -p ">> " user_input

    if [[ "${user_input}" == "X" || "${user_input}" == "x" ]]; then
        echo "Aborting. Cleaning up ${node_dir}..."
        rm -rf "${node_dir}"
        exit 0
    fi
}

# ==========================================
#        MAIN SCRIPT (DO NOT EDIT)
# ==========================================

echo "Starting Production Health Check for Node ${node_num}..."
[ "$interactive_mode" = true ] && echo "Mode: INTERACTIVE" || echo "Mode: SKIP"

# <--- Directory Setup --->
cd ${oracle_path}
for instance in ${instance_arr[*]}; do
    mkdir -p "${node_dir}/${instance}"
done
cd "${node_dir}"

# <--- FS Utilization --->
df -h >FS.txt
verify_file "${node_dir}/FS.txt"

# <--- CPU Utilization --->
top -b -n 1 | head -n 30 > top.txt
verify_file "${node_dir}/top.txt"

# <--- Get Status of CRS Resources --->
if [[ " ${crs_skip[*]} " =~ " ${node_num} " ]]; then
    echo "Skipping CRS Log for Node ${node_num}"
else 
    ${crsctl_path} stat res -t > crs.txt
    verify_file "${node_dir}/crs.txt"
fi

# <--- Get Status of Listener --->
lsnrctl status > lstnr.txt
verify_file "${node_dir}/lstnr.txt"

# <--- Copy Alert Logs --->
for instance in ${instance_arr[*]}; do
    target_log="${node_dir}/${instance}/alert_${instance}.log"
    cp -p "${alert_log_path}/${instance%?}/${instance}/trace/alert_${instance}.log" \
        "${node_dir}/${instance}"
    verify_file "$target_log"
done

# <--- Copy CRS Log --->
cp -p "${crs_log_path}/alert.log" "${node_dir}/crs${node_num}_alert.log"
verify_file "${node_dir}/crs${node_num}_alert.log"

# <--- Copy ASM Log --->
cp -p "${asm_log_path}/alert_+ASM${node_num}.log" "${node_dir}/asm${node_num}_alert.log"
verify_file "${node_dir}/asm${node_num}_alert.log"

# <--- Database SQL Checks --->
echo "Running Database SQL Health Checks..."

for instance in ${instance_arr[*]}; do
    echo "Processing Instance: ${instance}"

    export ORACLE_SID="${instance}"
    echo "Oracle SID: ${ORACLE_SID}"
    echo "Oracle Home: ${ORACLE_HOME}"

    cd "${main_dir}"
    sqlplus -s / as sysdba "@${oracle_path}/${hc_global_report_path}"
    verify_file "$(ls -t ${main_dir}/*.csv | head -1)"
    
    cd "${node_dir}/${instance}"
    sqlplus -s / as sysdba "@${hc_all_nodes_path}"
    for f in "${all_nodes_files[@]}"; do
        verify_file "${node_dir}/${instance}/$f"
    done
    
    # <--- Automated AWR Section --->
    echo "Generating AWR for ${instance}..."

    # Get most recent Snap IDs
    SNAP_IDS=$(sqlplus -s / as sysdba @"${get_snaps_path}")
    BEGIN_SNAP=$(echo "$SNAP_IDS" | awk '{print $1}')
    END_SNAP=$(echo "$SNAP_IDS" | awk '{print $2}')
    AWR_NAME="${node_dir}/${instance}/awrrpt_${node_num}_${BEGIN_SNAP}_${END_SNAP}.html"    

    # Generate AWR Report
    sqlplus -s / as sysdba @"${generate_awrrpt_path}" \
    "$BEGIN_SNAP" "$END_SNAP" "$AWR_NAME"
    verify_file "$AWR_NAME"

    echo "AWR Report generated: $AWR_NAME"

    if [[ " ${sql_check_skip[*]} " =~ " ${node_num} " ]]; then
        echo "Skipping Some SQL checks for Node ${node_num}"
    else
        sqlplus -s / as sysdba "@${hc_specific_nodes_path}"
        for f in "${specific_nodes_files[@]}"; do
            verify_file "${node_dir}/${instance}/$f"
        done
    fi
done

echo -e "\nProduction Health Check Completed Successfully."
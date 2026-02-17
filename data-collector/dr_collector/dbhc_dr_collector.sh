#! /bin/bash

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# <-- HANDLE OPTIONS -->
interactive_mode=true
while getopts "s" opt; do
  case $opt in
    s) interactive_mode=false ;;
    *) echo "Usage: $0 [-s]"; exit 1 ;;
  esac
done

# <--- DATA VARIABLES --->
# <--- SHARED VARIABLES --->
timestamp=$(date +%Y%m%d)
odb_version="19C"

# <--- DR-SPECIFIC VARIABLES --->
instance_arr=(droprdb drrepdb drarcdb)

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

# <--- DR-SPECIFIC PATHS --->
dr_dir="${main_dir}/DR"
crs_log_path="/u01/app/grid/diag/crs/pdsbancsv6db1d/crs/trace"
asm_log_path="/u01/app/grid/diag/asm/+asm/+ASM/trace"

# ==========================================
#           HELPER FUNCTIONS
# ==========================================

# Function to verify file if interactive mode is on
verify_file() {
    local file_path="$1"
    
    if [ "$interactive_mode" = true ]; then
        echo -e "\n=================================================="
        echo "REVIEWING FILE: ${file_path}"
        echo "=================================================="
        
        # Display content
        if [ -f "${file_path}" ]; then
            cat "${file_path}"
        else
            echo "Error: File not found for review."
        fi
        
        echo -e "\n=================================================="
        echo "Action: [ENTER] to continue | [X] to abort and delete all"
        read -p ">> " user_input
        
        if [[ "${user_input}" == "X" || "${user_input}" == "x" ]]; then
            echo "Aborting execution. Cleaning up directory..."
            rm -rf "${dr_dir}"
            exit 0
        fi
    fi
}

# ==========================================
#        MAIN SCRIPT (DO NOT EDIT)
# ==========================================

echo "Starting DR Health Check Collection..."
[ "$interactive_mode" = true ] && echo "Mode: INTERACTIVE (Default)" || echo "Mode: SKIP (Silent)"

# <--- Directory Setup --->
cd ${oracle_path}
for instance in ${instance_arr[@]}; do
    mkdir -p "${dr_dir}/${instance}"
done
cd "${dr_dir}"

# <--- FS Utilization --->
df -h >FS.txt
verify_file "${dr_dir}/FS.txt"

# <--- CPU Utilization --->
top -b -n 1 | head -n 30 > top.txt
verify_file "${dr_dir}/top.txt"

# <--- Copy Alert Logs --->
for instance in ${instance_arr[*]}; do
    target_file="${dr_dir}/${instance}/alert_${instance}.log"
    cp -p "${alert_log_path}/${instance}/${instance}/trace/alert_${instance}.log" \
        "${dr_dir}/${instance}"
    verify_file "$target_file"
done

# <--- Copy CRS Log --->
cp -p "${crs_log_path}/alert.log" "${dr_dir}/crs_alert.log"
verify_file "${dr_dir}/crs_alert.log"

# <--- Copy ASM Log --->
cp -p "${asm_log_path}/alert_+ASM.log" "${dr_dir}/asm_alert.log"
verify_file "${dr_dir}/asm_alert.log"

# <--- Get Status of CRS Resources --->
${crsctl_path} stat res -t > crs.txt
verify_file "${dr_dir}/crs.txt"

# <--- Get Status of Listener --->
lsnrctl status > lstnr.txt
verify_file "${dr_dir}/lstnr.txt"

echo -e "\nDR Collection Completed Successfully."

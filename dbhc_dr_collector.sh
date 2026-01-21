#! /bin/bash

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# <--- DATA VARIABLES --->
instance_arr=(droprdb drrepdb drarcdb)

# <--- PATHS AND DIRECTORIES --->
#ORACLE_BASE: assumed to already be set
dr_dir="${main_dir}/DR"
crs_log_path="/u01/app/grid/diag/crs/pdsbancsv6db1d/crs/trace"
asm_log_path="/u01/app/grid/diag/asm/+asm/+ASM/trace"

# <--- ENABLING SANITY CHECK --->
skip_check=false
if [[ "$1" == "--skip-check" ]]; then
    skip_check=true
fi

# Some Notes About Script Variables
# - timestamp was previously +"%d%^b%Y"
# - main_dir was previously healthcheck_${timestamp}_DR_${oracledb_version}

# ==========================================
#        MAIN SCRIPT (DO NOT EDIT)
# ==========================================

# <--- Directory Setup --->
cd ${oracle_path}
for instance in ${instance_arr[*]}; do
    mkdir -p "${dr_dir}/${instance}"
done
cd "${dr_dir}"

# <--- FS Utilization --->
df -h >FS.txt

# <--- CPU Utilization --->
top -b -n 1 >top.txt

# <--- Copy Alert Logs --->
for instance in ${instance_arr[*]}; do
    cp -p "${alert_log_path}/${instance}/${instance}/trace/alert_${instance}.log" \
        "${dr_dir}/${instance}"
done

# <--- Copy CRS Log --->
cp -p "${crs_log_path}/alert.log" "${dr_dir}/crs_alert.log"

# <--- Copy ASM Log --->
cp -p "${asm_log_path}/alert_+ASM.log" "${dr_dir}/asm_alert.log"

# <--- Get Status of CRS Resources --->
${crsctl_path} stat res -t > crs.txt

# <--- Get Status of Listener --->
lsnrctl status > lstnr.txt
cd ${oracle_path}

# <--- Sanity Check Logic --->
if [ "${skip_check}" = false ]; then
    echo "--- DIRECTORY TREE ---"
    ls -ltrh ${dr_dir}
    
    echo -e "\n--- FILE CONTENTS ---"
    find "${dr_dir}" -type f \( -name "*.txt" -o -name "*.log" \) | while read -r file; do
        echo "--------------------------------------------------"
        echo "FILE: $file"
        echo "--------------------------------------------------"
        cat "$file"
        echo -e "\n"
    done

    while true; do
        read -p "Does the outputs look correct? [Y/N]: " sanity_check
        case "${sanity_check}" in
            [yY] | [yY][eE][sS])
                echo "Validation successful."
                break 
                ;;
            [nN] | [nN][oO])
                echo "Task cancelled by user."
                rm -rf "${dr_dir}"
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

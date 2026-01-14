#! /bin/bash

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# <--- DATA VARIABLES --->
timestamp=$(date +%Y%m%d)
odb_version="19C"
db_arr=(droprdb drrepdb drarcdb)

# <--- PATHS AND DIRECTORIES --->
#ORACLE_BASE: assumed to already be set
oracle_path="/home/oracle"
main_dir="${timestamp}_healthcheck_DR_${odb_version}"
alert_log_path="${ORACLE_BASE}/diag/rdbms"
crs_log_path="/u01/app/grid/diag/crs/pdsbancsv6db1d/crs/trace"
asm_log_path="/u01/app/grid/diag/asm/+asm/+ASM/trace"
crsctl_path="/u01/app/19.0.0/grid/bin/crsctl"
usr_path="/home/pdskdineros_dba"

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
for db in ${db_arr[*]}; do
    mkdir -p "${main_dir}/${db}"
done
cd ${main_dir}

# <--- FS Utilization --->
df -h >FS.txt

# <--- CPU Utilization --->
top -b -n 1 >top.txt

# <--- Copy Alert Logs --->
for db in ${db_arr[*]}; do
    cp -p "${alert_log_path}/${db}/${db}/trace/alert_${db}.log" \
        "${oracle_path}/${main_dir}/${db}"
done

# <--- Copy CRS Log --->
cp -p "${crs_log_path}/alert.log" "${oracle_path}/${main_dir}/crs_alert.log"

# <--- Copy ASM Log --->
cp -p "${asm_log_path}/alert_+ASM.log" "${oracle_path}/${main_dir}/asm_alert.log"

# <--- Get Status of CRS Resources --->
${crsctl_path} stat res -t > crs.txt

# <--- Get Status of Listener --->
lsnrctl status > lstnr.txt

# <--- Compression --->
cd ..

# <--- Sanity Check Logic --->
if [ "${skip_check}" = false ]; then
    echo "--- DIRECTORY TREE ---"
    ls -ltrh ${main_dir}
    
    echo -e "\n--- FILE CONTENTS ---"
    find "${main_dir}" -type f \( -name "*.txt" -o -name "*.log" \) | while read -r file; do
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

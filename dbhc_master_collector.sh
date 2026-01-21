#! /bin/bash\

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# <--- DATA VARIABLES --->
export timestamp=$(date +%Y%m%d)
export odb_version="19C"

# <--- PATHS AND DIRECTORIES --->
export oracle_path="/home/oracle"
export main_dir="${oracle_path}/${timestamp}_healthcheck_${odb_version}"
export alert_log_path="${ORACLE_BASE}/diag/rdbms"
export crsctl_path="/u01/app/19.0.0/grid/bin/crsctl"
usr_path="/home/pdskdineros_dba"

# <--- ENABLING SANITY CHECK --->
skip_check=false
if [[ "$1" == "--skip-check" ]]; then
    skip_check=true
fi

# ==========================================
#        MAIN SCRIPT (DO NOT EDIT)
# ==========================================

# <--- Script Calls --->
if [[ ${skip_check} == "true" ]]; then
    bash dbhc_dr_collector.sh --skip-check
    bash dbhc_prod_collector.sh --skip-check # For Node 1
    bash dbhc_prod_collector.sh --skip-check # For Node 2
else
    bash dbhc_dr_collector.sh
    bash dbhc_prod_collector.sh
    bash dbhc_prod_collector.sh 
fi

# <--- Archiving Check --->
while true; do
    read -p "Do you wish to archive ${main_dir}? [Y/N]: " sanity_check
    case "${sanity_check}" in
        [yY] | [yY][eE][sS])
            echo "Validation successful. Proceeding to archiving..."
            break 
            ;;
        [nN] | [nN][oO])
            while true; do
                read -p "Do you wish to delete ${main_dir}? [Y/N]: " delete_check
                case "${delete_check}" in
                    [yY] | [yY][eE][sS])
                        echo "Deletion in progress..."
                        rm -rf "${main_dir}"
                        echo "Deletion Completed."
                        exit 1
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
            ;;
        *)
            echo "Invalid input. Please enter yes or no."
            ;;
    esac
done

# <--- tar Archiving --->
tar -czvf "${main_dir}.tar.gz" ${main_dir}

# <--- Move tar File --->
mv ${main_dir}.tar.gz ${usr_path}

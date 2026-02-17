#! /bin/bash\

# ==========================================
#             SCRIPT VARIABLES
# ==========================================
# ADJUST THESE VALUES AS NECESSARY BEFORE RUNNING

# TO MAKE MAINTENANCE EASIER, SHARED VARIABLES AND PATHS
# IN THE CHILDREN SCRIPTS CAN BE DEFINED HERE AS
# EXPORTED VARIABLES.

# <--- DATA VARIABLES --->
timestamp=$(date +%Y%m%d)
odb_version="19C"

# <--- PATHS AND DIRECTORIES --->
oracle_path="/home/oracle"
main_dir="${oracle_path}/${timestamp}_healthcheck_${odb_version}"
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
    bash dbhc_dr_collector.sh -s
    bash dbhc_prod_collector.sh -s -n 1 # For Node 1
    bash dbhc_prod_collector.sh -s -n 2 # For Node 2
else
    bash dbhc_dr_collector.sh
    bash dbhc_prod_collector.sh -n 1
    bash dbhc_prod_collector.sh -n 2
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

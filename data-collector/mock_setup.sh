#!/bin/bash
service ssh start

# Define the base where mocks will live
MOCK_BASE=/tmp/oracle_mock
mkdir -p /home/oracle/binaries

# =================================================================
# 1. ENVIRONMENT SPECIFIC SETUP (DIRECTORY CREATION)
# =================================================================

if [[ "$HOSTNAME" == "pdsbancsv6db1p" ]]; then
    # --- NODE 1 SETUP ---
    echo "Configuring Node 1 Environment..."
    
    # ASM Path for Node 1 (+ASM1)
    mkdir -p /u01/app/grid/diag/asm/+asm/+ASM1/trace
    touch /u01/app/grid/diag/asm/+asm/+ASM1/trace/alert_+ASM1.log

    # CRS Path for Node 1
    mkdir -p /u01/app/grid/diag/crs/pdsbancsv6db1p/crs/trace
    touch /u01/app/grid/diag/crs/pdsbancsv6db1p/crs/trace/alert.log

    # Instance Paths (bancsdb1 inside bancsdb)
    mkdir -p $MOCK_BASE/diag/rdbms/bancsdb/bancsdb1/trace
    touch $MOCK_BASE/diag/rdbms/bancsdb/bancsdb1/trace/alert_bancsdb1.log

    mkdir -p $MOCK_BASE/diag/rdbms/bancsrep/bancsrep1/trace
    touch $MOCK_BASE/diag/rdbms/bancsrep/bancsrep1/trace/alert_bancsrep1.log

    mkdir -p $MOCK_BASE/diag/rdbms/bancsarc/bancsarc1/trace
    touch $MOCK_BASE/diag/rdbms/bancsarc/bancsarc1/trace/alert_bancsarc1.log

elif [[ "$HOSTNAME" == "pdsbancsv6db2p" ]]; then
    # --- NODE 2 SETUP ---
    echo "Configuring Node 2 Environment..."
    
    # ASM Path for Node 2 (+ASM2)
    mkdir -p /u01/app/grid/diag/asm/+asm/+ASM2/trace
    touch /u01/app/grid/diag/asm/+asm/+ASM2/trace/alert_+ASM2.log

    # CRS Path for Node 2
    mkdir -p /u01/app/grid/diag/crs/pdsbancsv6db2p/crs/trace
    touch /u01/app/grid/diag/crs/pdsbancsv6db2p/crs/trace/alert.log

    # Instance Paths (bancsdb2 inside bancsdb)
    mkdir -p $MOCK_BASE/diag/rdbms/bancsdb/bancsdb2/trace
    touch $MOCK_BASE/diag/rdbms/bancsdb/bancsdb2/trace/alert_bancsdb2.log

    mkdir -p $MOCK_BASE/diag/rdbms/bancsarc/bancsarc2/trace
    touch $MOCK_BASE/diag/rdbms/bancsarc/bancsarc2/trace/alert_bancsarc2.log

    mkdir -p $MOCK_BASE/diag/rdbms/bancsrep/bancsrep2/trace
    touch $MOCK_BASE/diag/rdbms/bancsrep/bancsrep2/trace/alert_bancsrep2.log

elif [[ "$HOSTNAME" == "pdsbancsv6db1d" ]]; then
    # --- DR SETUP ---
    echo "Configuring DR Environment..."

    # ASM Path for DR (+ASM, no number)
    mkdir -p /u01/app/grid/diag/asm/+asm/+ASM/trace
    touch /u01/app/grid/diag/asm/+asm/+ASM/trace/alert_+ASM.log

    # CRS Path for DR
    mkdir -p /u01/app/grid/diag/crs/pdsbancsv6db1d/crs/trace
    touch /u01/app/grid/diag/crs/pdsbancsv6db1d/crs/trace/alert.log

    # Instance Paths (droprdb inside droprdb - no stripping of numbers)
    mkdir -p $MOCK_BASE/diag/rdbms/droprdb/droprdb/trace
    touch $MOCK_BASE/diag/rdbms/droprdb/droprdb/trace/alert_droprdb.log

    mkdir -p $MOCK_BASE/diag/rdbms/drrepdb/drrepdb/trace
    touch $MOCK_BASE/diag/rdbms/drrepdb/drrepdb/trace/alert_drrepdb.log

    mkdir -p $MOCK_BASE/diag/rdbms/drarcdb/drarcdb/trace
    touch $MOCK_BASE/diag/rdbms/drarcdb/drarcdb/trace/alert_drarcdb.log
fi


# =================================================================
# 2. CREATE SMART BINARIES (SQLPLUS, CRSCTL, LSNRCTL)
# =================================================================

# Ensure path exists
mkdir -p /u01/app/19.0.0/grid/bin/

# --- Mock crsctl ---
cat <<EOF > /u01/app/19.0.0/grid/bin/crsctl
#!/bin/bash
echo "CRS-4638: Oracle High Availability Services is online"
echo "--------------------------------------------------------------------------------"
echo "NAME           TARGET  STATE        SERVER                   STATE_DETAILS       "
echo "--------------------------------------------------------------------------------"
echo "ora.DATA.dg    ONLINE  ONLINE       $HOSTNAME             STABLE"
EOF
chmod +x /u01/app/19.0.0/grid/bin/crsctl

# --- Mock lsnrctl ---
echo -e "#!/bin/bash\necho 'The listener supports no services'" > /usr/bin/lsnrctl
chmod +x /usr/bin/lsnrctl

# --- Mock SQLPLUS (THE INTELLIGENT PART) ---
# This script generates files based on WHICH node is running it
cat <<EOF > /usr/local/bin/sqlplus
#!/bin/bash

# Files from: hc_global_reports.sql
# Note: The real script names this dynamically based on DB name.
# We will create all variations just to be safe for your test.
if [[ "\$(pwd)" == *"_healthcheck_19C" ]]; then
    touch operating_instance_archivelogswitch_19c.csv
    touch reporting_instance_archivelogswitch_19c.csv
    touch archiving_instance_archivelogswitch_19c.csv
else 
    # Always create the "All Nodes" logs (Common to Node 1 & 2)
    # Files from: hc_all_nodes.sql
    touch BLOCKING_1.txt BLOCKING_2.txt inactive_session.txt LONGOPS.txt parameter.txt session.txt

    # CONDITIONAL LOGIC FOR NODE 1 SPECIFIC FILES
    if [[ "\$HOSTNAME" == "pdsbancsv6db1p" ]]; then
        # Files from: hc_specific_nodes.sql
        # Only Node 1 generates these
        touch dba_data_files.txt dba_segments.txt datafiles.txt table_usage.txt LOCKED_OBJECTS.txt
        touch tablespace_2.txt tablespace_with_temporaryTBS.txt ASM.txt asm_diskgroup.txt
        touch controlfile.txt dba_indexes.txt Vlog.txt uptime.txt invalid_objects.txt 
        touch check_backup.txt check_if_sync.txt backup_status.txt archivelog_volume.txt select_all_redo_logs.txt
    fi
fi

echo "SQL*Plus: Release 19.0.0.0.0 - Production"
echo "Simulating SQL output generation for \$HOSTNAME..."
EOF
chmod +x /usr/local/bin/sqlplus

# =================================================================
# 3. FINAL PERMISSIONS & USER SETUP
# =================================================================

# Add ORACLE_BASE to .bashrc so you don't have to export it manually every time
echo "export ORACLE_BASE=$MOCK_BASE" >> /home/oracle/.bashrc

# Ensure Oracle user owns everything
chown -R oracle:oracle /home/oracle
chown -R oracle:oracle /u01
chown -R oracle:oracle /tmp/oracle_mock

# Keep container alive
tail -f /dev/null
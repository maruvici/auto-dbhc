---Always check if sasama yung SA and DO NOT RUN COALESCE ALWAYS ASK MAAM NINA----------------

sqlplus / as sysdba

/home/oracle/
mkdir healthcheck_09AUG2024_NODE1_19C
cd healthcheck_09AUG2024_NODE1_19C
mkdir bancsdb1
mkdir bancsrep1
mkdir bancsarc1

mkdir healthcheck_09AUG2024_NODE2_19C
cd healthcheck_09AUG2024_NODE2_19C
mkdir bancsdb2
mkdir bancsrep2
mkdir bancsarc2

=============================================================
--------- FS Utilization
=============================================================

df -h > FS.txt

=============================================================
--------- CPU Utilization
=============================================================

top > top.txt

=============================================================
----------- check PROD CRS status - skip Node 2
=============================================================

$ /u01/app/19.0.0/grid/bin/crsctl stat res -t > crs.txt



=============================================================
----------- check PROD listener
=============================================================


On Node1
$ lsnrctl status > lstnr.txt

On Node2
$ lsnrctl status > lstnr.txt



=============================================================
------- get database size -skip node 2
=============================================================

spool dba_data_files.txt
select sum(bytes/1024/1024/1024) "SUM(GB)" from dba_data_files;
spool off;

spool dba_segments.txt
select sum(bytes/1024/1024/1024) "SUM(GB)" from dba_segments;
spool off;

=============================================================
-------- datafiles.txt - skip node 2
=============================================================
spool datafiles.txt
SET LINESIZE 300
SET PAGESIZE 9999
SET VERIFY   OFF
COLUMN tablespace  FORMAT a32             HEADING 'TABLESPACE NAME'
COLUMN filename    FORMAT a58             HEADING 'FILENAME'
COLUMN filesize    FORMAT 9,999,999  	  HEADING 'FILE SIZE'
COLUMN used        FORMAT 9,999,999  	  HEADING 'USED(MB)'
COLUMN pct_used    FORMAT 999             HEADING 'USED(%)'
COLUMN maxbytes    FORMAT 9,999,999	  HEADING 'MAX SIZE'
COLUMN auto        FORMAT a4		  HEADING 'AUTO'
BREAK ON report
COMPUTE SUM OF filesize  ON report
COMPUTE SUM OF used      ON report
COMPUTE AVG OF pct_used  ON report
SELECT /*+ ordered */
    d.tablespace_name                     					tablespace
  , d.file_name                           					filename
  , d.file_id                             					file_id
  , d.bytes/1024/1024                     					filesize
  , NVL((d.bytes - s.bytes)/1024/1024, d.bytes/1024/1024) 			used
  , TRUNC(((NVL((d.bytes - s.bytes) , d.bytes)) / d.bytes) * 100) 		pct_used
  , d.maxbytes/1024/1024							maxbytes
  , d.autoextensible								auto
FROM
    sys.dba_data_files d
  , v$datafile v
  , ( select file_id, SUM(bytes) bytes
      from sys.dba_free_space
      GROUP BY file_id) s
WHERE
      (s.file_id (+)= d.file_id)
  AND (d.file_name = v.name)
UNION
SELECT
    d.tablespace_name                       tablespace 
  , d.file_name                             filename
  , d.file_id                               file_id
  , d.bytes/1024/1024                       filesize
  , NVL(t.bytes_cached/1024/1024, 0)        used
  , TRUNC((t.bytes_cached / d.bytes) * 100) pct_used
  , d.maxbytes/1024/1024							maxbytes
  , d.autoextensible								auto
FROM
    sys.dba_temp_files d
  , v$temp_extent_pool t
  , v$tempfile v
WHERE 
      (t.file_id (+)= d.file_id)
  AND (d.file_id = v.file#)
ORDER BY 1;
spool off;

=============================================================
-----------table usage - skip node 2
=============================================================
spool table_usage.txt
set echo off
prompt "Tablespace Usage"
col free_space  format 99,999,999
col total_space format 99,999,999
col pct_used(%) format 999.99

select tablespace_name "TABLESPACE NAME", free_space "FREE(MB)", sum(bytes/1024/1024) "TOTAL(MB)", 
(sum(bytes/1024/1024) - free_space)/sum(bytes/1024/1024)*100 "pct_used(%)"
from (select a.tablespace_name,a.bytes, (select sum(b.bytes/1024/1024) 
from dba_free_space b where b.tablespace_name = a.tablespace_name) free_space from dba_data_files a) 
having (sum(bytes/1024/1024) - free_space)/sum(bytes/1024/1024)*100 >= 80
group by tablespace_name,free_space
order by 1;
spool off;


=============================================================
---------- tablespace.txt - skip node 2 - DO NOT EXECUTE
=============================================================
#spool tablespace.txt
#SET LINESIZE 300
#SET PAGESIZE 9999
#SET VERIFY   OFF
#COLUMN status      FORMAT a9                 HEADING 'STATUS'
#COLUMN name        FORMAT a28                HEADING 'TABLESPACE NAME'
#COLUMN type        FORMAT a12                HEADING 'TS TYPE'
#COLUMN extent_mgt  FORMAT a10                HEADING 'EXT. MGT.'
#COLUMN segment_mgt FORMAT a9                 HEADING 'SEG. MGT.'
#COLUMN pct_free    FORMAT 999.99             HEADING "FREE(%)" 
#COLUMN mbytes      FORMAT 99,999,999         HEADING "TOTAL(MB)" 
#COLUMN used        FORMAT 99,999,999         HEADING "USED(MB)" 
#COLUMN free        FORMAT 99,999,999         HEADING "FREE(MB)" 
#BREAK ON REPORT
#COMPUTE SUM OF mbytes ON REPORT 
#COMPUTE SUM OF free ON REPORT 
#COMPUTE SUM OF used ON REPORT
#
#SELECT d.status status, d.tablespace_name name, d.contents type, d.extent_management extent_mgt, d.segment_space_management segment_mgt, df.tssize mbytes, (df.tssize - fs.free) used, fs.free free, ROUND(100 * (fs.free / df.tssize),2) pct_free 
#    FROM
#	  dba_tablespaces d,
#	  (SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) tssize FROM dba_data_files GROUP BY tablespace_name) df,
#	  (SELECT tablespace_name, ROUND(SUM(bytes)/1024/1024) free FROM dba_free_space GROUP BY tablespace_name) fs
#    WHERE
#	d.tablespace_name = df.tablespace_name(+)
#    AND d.tablespace_name = fs.tablespace_name(+)
#    AND NOT (d.extent_management like 'LOCAL' AND d.contents like 'TEMPORARY')
#UNION ALL
#SELECT d.status status, d.tablespace_name name, d.contents type, d.extent_management extent_mgt, d.segment_space_management segment_mgt, df.tssize mbytes, (df.tssize - fs.free) used, fs.free free, ROUND(100 * (fs.free / df.tssize),2) pct_free 
#    FROM
#	  dba_tablespaces d,
#	  (select tablespace_name, sum(bytes)/1024/1024 tssize from dba_temp_files group by tablespace_name) df,
#	  (select tablespace_name, sum(bytes_cached)/1024/1024 free from v$temp_extent_pool group by tablespace_name) fs
#    WHERE
#	d.tablespace_name = df.tablespace_name(+)
#    AND d.tablespace_name = fs.tablespace_name(+)
#    AND d.extent_management like 'LOCAL' AND d.contents like 'TEMPORARY'
#ORDER BY 2;
#CLEAR COLUMNS BREAKS COMPUTES
#spool off;

=============================================================
---------- tablespace.txt - skip node 2
=============================================================

spool tablespace_2.txt
set lines 200 pages 200
select
a.tablespace_name,
SUM(a.bytes)/1024/1024 "CurMb",
SUM(decode(b.maxextend, null, A.BYTES/1024/1024, b.maxextend*8192/1024/1024)) "MaxMb",
(SUM(a.bytes)/1024/1024 - round(c."Free"/1024/1024)) "TotalUsed",
(SUM(decode(b.maxextend, null, A.BYTES/1024/1024, b.maxextend*8192/1024/1024)) - (SUM(a.bytes)/1024/1024 - round(c."Free"/1024/1024))) "TotalFree",
round(100*(SUM(a.bytes)/1024/1024 - round(c."Free"/1024/1024))/(SUM(decode(b.maxextend, null, A.BYTES/1024/1024, b.maxextend*8192/1024/1024)))) "UPercent"
from
dba_data_files a,
sys.filext$ b,
(SELECT d.tablespace_name , sum(nvl(c.bytes,0)) "Free" FROM dba_tablespaces d,DBA_FREE_SPACE c where d.tablespace_name = c.tablespace_name(+) group by d.tablespace_name) c
where a.file_id = b.file#(+)
and a.tablespace_name = c.tablespace_name
GROUP by a.tablespace_name, c."Free"/1024
order by round(100*(SUM(a.bytes)/1024/1024 - round(c."Free"/1024/1024))/(SUM(decode(b.maxextend, null, A.BYTES/1024/1024, b.maxextend*8192/1024/1024)))) desc;
spool off;


=============================================================
---------- tablespace_with_temp.txt - skip node 2
=============================================================
spool tablespace_with_temporaryTBS.txt
set lines 200 pages 200
select a.tablespace_name,
nvl(b.tot_used,0)/(1024*1024*1024) "USED (GB)",
a.bytes_alloc/(1024*1024*1024) "TOTAL ALLOCATION (GB)",
a.physical_bytes/(1024*1024*1024) "TOTAL PHYSICAL ALLOCATION (GB)",
round((nvl(b.tot_used,0)/a.bytes_alloc)*100) "% USED"
from ( select tablespace_name,sum(bytes) physical_bytes,sum(decode(autoextensible,'NO',bytes,'YES',maxbytes)) bytes_alloc 
from dba_data_files group by tablespace_name ) a, ( select tablespace_name, sum(bytes) tot_used 
from dba_segments
group by tablespace_name ) b where a.tablespace_name = b.tablespace_name (+)
union all
select a.tablespace_name,
nvl(b.tot_used,0)/(1024*1024*1024) "USED (GB)",
a.bytes_alloc/(1024*1024*1024) "TOTAL ALLOCATION (GB)",
a.physical_bytes/(1024*1024*1024) "TOTAL PHYSICAL ALLOCATION (GB)",
round((nvl(b.tot_used,0)/a.bytes_alloc)*100) "% USED"
from ( select tablespace_name,
sum(bytes) physical_bytes,
sum(decode(autoextensible,'NO',bytes,'YES',maxbytes)) bytes_alloc
from dba_temp_files
group by tablespace_name ) a,
( select tablespace_name, sum(bytes) tot_used
from dba_segments
group by tablespace_name ) b
where a.tablespace_name = b.tablespace_name (+);
spool off;

=============================================================
-------------ASM - skip node 2
=============================================================


spool ASM.txt
SET LINES 200
SET PAGES 9999	
SELECT NAME,
STATE,
TYPE,
TOTAL_MB,
FREE_MB,
REQUIRED_MIRROR_FREE_MB REQ_FREE,
USABLE_FILE_MB USABLE_FILE,
ROUND((((TOTAL_MB-FREE_MB)/TOTAL_MB)*100),2) "% USED"
FROM v$asm_diskgroup;
spool off;


=============================================================
--------- asm_diskgroup.txt - skip node 2
=============================================================
spool asm_diskgroup.txt
COLUMN 	PATH	FORMAT	a25
SELECT GROUP_NUMBER,
		DISK_NUMBER,
		STATE,
		PATH,
		TOTAL_MB,
		FREE_MB,
		NAME
FROM V$ASM_DISK;
spool off;

=============================================================
---------- CHECK CONTROLFILES **/ - skip node 2
=============================================================
spool controlfile.txt
set lines 200
set pages 9999
col name for a50
select * from gv$controlfile;
spool off;

=============================================================
----------- DBA INDEXES - skip node 2
=============================================================
spool dba_indexes.txt
select index_name, table_name, INITIAL_EXTENT, MIN_EXTENTS, MAX_EXTENTS from dba_indexes;
spool off;

=============================================================
------------ Get Vlog -skip node 2
=============================================================
SQL> 
spool Vlog.txt
select * from gv$log;
spool off;



=============================================================
---------- AWR
=============================================================
sqlplus / as sysdba

SQL> @?/rdbms/admin/awrrpti.sql  (BOTH NODES)

---#OPR Aug 01 21-22 5877-5878
---#REP Aug 01 21-22  5835-5836
---#ARC Aug 03 16-18 5789-5791

=============================================================
---------- SESSIONS
=============================================================

spool session.txt
select
   to_char(logon_time,'DD/MM/YYYY HH24:MI:SS')
from
   v$session
where
   sid=1;
spool off;

=============================================================
---------- uptime - skip Node 2
=============================================================   

spool uptime.txt
select INST_ID, NAME, DB_UNIQUE_NAME, DATABASE_ROLE, LOG_MODE, OPEN_MODE, HOST_NAME,logins,to_char(STARTUP_TIME,'DD-MM-YYYY HH24:MI:SS') "UP TIME" from v$database,gv$instance;
spool off;


=============================================================
-----------  DEALLOCATE/COALESCE !!!!! FOR SCHEDULE !!!!! ASK BEFORE EXCUTING --DO NOT RUN!!!!!!
=============================================================

----#spool coalesce.sql
----#SELECT 'alter tablespace '||tablespace_name||' coalesce;'
----#FROM dba_tablespaces;
----#spool off
----#@coalesce.sql
----#
----#spool deallocate_tables.sql
----#SELECT 'alter table '||owner||'.'||table_name||' deallocate unused;' 
----#FROM dba_tables where owner not in ('SYS', 'SYSTEM');
----#spool off
----#@deallocate_tables.sql
----#
----#spool deallocate_indexes.sql
----#SELECT 'alter index '||owner||'.'||index_name||' deallocate unused;' 
----#FROM dba_indexes where owner not in ('SYS', 'SYSTEM');
----#spool off
----#@deallocate_indexes.sql
----#

=============================================================
-----------  invalid_objects.txt - skip node 2
=============================================================
spool invalid_objects.txt
set heading on
set pagesize 56
set feed on
col owner for a30
col object_type for a30
select owner,object_type,count (*) from dba_objects where status='INVALID' group by owner,object_type;
spool off

=============================================================
----------- check_backup.txt - skip node 2
=============================================================
spool check_backup.txt
col TIME_TAKEN_DISPLAY for a20
col INPUT_BYTES_DISPLAY for a20
col OUTPUT_BYTES_DISPLAY for a20
col STATUS for a15
set line 200
select  to_char(start_time,'DD-MM-YYYY HH24:MI:SS') "START_TIME",to_char(end_time,'DD-MM-YYYY HH24:MI:SS') "END_TIME",output_device_type,input_type,status,time_taken_display,input_bytes_display,output_bytes_display
from V$RMAN_BACKUP_JOB_DETAILS where start_time between SYSDATE -4 and SYSDATE order by start_time asc;
spool off;



=============================================================
----------- check_if_sync.txt - skip node 2
=============================================================
spool check_if_sync.txt
select distinct a.name "DBName",b.t1 thread#, b.ps "Last_Seq_On_Primary", c.ss "Last_Seq_Applied_on_Standby", b.ps-c.ss "GAP" from
   (select name from v$database) a,
   (select thread# t1, max(sequence#) ps from v$archived_log where RESETLOGS_CHANGE#=(select  RESETLOGS_CHANGE# from v$database) group by thread#) b,
   (select thread# t2, max(sequence#) ss from v$archived_log where RESETLOGS_CHANGE#=(select  RESETLOGS_CHANGE# from v$database) and applied='YES' group by thread#) c
 where b.t1 = c.t2
/
spool off;


===========================================================
select_all_redo_logs.txt - skip node 2
===========================================================
spool select_all_redo_logs.txt
set linesize 300
set pages 500
column REDOLOG_FILE_NAME format a50
SELECT
a.inst_id,
    a.GROUP#,
    a.THREAD#,
    a.SEQUENCE#,
    a.ARCHIVED,
    a.STATUS,
	b.TYPE,
    b.MEMBER    AS REDOLOG_FILE_NAME,
    (a.BYTES/1024/1024) AS SIZE_MB
FROM gv$log a
JOIN gv$logfile b ON a.Group#=b.Group# 
ORDER BY a.INST_ID,a.GROUP# ASC;
spool off;



===========================================================
prompt ########## BLOCKING ##########
===========================================================
spool BLOCKING_1.txt
select blocking_session, sid, serial#, username, wait_class, seconds_in_wait from gv$session
where blocking_session is not NULL order by blocking_session;
spool off;

===========================================================
prompt ########## BLOCKING2 ##########
===========================================================

spool BLOCKING_2.txt
set pages 999
set line 200
col event for a30
col SQL_TEXT for a60
select  a.blocking_session as block,a.sid, a.serial#, a.sql_id, a.last_call_et/60 as minutes, a.logon_time, a.event,  b.sql_text from v$session a, v$sqlarea b
where a.sql_address=b.address  and a.blocking_session is not NULL order by a.last_call_et desc;
spool off;

===========================================================
prompt ########## LOCKED OBJECTS ########## - skip node 2
===========================================================

spool LOCKED_OBJECTS.txt
SET LINESIZE 145
SET PAGESIZE 9999

COLUMN locking_instance   FORMAT a17   HEAD 'LOCKING|Instance - SID'  JUST LEFT
COLUMN locking_sid        FORMAT a7    HEAD 'LOCKING|SID'             JUST LEFT
COLUMN waiting_instance   FORMAT a17   HEAD 'WAITING|Instance - SID'  JUST LEFT
COLUMN waiting_sid        FORMAT a7    HEAD 'WAITING|SID'             JUST LEFT
COLUMN waiter_lock_type                HEAD 'Waiter Lock Type'        JUST LEFT
COLUMN waiter_mode_req                 HEAD 'Waiter Mode Req.'        JUST LEFT
COLUMN instance_name      FORMAT a12   HEAD 'Instance|Name'           JUST LEFT
COLUMN sid                FORMAT a7    HEAD 'SID'                     JUST LEFT
COLUMN serial_number      FORMAT a7    HEAD 'Serial|Number'           JUST LEFT
COLUMN session_status                  HEAD 'Status'                  JUST LEFT
COLUMN oracle_user        FORMAT a20   HEAD 'Oracle|Username'         JUST LEFT
COLUMN os_username        FORMAT a20   HEAD 'O/S|Username'            JUST LEFT
COLUMN object_owner       FORMAT a15   HEAD 'Object|Owner'            JUST LEFT
COLUMN object_name        FORMAT a30   HEAD 'Object|Name'             JUST LEFT
COLUMN object_type        FORMAT a15   HEAD 'Object|Type'             JUST LEFT

SELECT
    i.instance_name           instance_name
  , RPAD(l.session_id,7)      sid
  , RPAD(s.serial#,7)         serial_number
  , s.status                  session_status
  , l.oracle_username         oracle_user
  , l.os_user_name            os_username
  , o.owner                   object_owner
  , o.object_name             object_name
  , o.object_type             object_type
FROM
    dba_objects       o
  , gv$session        s
  , gv$locked_object  l
  , gv$instance       i
WHERE
      i.inst_id    = l.inst_id
  AND l.inst_id    = s.inst_id
  AND l.session_id = s.sid
  AND o.object_id  = l.object_id
ORDER BY
    s.status,
    l.session_id
/
spool off;

===========================================================
prompt ########## LONGOPS ##########
===========================================================
spool LONGOPS.txt
set line 200
col username for a10
col Long_OPS for a30
col message for a40
select a.username, a.sid, a.serial#, b.sql_text Long_OPS, a.message, a.sofar, a.totalwork,round(a.elapsed_seconds/60, 2) elapsed_mins, round(a.time_remaining/60, 2) Time_remaining_In_Mins
from v$SESSION_LONGOPS a, v$sqlarea b, v$session c
where a.sql_address = b.address
and a.sid = c.sid
and a.serial# = c.serial#
and a.sofar <> a.totalwork;
spool off;

===========================================================
prompt ########## BACKUP STATUS FOR THE LAST 2 DAYS ########## = Skip Node 2
===========================================================

spool backup_status.txt
col TIME_TAKEN_DISPLAY for a20
col INPUT_BYTES_DISPLAY for a20
col OUTPUT_BYTES_DISPLAY for a20
col STATUS for a15
set line 200
select  to_char(start_time,'DD-MM-YYYY HH24:MI:SS') "START_TIME",to_char(end_time,'DD-MM-YYYY HH24:MI:SS') "END_TIME",output_device_type,input_type,status,time_taken_display,input_bytes_display,output_bytes_display
from V$RMAN_BACKUP_JOB_DETAILS where start_time between SYSDATE -3 and SYSDATE order by
start_time asc ;
spool off;

===========================================================
prompt ########## ARCHIVELOG VOLUME FOR THE LAST 7 DAYS ########## - SKIP NODE 2
archivelog_volume.txt
===========================================================
spool archivelog_volume.txt
select trunc(COMPLETION_TIME) TIME, SUM (blocks * block_size)/1024/1024/1024 SIZE_gb FROM V$ARCHIVED_LOG WHERE COMPLETION_TIME between SYSDATE -7 and SYSDATE GROUP BY TRUNC(COMPLETION_TIME) ORDER BY 1 asc;
spool off;

===========================================================
prompt ########## INACTIVE SESSIONS ##########
inactive_session.txt
===========================================================
spool inactive_session.txt
SET LINES 300
SET PAGES 999
COL DATABASE_USER FOR A20
COL LOGON_TIME FOR A25
COL MACHINE FOR A25
COL MODULE FOR A10
COL PROGRAM FOR A40
COL INACTIVE_TIME FOR A15
SELECT S.SID,
 S.SERIAL#,
 S.USERNAME DATABASE_USER,
 TO_CHAR(LOGON_TIME, 'DD-MON-YYYY HH24:MI:SS' ) LOGON_TIME,
 S.STATUS,
 S.MACHINE,
 S.PORT,
 S.PROGRAM,
CASE
WHEN LAST_CALL_ET< 60 THEN LAST_CALL_ET || ' Seconds'
WHEN LAST_CALL_ET< 3600 THEN ROUND(LAST_CALL_ET/60) || ' Minutes'
WHEN LAST_CALL_ET< 86400 THEN ROUND(LAST_CALL_ET/60/60,1) || ' Hour(s)'
ELSE
ROUND(LAST_CALL_ET/60/60/24,1) || ' Day(s)'
END INACTIVE_TIME
FROM
 V$SESSION S, V$PROCESS P
WHERE
S.PADDR=P.ADDR AND
S.STATUS = 'INACTIVE'
ORDER BY LAST_CALL_ET DESC;
spool off;


===========================================================
Pfile
===========================================================

spool parameter.txt
show parameter
spool off;



=============================================================
--------- alert log
=============================================================


----Node 1:

cp -p $ORACLE_BASE/diag/rdbms/bancsdb/bancsdb1/trace/alert_bancsdb1.log /home/oracle/healthcheck_09AUG2024_NODE1_19C/bancsdb1

cp -p $ORACLE_BASE/diag/rdbms/bancsrep/bancsrep1/trace/alert_bancsrep1.log /home/oracle/healthcheck_09AUG2024_NODE1_19C/bancsrep1

cp -p $ORACLE_BASE/diag/rdbms/bancsarc/bancsarc1/trace/alert_bancsarc1.log /home/oracle/healthcheck_09AUG2024_NODE1_19C/bancsarc1


-----Node 2:

cp -p $ORACLE_BASE/diag/rdbms/bancsdb/bancsdb2/trace/alert_bancsdb2.log /home/oracle/healthcheck_09AUG2024_NODE2_19C/bancsdb2

cp -p $ORACLE_BASE/diag/rdbms/bancsrep/bancsrep2/trace/alert_bancsrep2.log /home/oracle/healthcheck_09AUG2024_NODE2_19C/bancsrep2

cp -p $ORACLE_BASE/diag/rdbms/bancsarc/bancsarc2/trace/alert_bancsarc2.log /home/oracle/healthcheck_09AUG2024_NODE2_19C/bancsarc2

============================================================
--------- CRS and ASM alert log
=============================================================

--NODE 1
cp -p /u01/app/grid/diag/crs/pdsbancsv6db1p/crs/trace/alert.log /home/oracle/healthcheck_09AUG2024_NODE1_19C/crs1_alert.log

cp -p /u01/app/grid/diag/asm/+asm/+ASM1/trace/alert_+ASM1.log /home/oracle/healthcheck_09AUG2024_NODE1_19C/asm1_alert.log


--NODE 2
cp -p /u01/app/grid/diag/crs/pdsbancsv6db2p/crs/trace/alert.log /home/oracle/healthcheck_09AUG2024_NODE2_19C/crs2_alert.log

cp -p /u01/app/grid/diag/asm/+asm/+ASM2/trace/alert_+ASM2.log /home/oracle/healthcheck_09AUG2024_NODE2_19C/asm2_alert.log


===========================================================
Compress folder
===========================================================

tar -czvf healthcheck_09AUG2024_NODE1_19C.tar.gz healthcheck_09AUG2024_NODE1_19C

tar -tf healthcheck_09AUG2024_NODE1_19C.tar.gz

tar -czvf healthcheck_09AUG2024_NODE2_19C.tar.gz healthcheck_09AUG2024_NODE2_19C

tar -tf healthcheck_09AUG2024_NODE2_19C.tar.gz

==================================
ARCHIVE LOGSWITCH
====================================

---via RAZOR
---operating_instance_archivelogswitch_19c.csv
---reporting_instance_archivelogswitch_19c.csv
---archiving_instance_archivelogswitch_19c.csv

SELECT d.name,
to_date(l.first_time) DAY,
to_char(sum(decode(to_char(l.first_time,'HH24'),'00',1,0)),'9999') "00",
to_char(sum(decode(to_char(l.first_time,'HH24'),'01',1,0)),'9999') "01",
to_char(sum(decode(to_char(l.first_time,'HH24'),'02',1,0)),'9999') "02",
to_char(sum(decode(to_char(l.first_time,'HH24'),'03',1,0)),'9999') "03",
to_char(sum(decode(to_char(l.first_time,'HH24'),'04',1,0)),'9999') "04",
to_char(sum(decode(to_char(l.first_time,'HH24'),'05',1,0)),'9999') "05",
to_char(sum(decode(to_char(l.first_time,'HH24'),'06',1,0)),'9999') "06",
to_char(sum(decode(to_char(l.first_time,'HH24'),'07',1,0)),'9999') "07",
to_char(sum(decode(to_char(l.first_time,'HH24'),'08',1,0)),'9999') "08",
to_char(sum(decode(to_char(l.first_time,'HH24'),'09',1,0)),'9999') "09",
to_char(sum(decode(to_char(l.first_time,'HH24'),'10',1,0)),'9999') "10",
to_char(sum(decode(to_char(l.first_time,'HH24'),'11',1,0)),'9999') "11",
to_char(sum(decode(to_char(l.first_time,'HH24'),'12',1,0)),'9999') "12",
to_char(sum(decode(to_char(l.first_time,'HH24'),'13',1,0)),'9999') "13",
to_char(sum(decode(to_char(l.first_time,'HH24'),'14',1,0)),'9999') "14",
to_char(sum(decode(to_char(l.first_time,'HH24'),'15',1,0)),'9999') "15",
to_char(sum(decode(to_char(l.first_time,'HH24'),'16',1,0)),'9999') "16",
to_char(sum(decode(to_char(l.first_time,'HH24'),'17',1,0)),'9999') "17",
to_char(sum(decode(to_char(l.first_time,'HH24'),'18',1,0)),'9999') "18",
to_char(sum(decode(to_char(l.first_time,'HH24'),'19',1,0)),'9999') "19",
to_char(sum(decode(to_char(l.first_time,'HH24'),'20',1,0)),'9999') "20",
to_char(sum(decode(to_char(l.first_time,'HH24'),'21',1,0)),'9999') "21",
to_char(sum(decode(to_char(l.first_time,'HH24'),'22',1,0)),'9999') "22",
to_char(sum(decode(to_char(l.first_time,'HH24'),'23',1,0)),'9999') "23"
from
gv$log_history l, gv$database d
where to_date(l.first_time) > sysdate - 40
GROUP by
d.name, to_char(l.first_time,'YYYY-MON-DD'), to_date(l.first_time)
order by to_date(l.first_time);




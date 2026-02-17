-- Initial Setup
SET FEEDBACK OFF
SET TERMOUT OFF
SET TRIMSPOOL ON
SET PAGESIZE 0
SET VERIFY OFF
SET ECHO OFF

-- 1. DBA Data
spool dba_data_files.txt
select sum(bytes/1024/1024/1024) "SUM(GB)" from dba_data_files;
spool off;

-- 2. DBA Segments
spool dba_segments.txt
select sum(bytes/1024/1024/1024) "SUM(GB)" from dba_segments;
spool off;

-- 3. Datafiles
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

-- 4. Table Usage
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

-- 5. Tablespace_2
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

-- 6. Tablespace with Temp
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


-- 7. ASM
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


-- 8. ASM Diskgroup
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

-- 9. Control File
spool controlfile.txt
set lines 200
set pages 9999
col name for a50
select * from gv$controlfile;
spool off;

-- 10. DBA Indexes
spool dba_indexes.txt
select index_name, table_name, INITIAL_EXTENT, MIN_EXTENTS, MAX_EXTENTS from dba_indexes;
spool off;

-- 11. Vlog
spool Vlog.txt
select * from gv$log;
spool off;

-- 12. Uptime
spool uptime.txt
select INST_ID, NAME, DB_UNIQUE_NAME, DATABASE_ROLE, LOG_MODE, OPEN_MODE, HOST_NAME,logins,to_char(STARTUP_TIME,'DD-MM-YYYY HH24:MI:SS') "UP TIME" from v$database,gv$instance;
spool off;

-- 13. Invalid Objects
spool invalid_objects.txt
set heading on
set pagesize 56
set feed on
col owner for a30
col object_type for a30
select owner,object_type,count (*) from dba_objects where status='INVALID' group by owner,object_type;
spool off

-- 14. Backup Check
spool check_backup.txt
col TIME_TAKEN_DISPLAY for a20
col INPUT_BYTES_DISPLAY for a20
col OUTPUT_BYTES_DISPLAY for a20
col STATUS for a15
set line 200
select  to_char(start_time,'DD-MM-YYYY HH24:MI:SS') "START_TIME",to_char(end_time,'DD-MM-YYYY HH24:MI:SS') "END_TIME",output_device_type,input_type,status,time_taken_display,input_bytes_display,output_bytes_display
from V$RMAN_BACKUP_JOB_DETAILS where start_time between SYSDATE -4 and SYSDATE order by start_time asc;
spool off;

-- 15. Sync Check
spool check_if_sync.txt
select distinct a.name "DBName",b.t1 thread#, b.ps "Last_Seq_On_Primary", c.ss "Last_Seq_Applied_on_Standby", b.ps-c.ss "GAP" from
   (select name from v$database) a,
   (select thread# t1, max(sequence#) ps from v$archived_log where RESETLOGS_CHANGE#=(select  RESETLOGS_CHANGE# from v$database) group by thread#) b,
   (select thread# t2, max(sequence#) ss from v$archived_log where RESETLOGS_CHANGE#=(select  RESETLOGS_CHANGE# from v$database) and applied='YES' group by thread#) c
 where b.t1 = c.t2
/
spool off;


-- 16. Redo Logs
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

-- 17. Locked Objects
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

-- 18. Backup Status
spool backup_status.txt
col TIME_TAKEN_DISPLAY for a20
col INPUT_BYTES_DISPLAY for a20
col OUTPUT_BYTES_DISPLAY for a20
col STATUS for a15
set line 200
select  to_char(start_time,'DD-MM-YYYY HH24:MI:SS') "START_TIME",to_char(end_time,'DD-MM-YYYY HH24:MI:SS') "END_TIME",output_device_type,input_type,status,time_taken_display,input_bytes_display,output_bytes_display
from V$RMAN_BACKUP_JOB_DETAILS where start_time between SYSDATE -3 and SYSDATE order by
start_time asc;
spool off;

-- 19. Archive Volume Log
spool archivelog_volume.txt
select trunc(COMPLETION_TIME) TIME, SUM (blocks * block_size)/1024/1024/1024 SIZE_gb FROM V$ARCHIVED_LOG WHERE COMPLETION_TIME between SYSDATE -7 and SYSDATE GROUP BY TRUNC(COMPLETION_TIME) ORDER BY 1 asc;
spool off;

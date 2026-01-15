SET FEEDBACK OFF
SET LINESIZE 300
SET PAGESIZE 999
SET VERIFY OFF

-- 1. BLOCKING_1
SPOOL BLOCKING_1.txt
select blocking_session, sid, serial#, username, wait_class, seconds_in_wait 
from gv$session where blocking_session is not NULL order by blocking_session;
SPOOL OFF;

-- 2. BLOCKING_2
SPOOL BLOCKING_2.txt
set line 200
col event for a30
col SQL_TEXT for a60
select a.blocking_session as block, a.sid, a.serial#, a.sql_id, a.last_call_et/60 as minutes, 
       a.logon_time, a.event, b.sql_text 
from v$session a, v$sqlarea b
where a.sql_address=b.address and a.blocking_session is not NULL 
order by a.last_call_et desc;
SPOOL OFF;

-- 3. INACTIVE_SESSIONS
SPOOL inactive_session.txt
COL DATABASE_USER FOR A20
COL LOGON_TIME FOR A25
COL MACHINE FOR A25
COL PROGRAM FOR A40
COL INACTIVE_TIME FOR A15
SELECT S.SID, S.SERIAL#, S.USERNAME DATABASE_USER, 
       TO_CHAR(LOGON_TIME, 'DD-MON-YYYY HH24:MI:SS') LOGON_TIME,
       S.STATUS, S.MACHINE, S.PORT, S.PROGRAM,
CASE
  WHEN LAST_CALL_ET< 60 THEN LAST_CALL_ET || ' Seconds'
  WHEN LAST_CALL_ET< 3600 THEN ROUND(LAST_CALL_ET/60) || ' Minutes'
  WHEN LAST_CALL_ET< 86400 THEN ROUND(LAST_CALL_ET/60/60,1) || ' Hour(s)'
  ELSE ROUND(LAST_CALL_ET/60/60/24,1) || ' Day(s)'
END INACTIVE_TIME
FROM V$SESSION S, V$PROCESS P
WHERE S.PADDR=P.ADDR AND S.STATUS = 'INACTIVE'
ORDER BY LAST_CALL_ET DESC;
SPOOL OFF;

-- 4. LONGOPS
SPOOL LONGOPS.txt
col username for a10
col Long_OPS for a30
col message for a40
SELECT a.username, a.sid, a.serial#, b.sql_text Long_OPS, a.message, a.sofar, a.totalwork,round(a.elapsed_seconds/60, 2) elapsed_mins, round(a.time_remaining/60, 2) Time_remaining_In_Mins 
FROM v$SESSION_LONGOPS a, v$sqlarea b, v$session c where a.sql_address = b.address
and a.sid = c.sid
and a.serial# = c.serial#
and a.sofar <> a.totalwork;
SPOOL off;

-- 5. PARAMETER FILE
SPOOL parameter.txt
show parameter;
SPOOL OFF;

-- 6. SESSIONS
SPOOL session.txt
select to_char(logon_time,'DD/MM/YYYY HH24:MI:SS') from v$session where sid=1;
SPOOL OFF;


-----------  DEALLOCATE/COALESCE !!!!! FOR SCHEDULE !!!!! ASK BEFORE EXCUTING --DO NOT RUN!!!!!!
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

EXIT;
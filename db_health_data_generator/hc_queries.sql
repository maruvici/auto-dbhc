-- Initial Setup
SET LINESIZE 300
SET PAGESIZE 9999
SET FEEDBACK OFF
SET VERIFY OFF

-- 1. Database Size
SPOOL dba_data_files.txt
SELECT sum(bytes/1024/1024/1024) "SUM(GB)" FROM dba_data_files; [cite: 3]
SPOOL OFF;

-- 2. Tablespace Usage (The 80% threshold query)
SPOOL table_usage.txt
SELECT tablespace_name "TABLESPACE NAME", free_space "FREE(MB)", sum(bytes/1024/1024) "TOTAL(MB)", 
(sum(bytes/1024/1024) - free_space)/sum(bytes/1024/1024)*100 "pct_used(%)"
FROM (select a.tablespace_name,a.bytes, (select sum(b.bytes/1024/1024) 
FROM dba_free_space b WHERE b.tablespace_name = a.tablespace_name) free_space FROM dba_data_files a) 
HAVING (sum(bytes/1024/1024) - free_space)/sum(bytes/1024/1024)*100 >= 80
GROUP BY tablespace_name,free_space
ORDER BY 1; [cite: 3]
SPOOL OFF;

-- 3. Inactive Sessions
SPOOL inactive_session.txt
SELECT S.SID, S.SERIAL#, S.USERNAME DATABASE_USER, STATUS,
CASE 
  WHEN LAST_CALL_ET < 3600 THEN ROUND(LAST_CALL_ET/60) || ' Minutes'
  ELSE ROUND(LAST_CALL_ET/3600,1) || ' Hour(s)'
END INACTIVE_TIME
FROM V$SESSION S
WHERE S.STATUS = 'INACTIVE'
ORDER BY LAST_CALL_ET DESC; [cite: 3]
SPOOL OFF;

-- 4. Archive Log Volume (Last 7 Days)
SPOOL archivelog_volume.txt
SELECT trunc(COMPLETION_TIME) TIME, SUM (blocks * block_size)/1024/1024/1024 SIZE_gb 
FROM V$ARCHIVED_LOG 
WHERE COMPLETION_TIME between SYSDATE -7 and SYSDATE 
GROUP BY TRUNC(COMPLETION_TIME) ORDER BY 1 asc; [cite: 3]
SPOOL OFF;

EXIT;
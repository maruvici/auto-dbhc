SET FEEDBACK OFF
SET LINESIZE 500
SET PAGESIZE 999
SET VERIFY OFF
SET TRIMSPOOL ON
SET TERMOUT OFF
SET MARKUP CSV ON QUOTE OFF

-- 1. Get the current Database Name
COLUMN db_name NEW_VALUE current_db_name
SELECT name AS db_name FROM v$database;

-- 2. Dynamically set the Filename based on the Database Name
COLUMN spool_filename NEW_VALUE target_spool_file
SELECT 
  CASE '&current_db_name'
    WHEN 'BANCSDB'  THEN 'operating_instance_archivelogswitch_19c.csv'
    WHEN 'BANCSREP' THEN 'reporting_instance_archivelogswitch_19c.csv'
    WHEN 'BANCSARC' THEN 'archiving_instance_archivelogswitch_19c.csv'
    ELSE 'unknown_db_archivelogswitch_19c.csv'
  END AS spool_filename
FROM dual;

-- 3. Spool to the correct file
SPOOL &target_spool_file

-- 4. Run the Archive Log Switch Query (From MOP)
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

SPOOL OFF
EXIT;
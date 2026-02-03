-- Initial Setup
SET FEEDBACK OFF
SET TERMOUT OFF
SET VERIFY OFF
SET HEAD OFF
SET PAGESIZE 0

-- 2. If arguments are passed, run the report (Standard MOP logic)
DEFINE report_type = 'html';
DEFINE num_days = '';
DEFINE begin_snap = &1;
DEFINE end_snap = &2;
DEFINE report_name = '&3';

@?/rdbms/admin/awrrpt.sql

EXIT;
import shutil
import re
import io
import sys
import os
import time
import pandas as pd
from pathlib import Path
from typing import Optional
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from datetime import datetime

def parse_alert_log(file: Path, start_date: str, end_date: str) -> Optional[pd.DataFrame]:
    """
    Parses an Oracle alert log to extract notable errors and their timestamps
    strictly within the time window defined by start_date and end_date (YYYYMMDD).
    """
    if not file.exists():
        return None

    # Define the exact time window
    try:
        start_dt = datetime.strptime(start_date, "%Y%m%d")
        # Extend end_dt to the very end of the specified day
        end_dt = datetime.strptime(end_date, "%Y%m%d").replace(hour=23, minute=59, second=59)
    except ValueError as e:
        print(f"Error: Invalid date format. Expected YYYYMMDD. Details: {e}")
        return None

    # Date patterns for Oracle 19c
    iso_pattern = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')
    legacy_pattern = re.compile(r'^\w{3} \w{3} \s?\d{1,2} \d{2}:\d{2}:\d{2} \d{4}')
    
    # Target keywords (will be checked against uppercase strings)
    keywords = ['ORA-', 'WARNING', 'FATAL NI']
    ignore_patterns = ['ORA-0', 'completed successfully', 'LICENSE_SESSIONS_WARNING']

    notable_events = []
    current_timestamp_str = "Unknown"
    current_block = []
    has_notable_keyword = False
    is_within_window = False

    try:
        with open(file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                clean_line = line.strip()
                if not clean_line:
                    continue

                # Check for new timestamp
                is_iso = iso_pattern.match(clean_line)
                is_legacy = legacy_pattern.match(clean_line)

                if is_iso or is_legacy:
                    # 1. Process the PREVIOUS block before resetting
                    if is_within_window and has_notable_keyword and current_block:
                        full_message = "\n".join(current_block)
                        if not any(noise in full_message for noise in ignore_patterns):
                            notable_events.append({
                                "Timestamp": current_timestamp_str,
                                "Message": full_message
                            })
                    
                    # 2. Reset for the NEW block
                    current_timestamp_str = clean_line
                    current_block = []
                    has_notable_keyword = False
                    
                    # 3. Determine if the NEW timestamp is within our window
                    try:
                        if is_iso:
                            # Parse ISO 8601 (e.g., 2026-02-06T14:22:33.123+08:00)
                            ts_part = clean_line.split('+')[0].split('.')[0]
                            this_dt = datetime.fromisoformat(ts_part)
                        else:
                            # Parse Legacy (e.g., Fri Feb 06 14:22:33 2026)
                            this_dt = datetime.strptime(clean_line, "%a %b %d %H:%M:%S %Y")
                        
                        is_within_window = (start_dt <= this_dt <= end_dt)
                    except (ValueError, IndexError):
                        is_within_window = False
                    
                    continue

                # If we are currently in a valid time window, collect the lines
                if is_within_window:
                    current_block.append(clean_line)
                    # Use uppercase for case-insensitive matching
                    upper_line = clean_line.upper()
                    if any(key in upper_line for key in keywords):
                        has_notable_keyword = True

            # Save the final block if it meets criteria
            if is_within_window and has_notable_keyword and current_block:
                full_message = "\n".join(current_block)
                if not any(noise in full_message for noise in ignore_patterns):
                    notable_events.append({
                        "Timestamp": current_timestamp_str,
                        "Message": full_message
                    })

    except Exception as e:
        print(f"  -> Error parsing alert log {file.name}: {e}")
        return None

    return pd.DataFrame(notable_events) if notable_events else None

def aggregate_alert_logs(df: pd.DataFrame) -> Optional[pd.DataFrame]:
    """
    Takes the parsed alert logs DataFrame and returns a summary table 
    containing unique errors, their occurrence counts, and timestamps.
    """
    if df is None or df.empty:
        return None

    # Group by the exact message text
    # The lambda function joins all timestamps into a single readable string
    aggregated = df.groupby('Message', as_index=False).agg(
        Occurrences=('Timestamp', 'count'),
        Timestamps=('Timestamp', lambda x: ' | '.join(x))
    )
    
    # Sort by the most frequent occurrences first
    aggregated = aggregated.sort_values(by='Occurrences', ascending=False).reset_index(drop=True)
    
    # Reorder columns for a logical flow in your final Excel file
    aggregated = aggregated[['Message', 'Occurrences', 'Timestamps']]
    
    return aggregated

def parse_spool_file(file: Path) -> Optional[pd.DataFrame]:
    """
    Parses an Oracle SQL*Plus spool file into a pandas DataFrame.
    """
    if not file.exists():
        return None

    try:
        with open(file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception:
        return None

    # 1. Cleaning and Pre-processing
    clean_lines = []
    data_started = False
    
    # Check for empty result
    full_content = "".join(lines)
    if "no rows selected" in full_content:
        return None

    # Filter out SQL commands and noise
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("SQL>") or stripped == "" or "selected." in stripped:
            continue
        clean_lines.append(line)

    if not clean_lines:
        return None

    # 2. Find Separator (---)
    separator_index = -1
    separator_pattern = re.compile(r'^[\s\-]+$')
    
    for i, line in enumerate(clean_lines):
        if separator_pattern.match(line) and '-' in line:
            separator_index = i
            break
            
    if separator_index == -1:
        return None

    # 3. Determine Column Specifications (col_specs) from Separator
    separator_line = clean_lines[separator_index]
    col_specs = []
    
    # Find start/end of dash sequences
    current_start = -1
    for i, char in enumerate(separator_line):
        if char == '-':
            if current_start == -1:
                current_start = i
        elif char == ' ':
            if current_start != -1:
                col_specs.append((current_start, i))
                current_start = -1
    
    if current_start != -1: 
        col_specs.append((current_start, len(separator_line.rstrip())))

    if not col_specs:
        return None

    # 4. Extract Header and Data
    header_line = clean_lines[separator_index - 1]
    raw_data_lines = clean_lines[separator_index + 1:]
    
    if not raw_data_lines:
        return None

    # 5. Unwrap Logic (Handling multi-line rows)
    unwrapped_lines = []
    first_col_start, first_col_end = col_specs[0]
    current_row = ""
    
    for line in raw_data_lines:
        first_col_content = line[first_col_start:first_col_end].strip()
        
        if first_col_content:
            if current_row:
                unwrapped_lines.append(current_row)
            current_row = line.strip('\n') # Start new row
        else:
            current_row += " " + line.strip()
            
    # Append the last accumulated row
    if current_row:
        unwrapped_lines.append(current_row)

    # 6. Create DataFrame
    try:
        # Parse Header
        headers = []
        for (start, end) in col_specs:
            h_val = header_line[start:end].strip() if start < len(header_line) else ""
            headers.append(h_val)

        # Parse Data
        data_str = "\n".join(unwrapped_lines)
        df = pd.read_fwf(
            io.StringIO(data_str), 
            colspecs=col_specs, 
            names=headers,
            header=None # We supply names manually
        )
        
        return df

    except Exception as e:
        # In case of parsing errors
        print(f"Error parsing {file.name}: {e}")
        return None

def parse_fs_file(file: Path) -> Optional[pd.DataFrame]:
    """
    Parses a fs file into a Pandas DataFrame
    """  
    try:
        with open(file, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        if not lines:
            return None

        columns = ["Filesystem", "Size", "Used", "Avail", "Use%", "Mounted_on"]
        rows = []
        
        i = 1 # Skip the header line
        while i < len(lines):
            line = lines[i].strip()
            if not line:
                i += 1
                continue
                
            parts = line.split()
            
            # Standard 6-column row
            if len(parts) == 6:
                rows.append(parts)
            
            # Handle wrapped filesystem names (long LVM paths)
            elif len(parts) == 1 and i + 1 < len(lines):
                next_parts = lines[i+1].split()
                combined = [parts[0]] + next_parts
                if len(combined) == 6:
                    rows.append(combined)
                    i += 1 
            
            i += 1

        return pd.DataFrame(rows, columns=columns)

    except Exception as e:
        print(f"Error: {e}")
        return None

def parse_awrrpt_file(file: Path) -> Optional[pd.DataFrame]:
    """
    Parses AWR HTML by targeting specific table summary attributes.
    """
    if not file.exists():
        return None

    try:
        with open(file, 'r', encoding='utf-8') as f:
            soup = BeautifulSoup(f, 'html.parser')

        all_data = []

        # 1 & 2: Database Instance Info (Two tables share this summary)
        db_info_tables = soup.find_all('table', {'summary': "This table displays database instance information"})
        for table in db_info_tables:
            for row in table.find_all('tr'):
                cols = [ele.get_text(strip=True) for ele in row.find_all(['td', 'th'])]
                if cols: all_data.append(cols)
            all_data.append([]) # Spacer

        # 3: Host Information
        host_table = soup.find('table', {'summary': "This table displays host information"})
        if host_table:
            for row in host_table.find_all('tr'):
                cols = [ele.get_text(strip=True) for ele in row.find_all(['td', 'th'])]
                if cols: all_data.append(cols)
            all_data.append([]) # Spacer

        # 4: Snapshot Information
        snap_table = soup.find('table', {'summary': "This table displays snapshot information"})
        if snap_table:
            for row in snap_table.find_all('tr'):
                cols = [ele.get_text(strip=True) for ele in row.find_all(['td', 'th'])]
                if cols: all_data.append(cols)
        
        # Insert requested section header between table 4 and 5
        all_data.append([]) # Spacer
        all_data.append(["Instance Efficiency Percentages (Target 100%)"])

        # 5: Instance Efficiency Percentages
        eff_table = soup.find('table', {'summary': "This table displays instance efficiency percentages"})
        if eff_table:
            for row in eff_table.find_all('tr'):
                cols = [ele.get_text(strip=True) for ele in row.find_all(['td', 'th'])]
                if cols: all_data.append(cols)

        if not all_data:
            return None

        # Standardize row lengths for Pandas
        max_cols = max(len(r) for r in all_data)
        padded_data = [r + [""] * (max_cols - len(r)) for r in all_data]
        
        return pd.DataFrame(padded_data)

    except Exception as e:
        print(f"Error parsing AWR: {e}")
        return None

def run_etl(src_path, dest_path, start_date, end_date):
    """
    Main function to process all defined files.
    """

    # Get Two Latest Health Checks for Data Comparison
    data_dir = Path(f"{src_path}")
    data_subdirs = sorted([p for p in data_dir.iterdir() if p.is_dir()])
    if len(data_subdirs) < 2:
        raise SystemExit("Error: Not enough data directories found to compare.")
    prev_dir = data_subdirs[-2]
    curr_dir = data_subdirs[-1]

    # Create Timestampped Directory in CSV Directory
    timestamp = curr_dir.name.split("_")[0]
    output_dir = Path(f"{dest_path}") / timestamp
    output_dir.mkdir(parents=True, exist_ok=True)

    # Move Already Existing CSV Files in CSV directory
    for csv_path in curr_dir.glob("*.csv"):
        shutil.copy(str(csv_path), str(output_dir))

    server_arr = ("DR", "NODE1", "NODE2")
    instance_arr = ("bancsarc", "bancsdb", "bancsrep")
    alert_instance_arr = [
        'drarcdb', 'droprdb', 'drrepdb',
        'bancsarc1', 'bancsdb1', 'bancsrep1',
        'bancsarc2', 'bancsdb2', 'bancsrep2'
    ]
    files_map = {} # Configuration: Input Path -> Output CSV

    # Node 1 Only
    for instance in instance_arr:
        node_path_prev = prev_dir / "NODE1" / f"{instance}1"
        node_path_curr = curr_dir / "NODE1" / f"{instance}1"

        # Data Size - Previous
        files_map[node_path_prev / "dba_data_files.txt"] = output_dir / f"db_size_physical_{instance}_prev.csv"
        files_map[node_path_prev / "dba_segments.txt"] = output_dir / f"db_size_logical_{instance}_prev.csv"
        
        # Data Size - Current
        files_map[node_path_curr / "dba_data_files.txt"] = output_dir / f"db_size_physical_{instance}_cur.csv"
        files_map[node_path_curr / "dba_segments.txt"] = output_dir / f"db_size_logical_{instance}_cur.csv"

        # Reports
        files_map[node_path_curr / "tablespace_2.txt"]   = output_dir / f"tablespace_{instance}.csv"
        files_map[node_path_curr / "controlfile.txt"]    = output_dir / f"controlfile_{instance}.csv"
        files_map[node_path_curr / "check_backup.txt"]   = output_dir / f"backup_{instance}.csv"
        files_map[node_path_curr / "check_if_sync.txt"]  = output_dir / f"data_guard_{instance}.csv"
        files_map[node_path_curr / "invalid_objects.txt"] = output_dir / f"invalid_objects_{instance}.csv"
    
    # ASM Report
    files_map[curr_dir / "NODE1" / "bancsarc1" / "ASM.txt" ] = output_dir / f"asm.csv"

    # Server Reports
    for server in server_arr:
        if server != "NODE2":
            files_map[curr_dir / f"{server}" / "crs.txt" ] = output_dir / f"crs_{server}.txt"
        files_map[curr_dir / f"{server}" / "FS.txt" ] = output_dir / f"fs_util_{server}.csv"
        files_map[curr_dir / f"{server}" / "lstnr.txt" ] = output_dir / f"lstnr_{server}.txt"

    # AWRRPT Reports
    for i in range(1, 3):
        current_node = f"NODE{i}"
        for instance in instance_arr:
            target_dir = curr_dir / current_node / f"{instance}{i}"
            # Find all awrrpt in target_dir
            matching_files = list(target_dir.glob(f"awrrpt_{i}_*.html"))  
            if matching_files:
                # Take the first match found
                actual_file = matching_files[0]
                files_map[actual_file] = output_dir / f"awrrpt_{current_node}_{instance}.csv"
            else:
                print(f"No AWRRPT.html file found in {target_dir}")

    # Alert Log Reports
    for i, instance in enumerate(alert_instance_arr):
        if i >= 0 and i < 3:
            server = "DR"
        elif i >= 3 and i < 6:
            server = "NODE1"
        else:
            server = "NODE2"
        files_map[curr_dir / f"{server}" / instance / f"alert_{instance}.log" ] = output_dir / f"alert_logs_raw_{instance}.csv"

    print("--- Starting ETL Process ---")
    for input_file, output_file in files_map.items():
        print(f"Processing {str(input_file)}...")

        if re.search(r"crs", str(output_file)) or re.search(f"lstnr", str(output_file)):
            try:
                shutil.copy2(input_file, output_file)
                print(f"  -> Saved to {output_file}")
                continue
            except Exception as e:
                print(f"Error during copy: {e}")
        elif re.search(r"fs", str(output_file)):
            df = parse_fs_file(input_file)
        elif re.search(f"awrrpt", str(output_file)):
            df = parse_awrrpt_file(input_file)
        elif re.search(f"alert", str(output_file)):
            df = parse_alert_log(input_file, start_date, end_date)
        else:
            df = parse_spool_file(input_file)
        
        if df is not None:
            df.to_csv(output_file, index=False)
            print(f"  -> Saved to {output_file} ({len(df)} rows)")
            if "alert_logs_raw_" in output_file.name:
                instance_name = output_file.stem.replace("alert_logs_raw_", "")
                filtered_logs_file = output_dir / f"alert_logs_filtered_{instance_name}.csv"

                filtered_df = aggregate_alert_logs(df)
                print(f"  -> Generating filtered logs for {instance_name}...")
                filtered_df.to_csv(filtered_logs_file, index=False)
                print(f"  -> Filtered logs saved to {filtered_logs_file.name}")
        else:
            # Create a dummy CSV with error message or empty to prevent file-not-found errors
            print(f"  -> Warning: Could not parse {input_file}")
            pd.DataFrame({'Status': ['No Data Found.']}).to_csv(output_file, index=False)
    
    print("--- ETL Complete ---")

if __name__ == "__main__":
    if len(sys.argv) > 4:
        print(f"Accessing data at: {sys.argv[1]}")
        run_etl(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
        print(f"Extracted data stored in: {sys.argv[2]}")
    else:
        print("Please follow the format: python3 script_name [src_path] [dest_path] [start_date] [end_date]")
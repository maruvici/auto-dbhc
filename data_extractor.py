import shutil
import re
import io
import pandas as pd
from pathlib import Path
from typing import Optional, List, Tuple

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

def run_etl():
    """
    Main function to process all defined files.
    """

    # Get Two Latest Health Checks for Data Comparison
    data_dir = Path("./dbhc_data")
    data_subdirs = sorted([p for p in data_dir.iterdir() if p.is_dir()])
    if len(data_subdirs) < 2:
        raise SystemExit("Error: Not enough data directories found to compare.")
    prev_dir = data_subdirs[-2]
    curr_dir = data_subdirs[-1]

    # Create Timestampped Directory in CSV Directory
    timestamp = curr_dir.name.split("_")[0]
    csv_dir = Path('./dbhc_csv') / timestamp
    csv_dir.mkdir(parents=True, exist_ok=True)

    # Move Already Existing CSV Files in CSV directory
    for csv_path in curr_dir.glob("*.csv"):
        shutil.copy(str(csv_path), str(csv_dir))

    server_arr = ("DR", "NODE1", "NODE2")
    instance_arr = ("bancsarc", "bancsdb", "bancsrep")
    files_map = {} # Configuration: Input Path -> Output CSV

    # Node 1 Only
    for instance in instance_arr:
        node_path_prev = prev_dir / "NODE1" / f"{instance}1"
        node_path_curr = curr_dir / "NODE1" / f"{instance}1"

        # Data Size - Previous
        files_map[node_path_prev / "dba_data_files.txt"] = csv_dir / f"db_size_physical_{instance}_prev.csv"
        files_map[node_path_prev / "dba_segments.txt"] = csv_dir / f"db_size_logical_{instance}_prev.csv"
        
        # Data Size - Current
        files_map[node_path_curr / "dba_data_files.txt"] = csv_dir / f"db_size_physical_{instance}_cur.csv"
        files_map[node_path_curr / "dba_segments.txt"] = csv_dir / f"db_size_logical_{instance}_cur.csv"

        # Reports
        files_map[node_path_curr / "tablespace_2.txt"]   = csv_dir / f"tablespace_{instance}.csv"
        files_map[node_path_curr / "controlfile.txt"]    = csv_dir / f"controlfile_{instance}.csv"
        files_map[node_path_curr / "check_backup.txt"]   = csv_dir / f"backup_{instance}.csv"
        files_map[node_path_curr / "check_if_sync.txt"]  = csv_dir / f"data_guard_{instance}.csv"
        files_map[node_path_curr / "invalid_objects.txt"] = csv_dir / f"invalid_objects_{instance}.csv"
    
    # ASM Report
    files_map[curr_dir / "NODE1" / "bancsarc1" / "ASM.txt" ] = csv_dir / f"asm.csv"

    # Server Reports (Not Yet Parseable)
    # for server in server_arr:
        # files_map[curr_dir / f"{server}" / "FS.txt" ] = csv_dir / f"fs_util_{server}.csv"
        # files_map[curr_dir / f"{server}" / "crs.txt" ] = csv_dir / f"crs_{server}.csv"
        # files_map[curr_dir / f"{server}" / "lstnr.txt" ] = csv_dir / f"lstnr_{server}.csv"
    
    # AWR Report (Not Yet Parseable)
    # for i in range(1,3):
    #     for instance in instance_arr:
    #         files_map[curr_dir / f"NODE{i}" / f"{instance}{i}" / awrrpt_{i}] = csv_dir / f"awr_{instance}{i}"

    print("--- Starting ETL Process ---")
    for input_file, output_csv in files_map.items():
        print(f"Processing {str(input_file)}...")
        df = parse_spool_file(input_file)
        
        if df is not None:
            # We save even empty DFs so the QMD file doesn't crash when looking for the file
            df.to_csv(output_csv, index=False)
            print(f"  -> Saved to {output_csv} ({len(df)} rows)")
        else:
            # Create a dummy CSV with error message or empty to prevent file-not-found errors
            print(f"  -> Warning: Could not parse {input_file}")
            pd.DataFrame({'Status': ['Parse Error']}).to_csv(output_csv, index=False)
    
    print("--- ETL Complete ---")

if __name__ == "__main__":
    run_etl()
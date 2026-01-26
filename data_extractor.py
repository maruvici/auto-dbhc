import shutil
import re
import io
import pandas as pd
from pathlib import Path
from typing import Optional
from bs4 import BeautifulSoup

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

def parse_crs_file(file: Path) -> Optional[pd.DataFrame]:
    if not file.exists():
        return None

    try:
        with open(file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception:
        return None

    data = []
    current_res = None
    current_row = None
    
    # Updated to include INTERMEDIATE state found in your logs
    status_pattern = re.compile(r'(ONLINE|OFFLINE|INTERMEDIATE)\s+(ONLINE|OFFLINE|INTERMEDIATE)')

    for line in lines:
        raw_line = line.strip('\n')
        stripped = raw_line.strip()

        if stripped in ["Local Resources", "Cluster Resources"]:
            if current_row:
                data.append(current_row)
                current_row = None
            data.append({"Resource": f"{stripped.upper()}", "Instance": "", "Target": "", "State": "", "Server": "", "Details": ""})
            continue

        if not stripped or "---" in stripped or "Name" in stripped:
            continue

        if raw_line.startswith('ora.'):
            if current_row:
                data.append(current_row)
                current_row = None
            current_res = stripped
            continue

        if status_pattern.search(raw_line):
            if current_row:
                data.append(current_row)

            # Robust parsing: handle single spaces between Target/State
            parts = re.split(r'\s{2,}', stripped)
            
            if parts[0].isdigit():
                inst = parts.pop(0)
                # If Target and State are merged (e.g., 'OFFLINE OFFLINE'), split them
                if len(parts) > 0 and ' ' in parts[0]:
                    status_parts = parts[0].split()
                    parts = status_parts + parts[1:]
                
                # Safe assignment to prevent IndexError
                target = parts[0] if len(parts) > 0 else ""
                state = parts[1] if len(parts) > 1 else ""
                server = parts[2] if len(parts) > 2 else ""
                details = " ".join(parts[3:]) if len(parts) > 3 else ""
            else:
                if len(parts) > 0 and ' ' in parts[0]:
                    status_parts = parts[0].split()
                    parts = status_parts + parts[1:]
                
                inst = "N/A"
                target = parts[0] if len(parts) > 0 else ""
                state = parts[1] if len(parts) > 1 else ""
                server = parts[2] if len(parts) > 2 else ""
                details = " ".join(parts[3:]) if len(parts) > 3 else ""

            current_row = {"Resource": current_res, "Instance": inst, "Target": target, "State": state, "Server": server, "Details": details}
        
        elif current_row and raw_line.startswith(' '):
            current_row["Details"] += " " + stripped

    if current_row:
        data.append(current_row)

    return pd.DataFrame(data)

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

def parse_lstnr_file(file: Path) -> Optional[pd.DataFrame]:
    """
    Parses an lstnr file a pandas DataFrame.
    """
    if not file.exists():
        return None

    try:
        with open(file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception:
        return None

    data = []
    metadata = {}
    current_service = None
    section = None

    for line in lines:
        raw_line = line.strip('\n')
        stripped = line.strip()

        if not stripped or "---" in stripped or "LSNRCTL for" in stripped or "Copyright" in stripped:
            continue

        # 1. Capture Basic Metadata
        if ":" in stripped and section is None:
            # Handle lines like 'Alias  LISTENER' or 'Version TNSLSNR...'
            parts = re.split(r'\s{2,}', stripped)
            if len(parts) >= 2:
                metadata[parts[0]] = parts[1]
            elif "Connecting to" in stripped:
                metadata["Connection"] = stripped.replace("Connecting to ", "")
            continue

        # 2. Section Detection
        if "Listening Endpoints Summary..." in stripped:
            section = "ENDPOINTS"
            continue
        elif "Services Summary..." in stripped:
            section = "SERVICES"
            continue
        elif "The command completed successfully" in stripped:
            break

        # 3. Parse Endpoints
        if section == "ENDPOINTS" and "(DESCRIPTION=" in stripped:
            data.append({
                "Type": "Endpoint",
                "Name": "Listener",
                "Status": "LISTENING",
                "Details": stripped
            })

        # 4. Parse Services and Instances
        if section == "SERVICES":
            # Service header: Service "bancsarc" has 1 instance(s).
            service_match = re.search(r'Service "([^"]+)"', stripped)
            if service_match:
                current_service = service_match.group(1)
                continue
            
            # Instance line: Instance "bancsarc1", status READY, has 1 handler(s)...
            if current_service and "Instance" in stripped:
                inst_match = re.search(r'Instance "([^"]+)", status ([^,]+)', stripped)
                if inst_match:
                    inst_name = inst_match.group(1)
                    status = inst_match.group(2)
                    data.append({
                        "Type": "Service Instance",
                        "Name": f"{current_service} ({inst_name})",
                        "Status": status,
                        "Details": stripped
                    })

    if not data:
        return None

    # Merge metadata into the rows for context
    df = pd.DataFrame(data)
    for key, value in metadata.items():
        df[key] = value

    return df

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

    # CRS Report
    files_map[curr_dir / "NODE1" / "crs.txt" ] = csv_dir / f"crs.csv"

    # Server Reports
    for server in server_arr:
        if server != "NODE2":
            files_map[curr_dir / f"{server}" / "crs.txt" ] = csv_dir / f"crs_{server}.csv"
        files_map[curr_dir / f"{server}" / "FS.txt" ] = csv_dir / f"fs_util_{server}.csv"
        files_map[curr_dir / f"{server}" / "lstnr.txt" ] = csv_dir / f"lstnr_{server}.csv"

    # AWRRPT Reports (Not Yet Parseable)
    for i in range(1, 3):
        current_node = f"NODE{i}"
        for instance in instance_arr:
            target_dir = curr_dir / current_node / f"{instance}{i}"
            # Find all awrrpt in target_dir
            matching_files = list(target_dir.glob(f"awrrpt_{i}_*.html"))  
            if matching_files:
                # Take the first match found
                actual_file = matching_files[0]
                files_map[actual_file] = csv_dir / f"awrrpt_{current_node}_{instance}.csv"
            else:
                print(f"No AWRRPT.html file found in {target_dir}")

    print("--- Starting ETL Process ---")
    for input_file, output_csv in files_map.items():
        print(f"Processing {str(input_file)}...")

        if re.search(r"crs", str(output_csv)):
            df = parse_crs_file(input_file)
        elif re.search(r"fs", str(output_csv)):
            df = parse_fs_file(input_file)
        elif re.search(f"lstnr", str(output_csv)):
            df = parse_lstnr_file(input_file)
        elif re.search(f"awrrpt", str(output_csv)):
            df = parse_awrrpt_file(input_file)
        else:
            df = parse_spool_file(input_file)
        
        if df is not None:
            # We save even empty DFs so the QMD file doesn't crash when looking for the file
            df.to_csv(output_csv, index=False)
            print(f"  -> Saved to {output_csv} ({len(df)} rows)")
        else:
            # Create a dummy CSV with error message or empty to prevent file-not-found errors
            print(f"  -> Warning: Could not parse {input_file}")
            pd.DataFrame({'Status': ['No Data Found.']}).to_csv(output_csv, index=False)
    
    print("--- ETL Complete ---")

if __name__ == "__main__":
    run_etl()
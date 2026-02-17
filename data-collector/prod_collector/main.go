package main

import (
	"bufio"
	"embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// This directive embeds your SQL files into the binary at compile time
//go:embed *.sql
var sqlScripts embed.FS

var interactiveMode = true
var nodeDir string
var mainDir string

func main() {
	// --- 1. HANDLE OPTIONS ---
	nodeNum := ""
	for i, arg := range os.Args {
		if arg == "-s" {
			interactiveMode = false
		}
		if arg == "-n" && i+1 < len(os.Args) {
			nodeNum = os.Args[i+1]
		}
	}

	if nodeNum == "" {
		fmt.Println("ERROR: Node number (-n) is required.")
		os.Exit(1)
	}

	// --- 2. DATA VARIABLES ---
	timestamp := time.Now().Format("20060102")
	oracleBase := os.Getenv("ORACLE_BASE")
	if oracleBase == "" {
		fmt.Println("ERROR: ORACLE_BASE not set.")
		os.Exit(1)
	}

	oraclePath := "/home/oracle"
	mainDir = filepath.Join(oraclePath, timestamp+"_healthcheck_19C")
	nodeDir = filepath.Join(mainDir, "NODE"+nodeNum)
	instances := []string{"bancsarc" + nodeNum, "bancsdb" + nodeNum, "bancsrep" + nodeNum}

	// Cluster Paths
	crsctlPath := "/u01/app/19.0.0/grid/bin/crsctl"
	crsLogPath := fmt.Sprintf("/u01/app/grid/diag/crs/pdsbancsv6db%sp/crs/trace/alert.log", nodeNum)
	asmLogPath := fmt.Sprintf("/u01/app/grid/diag/asm/+asm/+ASM%s/trace/alert_+ASM%s.log", nodeNum, nodeNum)

	fmt.Printf("Starting Production Health Check for Node %s...\n", nodeNum)

	// --- 3. DIRECTORY SETUP ---
	for _, inst := range instances {
		os.MkdirAll(filepath.Join(nodeDir, inst), 0755)
	}

	// --- 4. OS & CLUSTER COLLECTION ---
	runAndVerify(filepath.Join(nodeDir, "FS.txt"), "df", "-h")
	runAndVerify(filepath.Join(nodeDir, "top.txt"), "sh", "-c", "top -b -n 1 | head -n 30")

	if nodeNum != "2" { // Equivalent to crs_skip=(2)
		runAndVerify(filepath.Join(nodeDir, "crs.txt"), crsctlPath, "stat", "res", "-t")
	}
	runAndVerify(filepath.Join(nodeDir, "lstnr.txt"), "lsnrctl", "status")

	// --- 5. LOG COLLECTION ---
	for _, inst := range instances {
		// instance%? logic: bancsdb1 -> bancsdb
		dbName := inst[:len(inst)-1]
		src := filepath.Join(oracleBase, "diag/rdbms", dbName, inst, "trace", "alert_"+inst+".log")
		dst := filepath.Join(nodeDir, inst, "alert_"+inst+".log")
		exec.Command("cp", "-p", src, dst).Run()
		verifyFile(dst)
	}
	
	copyAndVerify(crsLogPath, filepath.Join(nodeDir, "crs"+nodeNum+"_alert.log"))
	copyAndVerify(asmLogPath, filepath.Join(nodeDir, "asm"+nodeNum+"_alert.log"))

	// --- 6. SQL EXECUTION ---
	allNodesFiles := []string{"BLOCKING_1.txt", "BLOCKING_2.txt", "inactive_session.txt", "LONGOPS.txt", "parameter.txt", "session.txt"}
	specNodesFiles := []string{"dba_data_files.txt", "dba_segments.txt", "datafiles.txt", "table_usage.txt", "LOCKED_OBJECTS.txt", "tablespace_2.txt", "tablespace_with_temporaryTBS.txt", "ASM.txt", "asm_diskgroup.txt", "controlfile.txt", "dba_indexes.txt", "Vlog.txt", "uptime.txt", "invalid_objects.txt", "check_backup.txt", "check_if_sync.txt", "backup_status.txt", "archivelog_volume.txt", "select_all_redo_logs.txt"}

	for _, inst := range instances {
		fmt.Printf("\n--- Processing Database Instance: %s ---\n", inst)

		// A. Global Reports
		runSQL(inst, "hc_global_reports.sql", mainDir)
		// Check the generated CSV
		csvs, _ := filepath.Glob(filepath.Join(mainDir, "*.csv"))
		if len(csvs) > 0 {
			verifyFile(csvs[len(csvs)-1]) // Verify newest CSV
		}

		// B. All Nodes
		runSQL(inst, "hc_all_nodes.sql", filepath.Join(nodeDir, inst))
		for _, f := range allNodesFiles {
			verifyFile(filepath.Join(nodeDir, inst, f))
		}

		// C. AWR Generation
		runAWR(inst, nodeNum, filepath.Join(nodeDir, inst))

		// D. Specific Nodes (Skip node 2)
		if nodeNum != "2" {
			runSQL(inst, "hc_specific_nodes.sql", filepath.Join(nodeDir, inst))
			for _, f := range specNodesFiles {
				verifyFile(filepath.Join(nodeDir, inst, f))
			}
		}
	}

	fmt.Println("\nProduction Health Check Completed successfully.")
}

// --- HELPER FUNCTIONS ---

func runSQL(sid string, scriptPath string, workingDir string) {
	content, _ := sqlScripts.ReadFile(scriptPath)
	cmd := exec.Command("sqlplus", "-s", "/", "as", "sysdba")
	cmd.Dir = workingDir
	cmd.Env = append(os.Environ(), "ORACLE_SID="+sid)
	cmd.Stdin = strings.NewReader(string(content))
	cmd.Run()
}

func runAWR(sid string, nodeNum string, workingDir string) {
	// 1. Get Snaps
	snapContent, _ := sqlScripts.ReadFile("get_snaps.sql")
	// Note: For AWR complex logic, passing args to stdin requires careful formatting
	// Simulating the bash logic:
	snapCmd := exec.Command("sqlplus", "-s", "/", "as", "sysdba")
	snapCmd.Env = append(os.Environ(), "ORACLE_SID="+sid)
	snapCmd.Stdin = strings.NewReader(string(snapContent))
	snapIDs, _ := snapCmd.Output()
	
	ids := strings.Fields(string(snapIDs))
	if len(ids) < 2 { return }

	awrName := filepath.Join(workingDir, fmt.Sprintf("awrrpt_%s_%s_%s.html", sid, ids[0], ids[1]))
	
	// 2. Generate AWR
	awrContent, _ := sqlScripts.ReadFile("generate_awrrpt.sql")
	// Prepend defines to the script
	fullAwrScript := fmt.Sprintf("define 1=%s\ndefine 2=%s\ndefine 3=%s\n%s", ids[0], ids[1], awrName, string(awrContent))
	
	genCmd := exec.Command("sqlplus", "-s", "/", "as", "sysdba")
	genCmd.Env = append(os.Environ(), "ORACLE_SID="+sid)
	genCmd.Stdin = strings.NewReader(fullAwrScript)
	genCmd.Run()

	verifyFile(awrName)
}

func verifyFile(path string) {
	if !interactiveMode { return }

	fmt.Printf("\n==================================================\n")
	fmt.Printf("REVIEWING FILE: %s\n", path)
	fmt.Printf("==================================================\n")

	if strings.HasSuffix(path, ".html") {
		fmt.Println("[HTML Content hidden for readability]")
	} else {
		content, _ := os.ReadFile(path)
		fmt.Println(string(content))
	}

	content, err := os.ReadFile(path)
	if err != nil {
		fmt.Println("Error: File not found for review.")
	} else {
		fmt.Println(string(content))
	}

	fmt.Printf("\nAction: [ENTER] to continue | [X] to abort and delete\n>> ")
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	if strings.ToUpper(strings.TrimSpace(input)) == "X" {
		os.RemoveAll(nodeDir)
		fmt.Println("Cleaned up and exited.")
		os.Exit(0)
	}
}

func runAndVerify(path string, name string, args ...string) {
	out, _ := exec.Command(name, args...).CombinedOutput()
	os.WriteFile(path, out, 0644)
	verifyFile(path)
}

func copyAndVerify(src string, dst string) {
	exec.Command("cp", "-p", src, dst).Run()
	verifyFile(dst)
}
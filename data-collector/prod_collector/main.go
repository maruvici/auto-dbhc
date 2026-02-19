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

// This directive now looks in the current directory (prod_collector) for SQL files
//go:embed *.sql
var sqlScripts embed.FS

var (
	interactiveMode = true
	nodeNum         string
	odbVersion      = "19C"
	oraclePath      = "/home/oracle"
	crsSkip         = []string{"2"}
	sqlCheckSkip    = []string{"2"}

	allNodesFiles = []string{
		"BLOCKING_1.txt", "BLOCKING_2.txt", "inactive_session.txt",
		"LONGOPS.txt", "parameter.txt", "session.txt",
	}

	specNodesFiles = []string{
		"dba_data_files.txt", "dba_segments.txt", "datafiles.txt",
		"table_usage.txt", "LOCKED_OBJECTS.txt", "tablespace_2.txt",
		"tablespace_with_temporaryTBS.txt", "ASM.txt", "asm_diskgroup.txt",
		"controlfile.txt", "dba_indexes.txt", "Vlog.txt", "uptime.txt",
		"invalid_objects.txt", "check_backup.txt", "check_if_sync.txt",
		"backup_status.txt", "archivelog_volume.txt", "select_all_redo_logs.txt",
	}
)

func main() {
	// 1. HANDLE OPTIONS
	for i := 1; i < len(os.Args); i++ {
		arg := os.Args[i]
		if arg == "-s" {
			interactiveMode = false
		} else if arg == "-n" && i+1 < len(os.Args) {
			nodeNum = os.Args[i+1]
			i++
		}
	}

	if nodeNum == "" {
		fmt.Println("ERROR: Node number (-n) is required.")
		os.Exit(1)
	}

	// 2. DATA VARIABLES
	timestamp := time.Now().Format("20060102")
	instanceArr := []string{"bancsarc" + nodeNum, "bancsdb" + nodeNum, "bancsrep" + nodeNum}

	oracleBase := os.Getenv("ORACLE_BASE")
	if oracleBase == "" {
		fmt.Println("ERROR: ORACLE_BASE is not set.")
		os.Exit(1)
	}

	mainDir := filepath.Join(oraclePath, fmt.Sprintf("%s_healthcheck_%s", timestamp, odbVersion))
	nodeDir := filepath.Join(mainDir, "NODE"+nodeNum)
	crsLogPath := fmt.Sprintf("/u01/app/grid/diag/crs/pdsbancsv6db%sp/crs/trace", nodeNum)
	asmLogPath := fmt.Sprintf("/u01/app/grid/diag/asm/+asm/+ASM%s/trace", nodeNum)

	fmt.Printf("Starting Production Health Check for Node %s...\n", nodeNum)

	// 3. DIRECTORY SETUP
	// Mirroring the 'cd ${oracle_path}' from bash
	os.Chdir(oraclePath)
	for _, inst := range instanceArr {
		os.MkdirAll(filepath.Join(nodeDir, inst), 0755)
	}
	// Mirroring 'cd ${node_dir}' from bash
	os.Chdir(nodeDir)

	// 4. OS COLLECTIONS
	runAndRedirect("FS.txt", "df", "-h")
	verifyFile(filepath.Join(nodeDir, "FS.txt"), nodeDir)

	runAndRedirect("top.txt", "sh", "-c", "top -b -n 1 | head -n 30")
	verifyFile(filepath.Join(nodeDir, "top.txt"), nodeDir)

	if !contains(crsSkip, nodeNum) {
		runAndRedirect("crs.txt", "/u01/app/19.0.0/grid/bin/crsctl", "stat", "res", "-t")
		verifyFile(filepath.Join(nodeDir, "crs.txt"), nodeDir)
	}

	runAndRedirect("lstnr.txt", "lsnrctl", "status")
	verifyFile(filepath.Join(nodeDir, "lstnr.txt"), nodeDir)

	// 5. COPY LOGS
	for _, inst := range instanceArr {
		dbName := inst[:len(inst)-1]
		src := filepath.Join(oracleBase, "diag/rdbms", dbName, inst, "trace", "alert_"+inst+".log")
		dst := filepath.Join(nodeDir, inst)
		exec.Command("cp", "-p", src, dst).Run()
		verifyFile(filepath.Join(dst, "alert_"+inst+".log"), nodeDir)
	}

	exec.Command("cp", "-p", filepath.Join(crsLogPath, "alert.log"), filepath.Join(nodeDir, "crs"+nodeNum+"_alert.log")).Run()
	verifyFile(filepath.Join(nodeDir, "crs"+nodeNum+"_alert.log"), nodeDir)

	exec.Command("cp", "-p", filepath.Join(asmLogPath, "alert_+ASM"+nodeNum+".log"), filepath.Join(nodeDir, "asm"+nodeNum+"_alert.log")).Run()
	verifyFile(filepath.Join(nodeDir, "asm"+nodeNum+"_alert.log"), nodeDir)

	// 6. DATABASE SQL CHECKS
	for _, inst := range instanceArr {
		fmt.Printf("\n--- Processing Instance: %s ---\n", inst)
		os.Setenv("ORACLE_SID", inst)

		// A. Global Reports (cd main_dir)
		os.Chdir(mainDir)
		runEmbeddedSQL("hc_global_reports.sql")
		checkLatestCSV(mainDir, nodeDir)

		// B. All Nodes (cd node_dir/instance)
		instPath := filepath.Join(nodeDir, inst)
		os.Chdir(instPath)
		runEmbeddedSQL("hc_all_nodes.sql")
		for _, f := range allNodesFiles {
			verifyFile(filepath.Join(instPath, f), nodeDir)
		}

		// C. AWR Generation
		generateAWR(inst, instPath, nodeDir)

		// D. Specific Nodes
		if !contains(sqlCheckSkip, nodeNum) {
			runEmbeddedSQL("hc_specific_nodes.sql")
			for _, f := range specNodesFiles {
				verifyFile(filepath.Join(instPath, f), nodeDir)
			}
		}
	}

	fmt.Println("\nProduction Health Check Completed Successfully.")
}

// --- HELPERS ---

func runEmbeddedSQL(scriptName string) {
	content, err := sqlScripts.ReadFile(scriptName)
	if err != nil {
		fmt.Printf("Internal Error: Could not find embedded script %s\n", scriptName)
		return
	}
	cmd := exec.Command("sqlplus", "-s", "/", "as", "sysdba")
	cmd.Stdin = strings.NewReader(string(content))
	cmd.Run()
}

func generateAWR(sid, instPath, nodeDir string) {
	fmt.Printf("Generating AWR for %s...\n", sid)
	
	snapScript, _ := sqlScripts.ReadFile("get_snaps.sql")
	snapCmd := exec.Command("sqlplus", "-s", "/", "as", "sysdba")
	snapCmd.Stdin = strings.NewReader(string(snapScript))
	out, _ := snapCmd.Output()
	
	snaps := strings.Fields(string(out))
	if len(snaps) < 2 { return }

	awrName := filepath.Join(instPath, fmt.Sprintf("awrrpt_%s_%s_%s.html", nodeNum, snaps[0], snaps[1]))
	
	awrScript, _ := sqlScripts.ReadFile("generate_awrrpt.sql")
	// Passing variables to SQLPlus Stdin via defining them at the top of the script
	fullScript := fmt.Sprintf("define 1=%s\ndefine 2=%s\ndefine 3=%s\n%s", snaps[0], snaps[1], awrName, string(awrScript))
	
	genCmd := exec.Command("sqlplus", "-s", "/", "as", "sysdba")
	genCmd.Stdin = strings.NewReader(fullScript)
	genCmd.Run()
	
	verifyFile(awrName, nodeDir)
}

func checkLatestCSV(dir, nodeDir string) {
	files, _ := filepath.Glob(filepath.Join(dir, "*.csv"))
	if len(files) == 0 { return }
	latest := files[0]
	for _, f := range files {
		if fi, _ := os.Stat(f); fi != nil {
			if curr, _ := os.Stat(latest); fi.ModTime().After(curr.ModTime()) {
				latest = f
			}
		}
	}
	verifyFile(latest, nodeDir)
}

func verifyFile(path string, cleanupDir string) {
	if !interactiveMode { return }
	fmt.Printf("\n==================================================\n")
	fmt.Printf("REVIEWING FILE: %s\n", path)
	fmt.Printf("==================================================\n")
	if strings.HasSuffix(path, ".html") {
		fmt.Println("[HTML File Detected: Content hidden to prevent terminal clutter]")
	} else {
		content, _ := os.ReadFile(path)
		fmt.Print(string(content))
	}
	fmt.Printf("\nAction: [ENTER] to continue | [X] to abort and delete all\n>> ")
	
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	if strings.ToUpper(strings.TrimSpace(input)) == "X" {
		os.RemoveAll(cleanupDir)
		os.Exit(0)
	}
}

func runAndRedirect(outFile string, name string, args ...string) {
	out, _ := exec.Command(name, args...).CombinedOutput()
	os.WriteFile(outFile, out, 0644)
}

func contains(slice []string, val string) bool {
	for _, item := range slice { if item == val { return true } }
	return false
}
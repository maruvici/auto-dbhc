package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var interactiveMode = true
var drDir string

func main() {
	// 1. Handle Options
	for _, arg := range os.Args {
		if arg == "-s" {
			interactiveMode = false
		}
	}

	// 2. Variables
	timestamp := time.Now().Format("20060102")
	odbVersion := "19C"
	oraclePath := "/home/oracle"
	oracleBase := os.Getenv("ORACLE_BASE")

	if oracleBase == "" {
		fmt.Println("ERROR: ORACLE_BASE is not set. Please export it before running.")
		os.Exit(1)
	}

	mainDir := filepath.Join(oraclePath, fmt.Sprintf("%s_healthcheck_%s", timestamp, odbVersion))
	drDir = filepath.Join(mainDir, "DR")
	instanceArr := []string{"droprdb", "drrepdb", "drarcdb"}

	crsLogPath := "/u01/app/grid/diag/crs/pdsbancsv6db1d/crs/trace"
	asmLogPath := "/u01/app/grid/diag/asm/+asm/+ASM/trace"
	crsctlPath := "/u01/app/19.0.0/grid/bin/crsctl"

	fmt.Println("Starting DR Health Check Collection...")
	if interactiveMode {
		fmt.Println("Mode: INTERACTIVE (Default)")
	} else {
		fmt.Println("Mode: SKIP (Silent)")
	}

	// 3. Directory Setup
	for _, inst := range instanceArr {
		os.MkdirAll(filepath.Join(drDir, inst), 0755)
	}

	// 4. Main Execution
	runAndVerify(filepath.Join(drDir, "FS.txt"), "df", "-h")
	runAndVerify(filepath.Join(drDir, "top.txt"), "sh", "-c", "top -b -n 1 | head -n 30")

	for _, inst := range instanceArr {
		targetFile := filepath.Join(drDir, inst, "alert_"+inst+".log")
		src := filepath.Join(oracleBase, "diag/rdbms", inst, inst, "trace", "alert_"+inst+".log")
		exec.Command("cp", "-p", src, targetFile).Run()
		verifyFile(targetFile)
	}

	copyAndVerify(filepath.Join(crsLogPath, "alert.log"), filepath.Join(drDir, "crs_alert.log"))
	copyAndVerify(filepath.Join(asmLogPath, "alert_+ASM.log"), filepath.Join(drDir, "asm_alert.log"))

	runAndVerify(filepath.Join(drDir, "crs.txt"), crsctlPath, "stat", "res", "-t")
	runAndVerify(filepath.Join(drDir, "lstnr.txt"), "lsnrctl", "status")

	fmt.Println("\nDR Collection Completed Successfully.")
}

func verifyFile(path string) {
	if !interactiveMode {
		return
	}

	fmt.Printf("\n==================================================\n")
	fmt.Printf("REVIEWING FILE: %s\n", path)
	fmt.Printf("==================================================\n")

	content, err := os.ReadFile(path)
	if err != nil {
		fmt.Println("Error: File not found for review.")
	} else {
		fmt.Println(string(content))
	}

	fmt.Printf("\n==================================================\n")
	fmt.Printf("Action: [ENTER] to continue | [X] to abort and delete all\n>> ")

	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(strings.ToUpper(input))

	if input == "X" {
		fmt.Println("Aborting execution. Cleaning up directory...")
		os.RemoveAll(drDir)
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
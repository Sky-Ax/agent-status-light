package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"go.bug.st/serial"
)

const serialWriteReleaseWait = 5 * time.Second

func runBridge(args []string) error {
	cfg, err := parseBridgeFlags(args)
	if err != nil {
		return err
	}

	if cfg.listPorts {
		return printPorts()
	}
	if cfg.openSerial == nil {
		cfg.openSerial = openSerialWithRetry
	}

	if cfg.statusPath == "" {
		root, err := findProjectRoot()
		if err != nil {
			return err
		}
		cfg.statusPath = filepath.Join(root, "data", "codex-status.json")
	}

	if _, err := os.Stat(cfg.statusPath); err != nil {
		return fmt.Errorf("status file is not available: %s: %w", cfg.statusPath, err)
	}

	var port serial.Port
	if !cfg.dryRun {
		if cfg.portName == "" {
			cfg.portName, err = choosePort()
			if err != nil {
				return err
			}
		}

		port, err = cfg.openSerial(cfg.portName, cfg.baudRate)
		if err != nil {
			return fmt.Errorf("open serial port %s failed: %w", cfg.portName, err)
		}
		defer func() {
			if port != nil {
				_ = port.Close()
			}
		}()
		logf("serial connected: %s @ %d", cfg.portName, cfg.baudRate)
		waitForDeviceSerialStartup(cfg)
	} else {
		if cfg.portName == "" {
			cfg.portName = "DRY-RUN"
		}
		logf("dry run enabled; serial writes will be printed only")
	}

	lastSent := ""
	lastMod := time.Time{}

	for {
		state, modTime, err := readStateIfChanged(cfg.statusPath, lastMod)
		if err != nil {
			logf("read status failed: %v", err)
		} else if state != "" {
			lastMod = modTime
			if state != lastSent {
				if err := sendStateWithRecovery(&port, cfg, state); err != nil {
					return err
				}
				lastSent = state
			}
		}

		if cfg.once {
			return nil
		}

		time.Sleep(cfg.interval)
	}
}

func parseBridgeFlags(args []string) (bridgeConfig, error) {
	var cfg bridgeConfig
	var intervalMs int
	var openDelayMs int
	var writeTimeoutMs int

	flags := flag.NewFlagSet("bridge", flag.ContinueOnError)
	flags.StringVar(&cfg.statusPath, "status", "", "Codex status JSON path. Default: <project>\\data\\codex-status.json")
	flags.StringVar(&cfg.portName, "port", "", "Serial port, for example COM4. Default: auto detect when possible")
	flags.IntVar(&cfg.baudRate, "baud", 115200, "Serial baud rate")
	flags.IntVar(&intervalMs, "interval", 300, "Status polling interval in milliseconds")
	flags.IntVar(&openDelayMs, "open-delay", 1200, "Delay after opening serial port in milliseconds")
	flags.IntVar(&writeTimeoutMs, "write-timeout", 3000, "Serial write timeout in milliseconds")
	flags.BoolVar(&cfg.once, "once", false, "Send current status once and exit")
	flags.BoolVar(&cfg.dryRun, "dry-run", false, "Print serial messages without opening a serial port")
	flags.BoolVar(&cfg.listPorts, "list-ports", false, "List serial ports and exit")
	if err := flags.Parse(args); err != nil {
		return cfg, err
	}

	if intervalMs < 100 {
		intervalMs = 100
	}
	cfg.interval = time.Duration(intervalMs) * time.Millisecond
	if openDelayMs < 0 {
		openDelayMs = 0
	}
	cfg.openDelay = time.Duration(openDelayMs) * time.Millisecond
	if writeTimeoutMs < 500 {
		writeTimeoutMs = 500
	}
	cfg.writeTimeout = time.Duration(writeTimeoutMs) * time.Millisecond
	return cfg, nil
}

func printPorts() error {
	ports, err := serial.GetPortsList()
	if err != nil {
		return fmt.Errorf("list serial ports failed: %w", err)
	}

	if len(ports) == 0 {
		fmt.Println("No serial ports found.")
		return nil
	}

	for _, port := range ports {
		fmt.Println(port)
	}
	return nil
}

func choosePort() (string, error) {
	ports, err := serial.GetPortsList()
	if err != nil {
		return "", fmt.Errorf("list serial ports failed: %w", err)
	}

	userPorts := make([]string, 0, len(ports))
	for _, port := range ports {
		if !strings.EqualFold(port, "COM1") {
			userPorts = append(userPorts, port)
		}
	}

	if len(userPorts) == 1 {
		return userPorts[0], nil
	}

	if len(userPorts) == 0 {
		return "", fmt.Errorf("no usable serial port found; available ports: %s", strings.Join(ports, ", "))
	}

	return "", fmt.Errorf("multiple serial ports found: %s; pass -port COMx", strings.Join(userPorts, ", "))
}

func openSerialWithRetry(portName string, baudRate int) (serial.Port, error) {
	mode := &serial.Mode{
		BaudRate: baudRate,
	}

	var lastErr error
	for attempt := 1; attempt <= 5; attempt++ {
		logf("opening serial port %s, attempt %d/5", portName, attempt)

		port, err := serial.Open(portName, mode)
		if err == nil {
			return port, nil
		}

		lastErr = err
		time.Sleep(700 * time.Millisecond)
	}

	return nil, lastErr
}

func readStateIfChanged(path string, lastMod time.Time) (string, time.Time, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", lastMod, err
	}

	modTime := info.ModTime()
	if !lastMod.IsZero() && !modTime.After(lastMod) {
		return "", lastMod, nil
	}

	content, err := os.ReadFile(path)
	if err != nil {
		return "", lastMod, err
	}

	var status statusFile
	if err := json.Unmarshal(content, &status); err != nil {
		return "", lastMod, err
	}

	state := normalizeState(status.State)
	if state == "" {
		state = "unknown"
	}

	return state, modTime, nil
}

func normalizeState(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "idle", "working", "attention", "unknown":
		return strings.ToLower(strings.TrimSpace(value))
	default:
		return "unknown"
	}
}

func sendState(port serial.Port, cfg bridgeConfig, state string) error {
	line := state + "\n"

	if cfg.dryRun {
		logf("send %s -> %s", strings.TrimSpace(line), cfg.portName)
		return nil
	}

	logf("writing %s -> %s", state, cfg.portName)
	if err := writeWithTimeout(port, []byte(line), cfg.writeTimeout); err != nil {
		return fmt.Errorf("write serial state %q failed: %w", state, err)
	}

	logf("sent %s -> %s", state, cfg.portName)
	return nil
}

func sendStateWithRecovery(port *serial.Port, cfg bridgeConfig, state string) error {
	if err := sendState(*port, cfg, state); err != nil {
		if cfg.dryRun {
			return err
		}
		openSerial := cfg.openSerial
		if openSerial == nil {
			openSerial = openSerialWithRetry
		}

		logf("serial write failed on %s: %v", cfg.portName, err)
		logf("serial connection may be lost; reconnecting %s...", cfg.portName)
		if *port != nil {
			_ = (*port).Close()
		}

		reopened, openErr := openSerial(cfg.portName, cfg.baudRate)
		if openErr != nil {
			return fmt.Errorf("serial connection was lost on %s while sending %q, and reconnect failed: %w. Unplug/replug the ESP32, close other serial tools, then run start.cmd again to choose the correct COM port", cfg.portName, state, openErr)
		}

		*port = reopened
		logf("serial reconnected: %s @ %d", cfg.portName, cfg.baudRate)
		waitForDeviceSerialStartup(cfg)

		if retryErr := sendState(*port, cfg, state); retryErr != nil {
			_ = (*port).Close()
			return fmt.Errorf("serial connection was lost on %s while sending %q; reconnected but retry failed: %w. Unplug/replug the ESP32, close other serial tools, then run start.cmd again to choose the correct COM port", cfg.portName, state, retryErr)
		}
	}

	return nil
}

func waitForDeviceSerialStartup(cfg bridgeConfig) {
	if cfg.openDelay <= 0 {
		return
	}

	logf("waiting %s for device serial startup", cfg.openDelay)
	time.Sleep(cfg.openDelay)
}

func writeWithTimeout(port serial.Port, data []byte, timeout time.Duration) error {
	done := make(chan error, 1)

	go func() {
		_, err := port.Write(data)
		done <- err
	}()

	select {
	case err := <-done:
		return err
	case <-time.After(timeout):
		_ = port.ResetOutputBuffer()
		_ = port.Close()
		select {
		case <-done:
		case <-time.After(serialWriteReleaseWait):
			return fmt.Errorf("serial write timed out after %s; previous write is still releasing after %s", timeout, serialWriteReleaseWait)
		}
		return fmt.Errorf("serial write timed out after %s", timeout)
	}
}

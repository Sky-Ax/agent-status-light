package main

import (
	"errors"
	"strings"
	"testing"
	"time"

	"go.bug.st/serial"
)

func TestSendStateWithRecoveryReopensPortAndRetriesFailedWrite(t *testing.T) {
	oldPort := &scriptedSerialPort{writeErrs: []error{errors.New("device disappeared")}}
	newPort := &scriptedSerialPort{}
	openCalls := 0
	cfg := bridgeConfig{
		portName:     "COM5",
		baudRate:     115200,
		writeTimeout: time.Second,
		openDelay:    0,
		openSerial: func(name string, baudRate int) (serial.Port, error) {
			openCalls++
			if name != "COM5" {
				t.Fatalf("reopen port name = %q, want COM5", name)
			}
			if baudRate != 115200 {
				t.Fatalf("reopen baud = %d, want 115200", baudRate)
			}
			return newPort, nil
		},
	}
	port := serial.Port(oldPort)

	if err := sendStateWithRecovery(&port, cfg, "idle"); err != nil {
		t.Fatalf("sendStateWithRecovery returned error: %v", err)
	}

	if openCalls != 1 {
		t.Fatalf("open calls = %d, want 1", openCalls)
	}
	if !oldPort.closed {
		t.Fatal("old port should be closed before reconnecting")
	}
	if got, ok := port.(*scriptedSerialPort); !ok || got != newPort {
		t.Fatalf("active port was not replaced after reconnect")
	}
	if string(oldPort.writes[0]) != "idle\n" {
		t.Fatalf("old port write = %q, want idle newline", oldPort.writes[0])
	}
	if string(newPort.writes[0]) != "idle\n" {
		t.Fatalf("new port write = %q, want idle newline", newPort.writes[0])
	}
}

func TestSendStateWithRecoveryReturnsActionableReconnectFailure(t *testing.T) {
	oldPort := &scriptedSerialPort{writeErrs: []error{errors.New("device disappeared")}}
	cfg := bridgeConfig{
		portName:     "COM5",
		baudRate:     115200,
		writeTimeout: time.Second,
		openSerial: func(name string, baudRate int) (serial.Port, error) {
			return nil, errors.New("access denied")
		},
	}
	port := serial.Port(oldPort)

	err := sendStateWithRecovery(&port, cfg, "idle")
	if err == nil {
		t.Fatal("sendStateWithRecovery returned nil, want reconnect failure")
	}

	message := err.Error()
	for _, want := range []string{"serial connection was lost", "COM5", "start.cmd"} {
		if !strings.Contains(message, want) {
			t.Fatalf("error %q should contain %q", message, want)
		}
	}
}

func TestWriteWithTimeoutPurgesAndClosesPortBeforeReturning(t *testing.T) {
	port := newBlockingSerialPort()

	err := writeWithTimeout(port, []byte("working\n"), 10*time.Millisecond)
	if err == nil {
		t.Fatal("writeWithTimeout returned nil, want timeout error")
	}
	if !strings.Contains(err.Error(), "serial write timed out") {
		t.Fatalf("error = %q, want serial write timeout", err)
	}
	if !port.resetOutputCalled {
		t.Fatal("ResetOutputBuffer should be called to abort a pending serial write")
	}
	if !port.closed {
		t.Fatal("Close should be called after aborting a timed-out serial write")
	}
	if !port.writeReleased {
		t.Fatal("writeWithTimeout should wait briefly for the pending Write to release")
	}
}

type scriptedSerialPort struct {
	writeErrs []error
	writes    [][]byte
	closed    bool
}

func (p *scriptedSerialPort) SetMode(mode *serial.Mode) error { return nil }

func (p *scriptedSerialPort) Read(data []byte) (int, error) { return 0, errors.New("not implemented") }

func (p *scriptedSerialPort) Write(data []byte) (int, error) {
	p.writes = append(p.writes, append([]byte(nil), data...))
	if len(p.writeErrs) > 0 {
		err := p.writeErrs[0]
		p.writeErrs = p.writeErrs[1:]
		return 0, err
	}
	return len(data), nil
}

func (p *scriptedSerialPort) Drain() error { return nil }

func (p *scriptedSerialPort) ResetInputBuffer() error { return nil }

func (p *scriptedSerialPort) ResetOutputBuffer() error { return nil }

func (p *scriptedSerialPort) SetDTR(dtr bool) error { return nil }

func (p *scriptedSerialPort) SetRTS(rts bool) error { return nil }

func (p *scriptedSerialPort) GetModemStatusBits() (*serial.ModemStatusBits, error) {
	return &serial.ModemStatusBits{}, nil
}

func (p *scriptedSerialPort) SetReadTimeout(timeout time.Duration) error { return nil }

func (p *scriptedSerialPort) Close() error {
	p.closed = true
	return nil
}

func (p *scriptedSerialPort) Break(duration time.Duration) error { return nil }

type blockingSerialPort struct {
	release           chan struct{}
	resetOutputCalled bool
	closed            bool
	writeReleased     bool
}

func newBlockingSerialPort() *blockingSerialPort {
	return &blockingSerialPort{release: make(chan struct{})}
}

func (p *blockingSerialPort) SetMode(mode *serial.Mode) error { return nil }

func (p *blockingSerialPort) Read(data []byte) (int, error) { return 0, errors.New("not implemented") }

func (p *blockingSerialPort) Write(data []byte) (int, error) {
	<-p.release
	p.writeReleased = true
	return 0, errors.New("write aborted")
}

func (p *blockingSerialPort) Drain() error { return nil }

func (p *blockingSerialPort) ResetInputBuffer() error { return nil }

func (p *blockingSerialPort) ResetOutputBuffer() error {
	p.resetOutputCalled = true
	return nil
}

func (p *blockingSerialPort) SetDTR(dtr bool) error { return nil }

func (p *blockingSerialPort) SetRTS(rts bool) error { return nil }

func (p *blockingSerialPort) GetModemStatusBits() (*serial.ModemStatusBits, error) {
	return &serial.ModemStatusBits{}, nil
}

func (p *blockingSerialPort) SetReadTimeout(timeout time.Duration) error { return nil }

func (p *blockingSerialPort) Close() error {
	if !p.closed {
		p.closed = true
		close(p.release)
	}
	return nil
}

func (p *blockingSerialPort) Break(duration time.Duration) error { return nil }

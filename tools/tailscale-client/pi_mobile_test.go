package main

import (
	"io"
	"net"
	"os"
	"testing"
	"time"
)

func TestPiTailscaleMissingNodeFailsClosed(t *testing.T) {
	if PiTailscaleStatus(-1) != nil || PiTailscaleLogin(-1) != -1 || PiTailscaleDial(-1, nil) != -1 {
		t.Fatal("missing nodes must not return status, start a login, or dial through another identity")
	}
	PiTailscaleClose(-1) // Idempotent teardown of an already closed node.
}

func TestPiTailscaleSocketRelayAndClose(t *testing.T) {
	remote, relay := net.Pipe()
	t.Cleanup(func() { remote.Close() })
	remote.SetDeadline(time.Now().Add(3 * time.Second))
	fd := mobileTailscaleSocket(&server{}, relay)
	if fd < 0 {
		t.Fatal("creating the native socket relay")
	}
	native := os.NewFile(uintptr(fd), "test-tailscale-socket")
	t.Cleanup(func() { native.Close() })
	sent := make(chan error, 1)
	go func() { _, err := native.Write([]byte("native SSH bytes")); sent <- err }()
	got := make([]byte, len("native SSH bytes"))
	if _, err := io.ReadFull(remote, got); err != nil || string(got) != "native SSH bytes" {
		t.Fatalf("native-to-tailnet relay: %q, %v", got, err)
	}
	if err := <-sent; err != nil {
		t.Fatal(err)
	}
	go func() { _, err := remote.Write([]byte("tailnet SSH bytes")); sent <- err }()
	got = make([]byte, len("tailnet SSH bytes"))
	if _, err := io.ReadFull(native, got); err != nil || string(got) != "tailnet SSH bytes" {
		t.Fatalf("tailnet-to-native relay: %q, %v", got, err)
	}
	if err := <-sent; err != nil {
		t.Fatal(err)
	}
	if err := native.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := remote.Read(make([]byte, 1)); err == nil {
		t.Fatal("closing the owned native socket must close the tailnet relay")
	}
}

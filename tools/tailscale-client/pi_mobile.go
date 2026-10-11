// Pi Mobile's bounded C entry points extend the pinned official libtailscale archive.
package main

// #include <stdlib.h>
import "C"

import (
	"context"
	"encoding/json"
	"net"
	"time"

	"tailscale.com/envknob"
	"tailscale.com/types/logger"
)

func init() {
	// Do not upload Tailscale diagnostics, login URLs, or other node state.
	envknob.SetNoLogsNoSupport()
}

// PiTailscaleStart starts a persistent userspace node without waiting for login.
// A positive handle is owned by the caller; failure returns -1 without diagnostics.
//
//export PiTailscaleStart
func PiTailscaleStart(directory *C.char) C.int {
	sd := TsnetNewServer()
	s := getServer(sd)
	s.s.Dir = C.GoString(directory)
	s.s.Hostname = "pi-mobile"
	s.s.Logf = logger.Discard
	s.s.UserLogf = logger.Discard
	if TsnetStart(sd) != 0 {
		s.s.Close()
		TsnetClose(sd)
		return -1
	}
	return sd
}

// PiTailscaleStatus reads the authenticated local node's status, never a remote HTTP service.
// The caller frees the returned JSON string; failures return NULL and expose no secrets.
//
//export PiTailscaleStatus
func PiTailscaleStatus(sd C.int) *C.char {
	s := getServer(sd)
	if s == nil {
		return nil
	}
	lc, err := s.s.LocalClient()
	if err != nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	status, err := lc.Status(ctx)
	if err != nil {
		return nil
	}
	data, err := json.Marshal(status)
	if err != nil {
		return nil
	}
	return C.CString(string(data))
}

// PiTailscaleLogin explicitly requests browser login with a ten-second LocalAPI deadline.
//
//export PiTailscaleLogin
func PiTailscaleLogin(sd C.int) C.int {
	s := getServer(sd)
	if s == nil {
		return -1
	}
	lc, err := s.s.LocalClient()
	if err != nil {
		return -1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if lc.StartLoginInteractive(ctx) != nil {
		return -1
	}
	return 0
}

// PiTailscaleDial returns a connected socketpair descriptor owned by the caller, or -1.
// Only the verified numeric peer address is supplied by Swift. No OS-network fallback.
//
//export PiTailscaleDial
func PiTailscaleDial(sd C.int, address *C.char) C.int {
	s := getServer(sd)
	if s == nil {
		return -1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	connection, err := s.s.Dial(ctx, "tcp", C.GoString(address))
	if err != nil {
		return -1
	}
	return mobileTailscaleSocket(s, connection)
}

// mobileTailscaleSocket hands libtailscale's full-duplex relay to the native SSH owner.
func mobileTailscaleSocket(s *server, connection net.Conn) C.int {
	var descriptor C.int
	if err := newConn(s, connection, &descriptor); err != nil {
		connection.Close()
		return -1
	}
	return descriptor
}

// PiTailscaleClose stops the local node without logging out or deleting its stored identity.
//
//export PiTailscaleClose
func PiTailscaleClose(sd C.int) {
	TsnetClose(sd)
}

package server

import (
	"bytes"
	"net"
	"strings"
	"testing"
	"time"
)

func TestSSDPAliveMessage_RootDevice(t *testing.T) {
	location := "http://192.168.1.100:8200/description.xml"
	udn := "uuid:12345678-1234-5050-8080-123456789abc"
	nt := "upnp:rootdevice"

	msg := ssdpAliveMessage(location, udn, nt, 42, 1)

	s := string(msg)
	if !strings.Contains(s, "NOTIFY") {
		t.Error("alive message missing NOTIFY")
	}
	if !strings.Contains(s, "NTS: ssdp:alive") {
		t.Errorf("alive message missing 'NTS: ssdp:alive', got:\n%s", s)
	}
	if !strings.Contains(s, "LOCATION: "+location) {
		t.Errorf("alive message missing LOCATION header, got:\n%s", s)
	}
	if !strings.Contains(s, "NT: "+nt) {
		t.Errorf("alive message missing NT header, got:\n%s", s)
	}
	if !strings.Contains(s, udn) {
		t.Errorf("alive message missing UDN in USN, got:\n%s", s)
	}
	if !strings.Contains(s, "HOST: 239.255.255.250:1900") {
		t.Errorf("alive message missing HOST header, got:\n%s", s)
	}
	if !strings.Contains(s, "CACHE-CONTROL: max-age=1800") {
		t.Errorf("alive message missing CACHE-CONTROL header, got:\n%s", s)
	}
	// Verify CRLF line endings
	if !bytes.Contains(msg, []byte("\r\n")) {
		t.Error("alive message must use CRLF line endings")
	}
	// Verify trailing blank line (double CRLF at end)
	if !bytes.HasSuffix(msg, []byte("\r\n\r\n")) {
		end := len(msg) - 8
		if end < 0 {
			end = 0
		}
		t.Errorf("alive message must end with blank CRLF line, got suffix: %q", msg[end:])
	}
}

func TestSSDPAliveMessage_DeviceUDN(t *testing.T) {
	location := "http://192.168.1.100:8200/description.xml"
	udn := "uuid:12345678-1234-5050-8080-123456789abc"
	nt := udn // device UDN as NT → USN is just the UDN

	msg := ssdpAliveMessage(location, udn, nt, 42, 1)
	s := string(msg)

	// When NT == UDN, USN should be just the UDN (no "::" suffix)
	if !strings.Contains(s, "USN: "+udn) {
		t.Errorf("alive message USN should be just UDN when NT==UDN, got:\n%s", s)
	}
}

func TestSSDPAliveMessage_ServiceNT(t *testing.T) {
	location := "http://192.168.1.100:8200/description.xml"
	udn := "uuid:12345678-1234-5050-8080-123456789abc"
	nt := "urn:schemas-upnp-org:service:ContentDirectory:1"

	msg := ssdpAliveMessage(location, udn, nt, 42, 1)
	s := string(msg)

	// USN should be udn::nt
	want := "USN: " + udn + "::" + nt
	if !strings.Contains(s, want) {
		t.Errorf("alive message USN = %q not found, got:\n%s", want, s)
	}
}

func TestSSDPSearchResponse(t *testing.T) {
	location := "http://192.168.1.100:8200/description.xml"
	udn := "uuid:12345678-1234-5050-8080-123456789abc"
	st := "urn:schemas-upnp-org:device:MediaServer:1"

	msg := ssdpSearchResponse(location, udn, st, 42, 1, "Mon, 02 Jan 2006 15:04:05 GMT")
	s := string(msg)

	if !strings.Contains(s, "HTTP/1.1 200 OK") {
		t.Errorf("search response missing status line, got:\n%s", s)
	}
	if !strings.Contains(s, "ST: "+st) {
		t.Errorf("search response missing ST header, got:\n%s", s)
	}
	if !strings.Contains(s, "LOCATION: "+location) {
		t.Errorf("search response missing LOCATION header, got:\n%s", s)
	}
	if !strings.Contains(s, "CACHE-CONTROL: max-age=1800") {
		t.Errorf("search response missing CACHE-CONTROL header, got:\n%s", s)
	}
	if !strings.Contains(s, "EXT:") {
		t.Errorf("search response missing EXT header, got:\n%s", s)
	}
	if !strings.Contains(s, udn) {
		t.Errorf("search response missing UDN in USN, got:\n%s", s)
	}
	// Verify CRLF line endings
	if !bytes.Contains(msg, []byte("\r\n")) {
		t.Error("search response must use CRLF line endings")
	}
	// Verify trailing blank line
	if !bytes.HasSuffix(msg, []byte("\r\n\r\n")) {
		t.Errorf("search response must end with blank CRLF line")
	}
}

func TestSSDPByebyeMessage(t *testing.T) {
	udn := "uuid:12345678-1234-5050-8080-123456789abc"
	nt := "upnp:rootdevice"

	msg := ssdpByebyeMessage(udn, nt, 42, 1)
	s := string(msg)

	if !strings.Contains(s, "NOTIFY") {
		t.Error("byebye message missing NOTIFY")
	}
	if !strings.Contains(s, "NTS: ssdp:byebye") {
		t.Errorf("byebye message missing 'NTS: ssdp:byebye', got:\n%s", s)
	}
	if !strings.Contains(s, "NT: "+nt) {
		t.Errorf("byebye message missing NT header, got:\n%s", s)
	}
	if !strings.Contains(s, udn) {
		t.Errorf("byebye message missing UDN, got:\n%s", s)
	}
	// Verify CRLF line endings
	if !bytes.Contains(msg, []byte("\r\n")) {
		t.Error("byebye message must use CRLF line endings")
	}
}

// TestSSDPMessages_UPnP11Headers verifies the UDA 1.1 headers control points
// may require (BOOTID/CONFIGID on every advertisement, DATE on responses).
func TestSSDPMessages_UPnP11Headers(t *testing.T) {
	loc := "http://192.168.1.100:8200/description.xml"
	udn := "uuid:12345678-1234-5050-8080-123456789abc"

	alive := string(ssdpAliveMessage(loc, udn, ntRootDevice, 7, 3))
	for _, h := range []string{"BOOTID.UPNP.ORG: 7", "CONFIGID.UPNP.ORG: 3"} {
		if !strings.Contains(alive, h) {
			t.Errorf("alive missing %q, got:\n%s", h, alive)
		}
	}

	resp := string(ssdpSearchResponse(loc, udn, ntMediaServer, 7, 3, "Tue, 05 Aug 2026 01:02:03 GMT"))
	for _, h := range []string{
		"BOOTID.UPNP.ORG: 7",
		"CONFIGID.UPNP.ORG: 3",
		"DATE: Tue, 05 Aug 2026 01:02:03 GMT",
	} {
		if !strings.Contains(resp, h) {
			t.Errorf("search response missing %q, got:\n%s", h, resp)
		}
	}

	bye := string(ssdpByebyeMessage(udn, ntRootDevice, 7, 3))
	for _, h := range []string{"BOOTID.UPNP.ORG: 7", "CONFIGID.UPNP.ORG: 3"} {
		if !strings.Contains(bye, h) {
			t.Errorf("byebye missing %q, got:\n%s", h, bye)
		}
	}
}

// TestSearchResponseDelay verifies the M-SEARCH response delay honours MX and
// the hard cap, and never blocks (0) for MX<=0.
func TestSearchResponseDelay(t *testing.T) {
	if d := searchResponseDelay(0); d != 0 {
		t.Errorf("MX=0 must yield zero delay, got %v", d)
	}
	if d := searchResponseDelay(-5); d != 0 {
		t.Errorf("negative MX must yield zero delay, got %v", d)
	}
	for i := 0; i < 200; i++ {
		if d := searchResponseDelay(1); d < 0 || d > time.Second {
			t.Fatalf("MX=1 delay out of [0,1s]: %v", d)
		}
	}
	for i := 0; i < 200; i++ {
		// Large MX must still be capped at maxSearchResponseDelay.
		if d := searchResponseDelay(30); d < 0 || d > maxSearchResponseDelay {
			t.Fatalf("MX=30 delay must be capped at %v, got %v", maxSearchResponseDelay, d)
		}
	}
}

// TestScoreInterface verifies Wi-Fi/Ethernet outrank cellular/VPN so SSDP binds
// to the LAN — the root-cause fix for control points not discovering the server.
func TestScoreInterface(t *testing.T) {
	const mc = net.FlagUp | net.FlagMulticast
	wlan := scoreInterface("wlan0", mc)
	eth := scoreInterface("eth0", mc)
	rmnet := scoreInterface("rmnet_data0", net.FlagUp|net.FlagMulticast|net.FlagPointToPoint)
	tun := scoreInterface("tun0", net.FlagUp|net.FlagPointToPoint)

	if wlan <= rmnet {
		t.Errorf("wlan0 (%d) must outrank rmnet_data0 (%d)", wlan, rmnet)
	}
	if wlan <= tun {
		t.Errorf("wlan0 (%d) must outrank tun0 (%d)", wlan, tun)
	}
	if eth <= rmnet {
		t.Errorf("eth0 (%d) must outrank rmnet_data0 (%d)", eth, rmnet)
	}
}


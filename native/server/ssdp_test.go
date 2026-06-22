package server

import (
	"bytes"
	"strings"
	"testing"
)

func TestSSDPAliveMessage_RootDevice(t *testing.T) {
	location := "http://192.168.1.100:8200/description.xml"
	udn := "uuid:12345678-1234-5050-8080-123456789abc"
	nt := "upnp:rootdevice"

	msg := ssdpAliveMessage(location, udn, nt)

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

	msg := ssdpAliveMessage(location, udn, nt)
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

	msg := ssdpAliveMessage(location, udn, nt)
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

	msg := ssdpSearchResponse(location, udn, st)
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

	msg := ssdpByebyeMessage(udn, nt)
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


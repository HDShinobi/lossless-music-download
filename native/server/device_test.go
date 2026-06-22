package server

import (
	"encoding/xml"
	"strings"
	"testing"
)

func TestDeviceDescriptionXML(t *testing.T) {
	data := deviceDescriptionXML("My Music", "uuid:test-udn-1234", "http://192.168.1.10:8200")
	if len(data) == 0 {
		t.Fatal("deviceDescriptionXML returned empty bytes")
	}
	// Must be well-formed XML.
	if err := xml.Unmarshal(data, new(interface{})); err != nil {
		// xml.Unmarshal into interface{} won't work directly; check via decoder.
		dec := xml.NewDecoder(strings.NewReader(string(data)))
		for {
			_, err := dec.Token()
			if err != nil {
				if err.Error() == "EOF" {
					break
				}
				t.Fatalf("deviceDescriptionXML is not well-formed XML: %v", err)
			}
		}
	}
	s := string(data)
	if !strings.Contains(s, "urn:schemas-upnp-org:device:MediaServer:1") {
		t.Error("missing deviceType urn:schemas-upnp-org:device:MediaServer:1")
	}
	if !strings.Contains(s, "urn:schemas-upnp-org:service:ContentDirectory:1") {
		t.Error("missing serviceType ContentDirectory:1")
	}
	if !strings.Contains(s, "My Music") {
		t.Error("missing friendlyName")
	}
	if !strings.Contains(s, "uuid:test-udn-1234") {
		t.Error("missing UDN")
	}
	if !strings.Contains(s, "/cd/control") {
		t.Error("missing controlURL /cd/control")
	}
}

func TestContentDirectorySCPD(t *testing.T) {
	data := contentDirectorySCPD()
	s := string(data)
	if !strings.Contains(s, "Browse") {
		t.Error("SCPD missing Browse action")
	}
	if !strings.Contains(s, "BrowseDirectChildren") {
		t.Error("SCPD missing BrowseDirectChildren")
	}
	// Must be well-formed XML.
	dec := xml.NewDecoder(strings.NewReader(s))
	for {
		_, err := dec.Token()
		if err != nil {
			if err.Error() == "EOF" {
				break
			}
			t.Fatalf("contentDirectorySCPD is not well-formed XML: %v", err)
		}
	}
}

package server

import (
	"encoding/xml"
	"strings"
	"testing"
)

func TestDidlLite(t *testing.T) {
	containers := []cdObject{
		{id: "abc123", parentID: "0", title: "My Album", childCount: 3},
	}
	items := []cdItem{
		{
			id:       "def456",
			parentID: "abc123",
			title:    "01 Song Title",
			artist:   "The Artist",
			album:    "My Album",
			size:     123456,
			mime:     "audio/flac",
			url:      "http://192.168.1.10:8200/media/def456",
		},
	}

	out := didlLite(containers, items)
	if len(out) == 0 {
		t.Fatal("didlLite returned empty bytes")
	}

	s := string(out)

	// Must be well-formed XML.
	dec := xml.NewDecoder(strings.NewReader(s))
	for {
		_, err := dec.Token()
		if err != nil {
			if err.Error() == "EOF" {
				break
			}
			t.Fatalf("didlLite output is not well-formed XML: %v\n%s", err, s)
		}
	}

	if !strings.Contains(s, "DIDL-Lite") {
		t.Error("missing DIDL-Lite root element")
	}
	if !strings.Contains(s, "object.container.storageFolder") {
		t.Error("container missing object.container.storageFolder class")
	}
	if !strings.Contains(s, "object.item.audioItem.musicTrack") {
		t.Error("item missing object.item.audioItem.musicTrack class")
	}
	if !strings.Contains(s, "My Album") {
		t.Error("missing container title")
	}
	if !strings.Contains(s, "01 Song Title") {
		t.Error("missing item title")
	}
	if !strings.Contains(s, "The Artist") {
		t.Error("missing upnp:artist")
	}
	if !strings.Contains(s, "http-get:*:audio/flac:*") {
		t.Error("missing protocolInfo in res element")
	}
	if !strings.Contains(s, "http://192.168.1.10:8200/media/def456") {
		t.Error("missing res URL")
	}
	if !strings.Contains(s, `size="123456"`) {
		t.Error("missing size attribute")
	}
}

func TestDidlLiteXMLEscaping(t *testing.T) {
	items := []cdItem{
		{
			id:       "x",
			parentID: "0",
			title:    `Track with <special> & "chars"`,
			artist:   "",
			album:    "",
			size:     100,
			mime:     "audio/mpeg",
			url:      "http://host/media/x",
		},
	}
	out := didlLite(nil, items)
	s := string(out)

	dec := xml.NewDecoder(strings.NewReader(s))
	for {
		_, err := dec.Token()
		if err != nil {
			if err.Error() == "EOF" {
				break
			}
			t.Fatalf("XML with special chars not well-formed: %v", err)
		}
	}
}

func TestDidlLiteEmpty(t *testing.T) {
	out := didlLite(nil, nil)
	s := string(out)
	if !strings.Contains(s, "DIDL-Lite") {
		t.Error("empty DIDL-Lite missing root element")
	}
	dec := xml.NewDecoder(strings.NewReader(s))
	for {
		_, err := dec.Token()
		if err != nil {
			if err.Error() == "EOF" {
				break
			}
			t.Fatalf("empty didlLite not well-formed XML: %v", err)
		}
	}
}

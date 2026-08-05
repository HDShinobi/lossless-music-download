package server

import (
	"strings"
	"testing"
)

func TestFormatDuration(t *testing.T) {
	cases := map[int]string{
		0:    "",
		-1:   "",
		45:   "0:00:45",
		225:  "0:03:45",
		3661: "1:01:01",
	}
	for sec, want := range cases {
		if got := formatDuration(sec); got != want {
			t.Errorf("formatDuration(%d) = %q, want %q", sec, got, want)
		}
	}
}

func TestBitrateBytesPerSec(t *testing.T) {
	// UPnP res@bitrate is bytes/sec: 1411 kbps (CD) -> ~176375 bytes/sec.
	if got := bitrateBytesPerSec(1411); got != 176375 {
		t.Errorf("bitrateBytesPerSec(1411) = %d, want 176375", got)
	}
	if got := bitrateBytesPerSec(320); got != 40000 {
		t.Errorf("bitrateBytesPerSec(320) = %d, want 40000", got)
	}
	if got := bitrateBytesPerSec(0); got != 0 {
		t.Errorf("bitrateBytesPerSec(0) = %d, want 0", got)
	}
}

func TestProtocolInfoFor(t *testing.T) {
	mp3 := protocolInfoFor("audio/mpeg")
	if !strings.Contains(mp3, "DLNA.ORG_PN=MP3") {
		t.Errorf("mp3 protocolInfo missing PN=MP3: %s", mp3)
	}
	for _, mime := range []string{"audio/mpeg", "audio/flac", "audio/mp4"} {
		pi := protocolInfoFor(mime)
		if !strings.HasPrefix(pi, "http-get:*:"+mime+":") {
			t.Errorf("protocolInfo for %s wrong prefix: %s", mime, pi)
		}
		if !strings.Contains(pi, "DLNA.ORG_OP=01") || !strings.Contains(pi, "DLNA.ORG_FLAGS=") {
			t.Errorf("protocolInfo for %s missing OP/FLAGS: %s", mime, pi)
		}
	}
	// FLAC must NOT claim a DLNA.ORG_PN (none is universally honoured).
	if strings.Contains(protocolInfoFor("audio/flac"), "DLNA.ORG_PN") {
		t.Errorf("flac protocolInfo should not carry a PN")
	}
}

func TestDIDLItemFullMetadata(t *testing.T) {
	items := []cdItem{{
		id:          "aWQ",
		parentID:    "0",
		title:       "Easy On Me",
		artist:      "Adele",
		album:       "30",
		genre:       "Pop",
		trackNumber: 1,
		albumArtURI: "http://192.168.1.9:8200/art/aWQ",
		durationSec: 225,
		sampleRate:  44100,
		bitDepth:    16,
		bitrateKbps: 900,
		size:        1234,
		mime:        "audio/flac",
		url:         "http://192.168.1.9:8200/media/aWQ",
	}}
	out := string(didlLite(nil, items))

	for _, want := range []string{
		`xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"`,
		"<dc:title>Easy On Me</dc:title>",
		"<dc:creator>Adele</dc:creator>",
		"<upnp:artist>Adele</upnp:artist>",
		"<upnp:album>30</upnp:album>",
		"<upnp:genre>Pop</upnp:genre>",
		"<upnp:originalTrackNumber>1</upnp:originalTrackNumber>",
		`<upnp:albumArtURI dlna:profileID="JPEG_TN">http://192.168.1.9:8200/art/aWQ</upnp:albumArtURI>`,
		`duration="0:03:45"`,
		`sampleFrequency="44100"`,
		`bitsPerSample="16"`,
		`bitrate="112500"`, // 900 kbps -> 112500 bytes/sec
		"http-get:*:audio/flac:",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("DIDL missing %q\n---\n%s", want, out)
		}
	}
}

func TestDIDLItemOmitsUnknownFields(t *testing.T) {
	// A filename-only item (no provider) must not emit empty metadata elements.
	items := []cdItem{{
		id: "x", parentID: "0", title: "track01", mime: "audio/flac",
		url: "http://h/media/x", size: 10,
	}}
	out := string(didlLite(nil, items))
	for _, unwanted := range []string{
		"<dc:creator>", "<upnp:artist>", "<upnp:album>", "<upnp:genre>",
		"<upnp:originalTrackNumber>", "<upnp:albumArtURI", "duration=", "bitrate=",
	} {
		if strings.Contains(out, unwanted) {
			t.Errorf("DIDL should omit %q for a bare item\n---\n%s", unwanted, out)
		}
	}
}

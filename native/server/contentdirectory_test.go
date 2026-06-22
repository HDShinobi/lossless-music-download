package server

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sampleBrowseEnvelope = `<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <ObjectID>0</ObjectID>
      <BrowseFlag>BrowseDirectChildren</BrowseFlag>
      <Filter>*</Filter>
      <StartingIndex>0</StartingIndex>
      <RequestedCount>0</RequestedCount>
      <SortCriteria></SortCriteria>
    </u:Browse>
  </s:Body>
</s:Envelope>`

func TestParseBrowse(t *testing.T) {
	id, flag, err := parseBrowse([]byte(sampleBrowseEnvelope))
	if err != nil {
		t.Fatalf("parseBrowse error: %v", err)
	}
	if id != "0" {
		t.Errorf("objectID = %q, want %q", id, "0")
	}
	if flag != "BrowseDirectChildren" {
		t.Errorf("browseFlag = %q, want %q", flag, "BrowseDirectChildren")
	}
}

func TestParseBrowseEncoded(t *testing.T) {
	encoded := encodeObjectID("Artist/Album")
	body := `<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <ObjectID>` + encoded + `</ObjectID>
      <BrowseFlag>BrowseDirectChildren</BrowseFlag>
    </u:Browse>
  </s:Body>
</s:Envelope>`
	id, _, err := parseBrowse([]byte(body))
	if err != nil {
		t.Fatalf("parseBrowse error: %v", err)
	}
	if id != encoded {
		t.Errorf("objectID = %q, want %q", id, encoded)
	}
}

func TestBrowseRoot(t *testing.T) {
	// Set up a temp dir: Artist/Album/01 Song.flac + a top-level file.
	dir := t.TempDir()
	albumDir := filepath.Join(dir, "Artist", "Album")
	if err := os.MkdirAll(albumDir, 0755); err != nil {
		t.Fatal(err)
	}
	flacPath := filepath.Join(albumDir, "01 Song.flac")
	if err := os.WriteFile(flacPath, []byte("FAKEFLAC"), 0644); err != nil {
		t.Fatal(err)
	}

	srv := NewMediaServer(dir, "Test Server")
	srv.baseURL = "http://127.0.0.1:8200"

	didl, num, total, err := srv.browse("0")
	if err != nil {
		t.Fatalf("browse(0) error: %v", err)
	}
	if num != total {
		t.Errorf("numReturned %d != totalMatches %d", num, total)
	}
	// Root has one dir: "Artist"
	if num != 1 {
		t.Errorf("expected 1 child (Artist dir), got %d", num)
	}
	s := string(didl)
	if !strings.Contains(s, "Artist") {
		t.Error("DIDL missing Artist container")
	}
	if !strings.Contains(s, "storageFolder") {
		t.Error("DIDL container missing storageFolder class")
	}
}

func TestBrowseSubDir(t *testing.T) {
	dir := t.TempDir()
	albumDir := filepath.Join(dir, "Artist", "Album")
	if err := os.MkdirAll(albumDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(albumDir, "01 Song.flac"), []byte("FAKEFLAC"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(albumDir, "02 Track.mp3"), []byte("FAKEMP3"), 0644); err != nil {
		t.Fatal(err)
	}

	srv := NewMediaServer(dir, "Test Server")
	srv.baseURL = "http://127.0.0.1:8200"

	// Browse into Artist/Album
	albumID := encodeObjectID("Artist/Album")
	didl, num, _, err := srv.browse(albumID)
	if err != nil {
		t.Fatalf("browse(Artist/Album) error: %v", err)
	}
	if num != 2 {
		t.Errorf("expected 2 items in Album dir, got %d", num)
	}
	s := string(didl)
	if !strings.Contains(s, "01 Song") {
		t.Error("DIDL missing track title '01 Song'")
	}
	if !strings.Contains(s, "audio/flac") {
		t.Error("DIDL missing audio/flac mime")
	}
	if !strings.Contains(s, "/media/") {
		t.Error("DIDL missing /media/ URL")
	}
}

func TestBrowseTraversalRejected(t *testing.T) {
	dir := t.TempDir()

	srv := NewMediaServer(dir, "Test Server")
	srv.baseURL = "http://127.0.0.1:8200"

	// Attempt traversal via encoded "../secret"
	badID := encodeObjectID("../secret")
	_, _, _, err := srv.browse(badID)
	if err == nil {
		t.Error("expected error for traversal objectID, got nil")
	}
}

func TestEncodeDecodeObjectID(t *testing.T) {
	paths := []string{
		"Artist/Album",
		"Artist/Album/01 Song.flac",
		"simple",
	}
	for _, p := range paths {
		encoded := encodeObjectID(p)
		decoded, err := decodeObjectID(encoded)
		if err != nil {
			t.Errorf("decodeObjectID(%q) error: %v", encoded, err)
			continue
		}
		if decoded != p {
			t.Errorf("round-trip failed: got %q, want %q", decoded, p)
		}
	}
}

func TestMimeForExt(t *testing.T) {
	cases := []struct{ ext, mime string }{
		{".flac", "audio/flac"},
		{".FLAC", "audio/flac"},
		{".mp3", "audio/mpeg"},
		{".m4a", "audio/mp4"},
		{".alac", "audio/mp4"},
		{".wav", "audio/wav"},
		{".ogg", "audio/ogg"},
		{".opus", "audio/ogg"},
		{".aiff", "audio/aiff"},
		{".aif", "audio/aiff"},
		{".txt", "application/octet-stream"},
	}
	for _, tc := range cases {
		got := mimeForExt(tc.ext)
		if got != tc.mime {
			t.Errorf("mimeForExt(%q) = %q, want %q", tc.ext, got, tc.mime)
		}
	}
}

package server

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type fakeMeta struct{}

func (fakeMeta) ReadTags(string) (TrackTags, bool) {
	return TrackTags{
		Title: "Hello", Artist: "Adele", Album: "25", Genre: "Pop",
		TrackNumber: 2, DurationSec: 295, SampleRate: 44100, BitDepth: 16, BitrateKbps: 900,
	}, true
}

func (fakeMeta) ReadCover(string) ([]byte, string, bool) {
	return []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03}, "image/jpeg", true
}

// TestBrowseWithMetadataProvider exercises the full HTTP path: a SOAP Browse
// returns DIDL enriched from the provider, and /art serves the cover.
func TestBrowseWithMetadataProvider(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "song.flac"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	srv := NewMediaServer(dir, "MetaSrv", "")
	srv.SetMetadataProvider(fakeMeta{})

	mux := http.NewServeMux()
	mux.HandleFunc("/cd/control", srv.handleControl)
	mux.HandleFunc("/art/", srv.handleArt)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	srv.mu.Lock()
	srv.baseURL = ts.URL
	srv.mu.Unlock()

	body := `<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag></u:Browse></s:Body></s:Envelope>`
	resp, err := http.Post(ts.URL+"/cd/control", "text/xml", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	out := string(b)

	// DIDL is XML-escaped inside <Result>, but text/URL substrings survive.
	// DIDL is XML-escaped inside <Result>, so element markup appears as &lt;/&gt;.
	for _, want := range []string{
		"Adele",
		"25&lt;/upnp:album&gt;",
		"Pop",
		"originalTrackNumber",
		"/art/",
		"0:04:55", // 295s duration
	} {
		if !strings.Contains(out, want) {
			t.Errorf("browse response missing %q\n---\n%s", want, out)
		}
	}

	// Fetch the advertised cover.
	encoded := encodeObjectID("song.flac")
	artResp, err := http.Get(ts.URL + "/art/" + encoded)
	if err != nil {
		t.Fatal(err)
	}
	defer artResp.Body.Close()
	if artResp.StatusCode != 200 {
		t.Fatalf("/art status = %d, want 200", artResp.StatusCode)
	}
	if ct := artResp.Header.Get("Content-Type"); ct != "image/jpeg" {
		t.Errorf("/art Content-Type = %q, want image/jpeg", ct)
	}
	art, _ := io.ReadAll(artResp.Body)
	if len(art) != 7 {
		t.Errorf("/art body len = %d, want 7", len(art))
	}
}

// TestArtWithoutProvider returns 404 when no metadata provider is set.
func TestArtWithoutProvider(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "song.flac"), []byte("x"), 0o644)
	srv := NewMediaServer(dir, "NoMeta", "")

	mux := http.NewServeMux()
	mux.HandleFunc("/art/", srv.handleArt)
	ts := httptest.NewServer(mux)
	defer ts.Close()

	resp, err := http.Get(ts.URL + "/art/" + encodeObjectID("song.flac"))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("status = %d, want 404", resp.StatusCode)
	}
}

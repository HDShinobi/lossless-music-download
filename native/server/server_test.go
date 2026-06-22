package server

import (
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// seedDir creates a temp directory with the structure:
//
//	Artist/
//	  Album/
//	    01 Song.flac  (content: "FLACDATA")
func seedDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	albumDir := filepath.Join(dir, "Artist", "Album")
	if err := os.MkdirAll(albumDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(albumDir, "01 Song.flac"), []byte("FLACDATA"), 0644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestServerDescriptionXML(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "LosslessMusic Test")

	url, err := srv.Start()
	if err != nil {
		t.Fatalf("Start() error: %v", err)
	}
	defer srv.Stop()

	resp, err := http.Get(url + "/description.xml")
	if err != nil {
		t.Fatalf("GET /description.xml: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET /description.xml status = %d, want 200", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	s := string(body)

	if !strings.Contains(s, "LosslessMusic Test") {
		t.Error("description.xml missing friendlyName")
	}
	if !strings.Contains(s, "MediaServer:1") {
		t.Error("description.xml missing MediaServer:1 deviceType")
	}
	if !strings.Contains(s, "ContentDirectory:1") {
		t.Error("description.xml missing ContentDirectory:1")
	}

	// Must be well-formed XML.
	dec := xml.NewDecoder(strings.NewReader(s))
	for {
		_, err := dec.Token()
		if err != nil {
			if err.Error() == "EOF" {
				break
			}
			t.Fatalf("description.xml not well-formed XML: %v", err)
		}
	}
}

func TestServerBrowseRoot(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "LosslessMusic Test")

	baseURL, err := srv.Start()
	if err != nil {
		t.Fatalf("Start() error: %v", err)
	}
	defer srv.Stop()

	soapBody := `<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
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

	resp, err := http.Post(baseURL+"/cd/control", "text/xml", strings.NewReader(soapBody))
	if err != nil {
		t.Fatalf("POST /cd/control: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("POST /cd/control status = %d, want 200", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	s := string(body)

	if !strings.Contains(s, "BrowseResponse") {
		t.Error("response missing BrowseResponse")
	}
	if !strings.Contains(s, "Artist") {
		t.Error("response missing Artist container")
	}
	if !strings.Contains(s, "storageFolder") {
		t.Error("response missing storageFolder class")
	}
}

func TestServerBrowseAlbum(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "LosslessMusic Test")

	baseURL, err := srv.Start()
	if err != nil {
		t.Fatalf("Start() error: %v", err)
	}
	defer srv.Stop()

	// Browse into Artist/Album
	albumID := encodeObjectID("Artist/Album")
	soapBody := fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <ObjectID>%s</ObjectID>
      <BrowseFlag>BrowseDirectChildren</BrowseFlag>
      <Filter>*</Filter>
      <StartingIndex>0</StartingIndex>
      <RequestedCount>0</RequestedCount>
      <SortCriteria></SortCriteria>
    </u:Browse>
  </s:Body>
</s:Envelope>`, albumID)

	resp, err := http.Post(baseURL+"/cd/control", "text/xml", strings.NewReader(soapBody))
	if err != nil {
		t.Fatalf("POST /cd/control: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("POST /cd/control status = %d, want 200", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	s := string(body)

	if !strings.Contains(s, "01 Song") {
		t.Error("response missing track title")
	}
	if !strings.Contains(s, "/media/") {
		t.Error("response missing /media/ URL in Result")
	}
	if !strings.Contains(s, "audioItem.musicTrack") {
		t.Error("response missing audioItem.musicTrack class")
	}
}

func TestServerMediaFile(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "LosslessMusic Test")

	baseURL, err := srv.Start()
	if err != nil {
		t.Fatalf("Start() error: %v", err)
	}
	defer srv.Stop()

	// Get the media URL from a browse response.
	encoded := encodeObjectID("Artist/Album/01 Song.flac")
	mediaURL := baseURL + "/media/" + encoded

	resp, err := http.Get(mediaURL)
	if err != nil {
		t.Fatalf("GET media: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET media status = %d, want 200", resp.StatusCode)
	}
	got, _ := io.ReadAll(resp.Body)
	if string(got) != "FLACDATA" {
		t.Errorf("media body = %q, want %q", got, "FLACDATA")
	}
}

func TestServerMediaTraversalForbidden(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "LosslessMusic Test")

	baseURL, err := srv.Start()
	if err != nil {
		t.Fatalf("Start() error: %v", err)
	}
	defer srv.Stop()

	// Encode a traversal path.
	traversalID := encodeObjectID("../etc/passwd")
	resp, err := http.Get(baseURL + "/media/" + traversalID)
	if err != nil {
		t.Fatalf("GET traversal: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusForbidden && resp.StatusCode != http.StatusNotFound {
		t.Errorf("traversal attempt got status %d, want 403 or 404", resp.StatusCode)
	}
}

func TestServerStatus(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "StatusTest")

	running, url, name := srv.Status()
	if running {
		t.Error("expected not running before Start")
	}
	if url != "" {
		t.Errorf("expected empty url before Start, got %q", url)
	}

	_, err := srv.Start()
	if err != nil {
		t.Fatalf("Start() error: %v", err)
	}
	defer srv.Stop()

	running, url, name = srv.Status()
	if !running {
		t.Error("expected running after Start")
	}
	if url == "" {
		t.Error("expected non-empty url after Start")
	}
	if name != "StatusTest" {
		t.Errorf("name = %q, want %q", name, "StatusTest")
	}
}

func TestServerStop(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "StopTest")

	baseURL, err := srv.Start()
	if err != nil {
		t.Fatalf("Start() error: %v", err)
	}

	if err := srv.Stop(); err != nil {
		t.Fatalf("Stop() error: %v", err)
	}

	running, _, _ := srv.Status()
	if running {
		t.Error("expected not running after Stop")
	}

	// Requests should fail after stop.
	_, err = http.Get(baseURL + "/description.xml")
	if err == nil {
		t.Error("expected connection error after Stop, got nil")
	}
}

func TestStableUDN(t *testing.T) {
	udn1 := stableUDN("MyServer", "/music")
	udn2 := stableUDN("MyServer", "/music")
	if udn1 != udn2 {
		t.Errorf("stableUDN not deterministic: %q != %q", udn1, udn2)
	}
	udn3 := stableUDN("OtherServer", "/music")
	if udn1 == udn3 {
		t.Error("different inputs produced same UDN")
	}
	if !strings.HasPrefix(udn1, "uuid:") {
		t.Errorf("UDN missing uuid: prefix: %q", udn1)
	}
}

// TestHandlersViaHttptest uses httptest.NewServer to verify handler wiring
// without needing a real network.
func TestHandlersViaHttptest(t *testing.T) {
	dir := seedDir(t)
	srv := NewMediaServer(dir, "HttptestServer")
	srv.baseURL = "http://127.0.0.1:0" // will be overridden by httptest

	mux := http.NewServeMux()
	mux.HandleFunc("/description.xml", srv.handleDescription)
	mux.HandleFunc("/cd/scpd", srv.handleSCPD)
	mux.HandleFunc("/cd/control", srv.handleControl)
	mux.HandleFunc("/media/", srv.handleMedia)

	ts := httptest.NewServer(mux)
	defer ts.Close()

	// Update baseURL so media URLs are correct.
	srv.mu.Lock()
	srv.baseURL = ts.URL
	srv.mu.Unlock()

	t.Run("description", func(t *testing.T) {
		resp, err := http.Get(ts.URL + "/description.xml")
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("status %d", resp.StatusCode)
		}
		b, _ := io.ReadAll(resp.Body)
		if !strings.Contains(string(b), "HttptestServer") {
			t.Error("missing friendlyName")
		}
	})

	t.Run("scpd", func(t *testing.T) {
		resp, err := http.Get(ts.URL + "/cd/scpd")
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("status %d", resp.StatusCode)
		}
		b, _ := io.ReadAll(resp.Body)
		if !strings.Contains(string(b), "Browse") {
			t.Error("SCPD missing Browse")
		}
	})

	t.Run("browse-root", func(t *testing.T) {
		body := `<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag></u:Browse></s:Body></s:Envelope>`
		resp, err := http.Post(ts.URL+"/cd/control", "text/xml", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("status %d", resp.StatusCode)
		}
		b, _ := io.ReadAll(resp.Body)
		if !strings.Contains(string(b), "Artist") {
			t.Error("missing Artist in browse response")
		}
	})

	t.Run("media-ok", func(t *testing.T) {
		encoded := encodeObjectID("Artist/Album/01 Song.flac")
		resp, err := http.Get(ts.URL + "/media/" + encoded)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("status %d", resp.StatusCode)
		}
		b, _ := io.ReadAll(resp.Body)
		if string(b) != "FLACDATA" {
			t.Errorf("body = %q, want FLACDATA", b)
		}
	})

	t.Run("media-traversal", func(t *testing.T) {
		encoded := encodeObjectID("../outside")
		resp, err := http.Get(ts.URL + "/media/" + encoded)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		if resp.StatusCode != 403 && resp.StatusCode != 404 {
			t.Errorf("traversal got status %d, want 403 or 404", resp.StatusCode)
		}
	})
}

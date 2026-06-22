package server

import (
	"bytes"
	"context"
	"crypto/sha1"
	"encoding/xml"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// MediaServer serves the download library over HTTP so DLNA players can browse and stream it.
type MediaServer struct {
	rootDir      string
	friendlyName string
	udn          string
	httpSrv      *http.Server
	baseURL      string
	ssdp         *ssdpResponder
	mu           sync.Mutex
	running      bool
}

// NewMediaServer creates a new MediaServer. The UDN is derived deterministically
// from a SHA-1 hash of friendlyName+rootDir so the device identity is stable
// across restarts with no external randomness.
func NewMediaServer(rootDir, friendlyName string) *MediaServer {
	udn := stableUDN(friendlyName, rootDir)
	return &MediaServer{
		rootDir:      rootDir,
		friendlyName: friendlyName,
		udn:          udn,
	}
}

// stableUDN produces a deterministic uuid: URN from a SHA-1 of name+rootDir,
// formatted as a standard UUID (8-4-4-4-12 hex groups).
func stableUDN(name, rootDir string) string {
	h := sha1.New()
	h.Write([]byte(name))
	h.Write([]byte{0x00})
	h.Write([]byte(rootDir))
	sum := h.Sum(nil) // 20 bytes
	// Format first 16 bytes as a UUID (version 5 style, but without strict RFC compliance).
	b := sum[:16]
	// Set version bits (version 5 = 0101) and variant bits (10xxxxxx).
	b[6] = (b[6] & 0x0f) | 0x50
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("uuid:%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// Start picks a LAN IPv4, listens on port 8200 (falls back to :0), registers
// HTTP handlers, starts serving in a goroutine, and returns the base URL.
func (s *MediaServer) Start() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.running {
		return s.baseURL, nil
	}

	ip, err := lanIPv4()
	if err != nil {
		ip = "127.0.0.1"
	}

	// Try port 8200 first, fall back to any free port.
	ln, err := net.Listen("tcp", fmt.Sprintf("%s:8200", ip))
	if err != nil {
		ln, err = net.Listen("tcp", fmt.Sprintf("%s:0", ip))
		if err != nil {
			return "", fmt.Errorf("MediaServer.Start: listen: %w", err)
		}
	}

	s.baseURL = fmt.Sprintf("http://%s", ln.Addr().String())

	mux := http.NewServeMux()
	mux.HandleFunc("/description.xml", s.handleDescription)
	mux.HandleFunc("/cd/scpd", s.handleSCPD)
	mux.HandleFunc("/cd/control", s.handleControl)
	mux.HandleFunc("/media/", s.handleMedia)

	s.httpSrv = &http.Server{Handler: mux}

	go func() {
		_ = s.httpSrv.Serve(ln)
	}()

	// Start SSDP advertisement (best-effort: failure does not abort the server).
	s.ssdp = &ssdpResponder{}
	location := s.baseURL + "/description.xml"
	if err := s.ssdp.start(location, s.udn); err != nil {
		log.Printf("MediaServer: SSDP unavailable (best-effort): %v", err)
		s.ssdp = nil
	}

	s.running = true
	return s.baseURL, nil
}

// Stop gracefully shuts down the HTTP server.
func (s *MediaServer) Stop() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if !s.running {
		return nil
	}

	// Stop SSDP before shutting down HTTP so byebye goes out while still alive.
	if s.ssdp != nil {
		s.ssdp.stop(s.udn)
		s.ssdp = nil
	}

	err := s.httpSrv.Shutdown(context.Background())
	s.running = false
	return err
}

// Status returns whether the server is running, the base URL, and the friendly name.
func (s *MediaServer) Status() (running bool, url, name string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.running, s.baseURL, s.friendlyName
}

// handleDescription serves the UPnP device description XML.
func (s *MediaServer) handleDescription(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	friendlyName := s.friendlyName
	udn := s.udn
	baseURL := s.baseURL
	s.mu.Unlock()

	data := deviceDescriptionXML(friendlyName, udn, baseURL)
	w.Header().Set("Content-Type", "text/xml; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

// handleSCPD serves the ContentDirectory SCPD XML.
func (s *MediaServer) handleSCPD(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/xml; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(contentDirectorySCPD())
}

// handleControl handles SOAP Browse requests for ContentDirectory.
func (s *MediaServer) handleControl(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	objectID, browseFlag, err := parseBrowse(body)
	if err != nil {
		http.Error(w, "Bad Request: "+err.Error(), http.StatusBadRequest)
		return
	}

	var didl []byte
	var numReturned, totalMatches int
	if browseFlag == "BrowseMetadata" {
		didl, numReturned, totalMatches, err = s.browseMetadata(objectID)
	} else {
		didl, numReturned, totalMatches, err = s.browse(objectID)
	}
	if err != nil {
		http.Error(w, "Internal Server Error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	resp := buildBrowseResponse(didl, numReturned, totalMatches)
	w.Header().Set("Content-Type", "text/xml; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(resp)
}

// buildBrowseResponse wraps DIDL-Lite in a SOAP BrowseResponse envelope.
// The DIDL is escaped as a string inside the Result element.
func buildBrowseResponse(didl []byte, numReturned, totalMatches int) []byte {
	var escapedDidl bytes.Buffer
	xml.EscapeText(&escapedDidl, didl)

	return []byte(fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
      <Result>%s</Result>
      <NumberReturned>%d</NumberReturned>
      <TotalMatches>%d</TotalMatches>
      <UpdateID>1</UpdateID>
    </u:BrowseResponse>
  </s:Body>
</s:Envelope>`, escapedDidl.String(), numReturned, totalMatches))
}

// handleMedia serves audio files under /media/<encodedRelPath>.
// It validates the decoded path stays within rootDir, then delegates to http.ServeFile
// which handles Range requests automatically.
func (s *MediaServer) handleMedia(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	rootDir := s.rootDir
	s.mu.Unlock()

	// Strip the "/media/" prefix.
	encodedRel := strings.TrimPrefix(r.URL.Path, "/media/")
	if encodedRel == "" {
		http.Error(w, "Not Found", http.StatusNotFound)
		return
	}

	relPath, err := decodeObjectID(encodedRel)
	if err != nil {
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	// Traversal guard 1: reject ".." components in the decoded path.
	if err := validateRelPath(relPath); err != nil {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	absPath := filepath.Join(rootDir, relPath)

	// Traversal guard 2: clean resolved path must be under rootDir.
	rootClean := filepath.Clean(rootDir)
	absClean := filepath.Clean(absPath)
	if !strings.HasPrefix(absClean+string(filepath.Separator), rootClean+string(filepath.Separator)) {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	// Reject directories.
	info, err := os.Stat(absPath)
	if err != nil || info.IsDir() {
		http.Error(w, "Not Found", http.StatusNotFound)
		return
	}

	http.ServeFile(w, r, absPath)
}

package server

import (
	"encoding/base64"
	"encoding/xml"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// audioExtensions is the set of supported audio file extensions (lowercase, with dot).
var audioExtensions = map[string]string{
	".flac": "audio/flac",
	".m4a":  "audio/mp4",
	".mp3":  "audio/mpeg",
	".alac": "audio/mp4",
	".opus": "audio/ogg",
	".ogg":  "audio/ogg",
	".wav":  "audio/wav",
	".aiff": "audio/aiff",
	".aif":  "audio/aiff",
}

// mimeForExt returns the MIME type for the given file extension (with dot, any case).
func mimeForExt(ext string) string {
	if m, ok := audioExtensions[strings.ToLower(ext)]; ok {
		return m
	}
	return "application/octet-stream"
}

// encodeObjectID encodes a relative path to a URL-safe base64 objectID.
func encodeObjectID(relPath string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(relPath))
}

// decodeObjectID decodes a base64 objectID back to a relative path.
func decodeObjectID(id string) (string, error) {
	b, err := base64.RawURLEncoding.DecodeString(id)
	if err != nil {
		return "", fmt.Errorf("decodeObjectID: %w", err)
	}
	return string(b), nil
}

// soapBrowse is a minimal struct for parsing the SOAP Browse request.
type soapBrowse struct {
	ObjectID   string `xml:"Body>Browse>ObjectID"`
	BrowseFlag string `xml:"Body>Browse>BrowseFlag"`
}

// parseBrowse extracts ObjectID and BrowseFlag from a SOAP Browse request body.
func parseBrowse(soapBody []byte) (objectID string, browseFlag string, err error) {
	var env soapBrowse
	if err := xml.Unmarshal(soapBody, &env); err != nil {
		return "", "", fmt.Errorf("parseBrowse: %w", err)
	}
	return env.ObjectID, env.BrowseFlag, nil
}

// browse lists the contents of the directory identified by objectID and
// returns DIDL-Lite XML plus counts. objectID "0" maps to rootDir.
func (s *MediaServer) browse(objectID string) (didl []byte, numReturned, totalMatches int, err error) {
	s.mu.Lock()
	rootDir := s.rootDir
	baseURL := s.baseURL
	s.mu.Unlock()

	// Resolve the target directory.
	var targetDir string
	var parentID string

	if objectID == "0" {
		targetDir = rootDir
		parentID = "-1"
	} else {
		relPath, err := decodeObjectID(objectID)
		if err != nil {
			return nil, 0, 0, fmt.Errorf("browse: invalid objectID: %w", err)
		}
		// Traversal guard: clean path must not escape rootDir.
		if err := validateRelPath(relPath); err != nil {
			return nil, 0, 0, err
		}
		targetDir = filepath.Join(rootDir, relPath)
		// Absolute-path check: resolved path must still be under rootDir.
		clean := filepath.Clean(targetDir)
		rootClean := filepath.Clean(rootDir)
		if !strings.HasPrefix(clean+string(filepath.Separator), rootClean+string(filepath.Separator)) {
			return nil, 0, 0, fmt.Errorf("browse: path escapes rootDir")
		}
		// Parent is the encoded parent rel path, or "0" if parent is rootDir.
		parentRel := filepath.Dir(relPath)
		if parentRel == "." {
			parentID = "0"
		} else {
			parentID = encodeObjectID(parentRel)
		}
	}

	entries, err := os.ReadDir(targetDir)
	if err != nil {
		return nil, 0, 0, fmt.Errorf("browse: ReadDir %s: %w", targetDir, err)
	}

	var containers []cdObject
	var items []cdItem

	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(name, ".") {
			continue // skip hidden
		}

		if entry.IsDir() {
			// Count audio+dir children for childCount.
			childCount := countChildren(filepath.Join(targetDir, name))
			var relPath string
			if objectID == "0" {
				relPath = name
			} else {
				pRel, _ := decodeObjectID(objectID)
				relPath = filepath.Join(pRel, name)
			}
			containers = append(containers, cdObject{
				id:         encodeObjectID(relPath),
				parentID:   objectID,
				title:      name,
				childCount: childCount,
			})
		} else {
			ext := filepath.Ext(name)
			mime, ok := audioExtensions[strings.ToLower(ext)]
			if !ok {
				continue
			}
			var relPath string
			if objectID == "0" {
				relPath = name
			} else {
				pRel, _ := decodeObjectID(objectID)
				relPath = filepath.Join(pRel, name)
			}
			encoded := encodeObjectID(relPath)
			info, err := entry.Info()
			var size int64
			if err == nil {
				size = info.Size()
			}
			// Derive title from filename (strip extension).
			title := strings.TrimSuffix(name, ext)
			items = append(items, cdItem{
				id:       encoded,
				parentID: objectID,
				title:    title,
				size:     size,
				mime:     mime,
				url:      baseURL + "/media/" + encoded,
			})
		}
	}

	_ = parentID // used only in metadata browse (BrowseMetadata); see browseMetadata

	total := len(containers) + len(items)
	return didlLite(containers, items), total, total, nil
}

// browseMetadata returns a single-item DIDL-Lite describing the metadata of
// the object identified by objectID. Only objectID "0" (root container) is
// currently supported; all other IDs return an error.
func (s *MediaServer) browseMetadata(objectID string) (didl []byte, numReturned, totalMatches int, err error) {
	s.mu.Lock()
	rootDir := s.rootDir
	friendlyName := s.friendlyName
	s.mu.Unlock()

	if objectID != "0" {
		return nil, 0, 0, fmt.Errorf("browseMetadata: unsupported objectID %q", objectID)
	}

	// Count direct children of root for childCount.
	childCount := countChildren(rootDir)

	container := cdObject{
		id:         "0",
		parentID:   "-1",
		title:      friendlyName,
		childCount: childCount,
	}
	return didlLite([]cdObject{container}, nil), 1, 1, nil
}

// validateRelPath rejects relative paths containing ".." components.
func validateRelPath(relPath string) error {
	clean := filepath.Clean(relPath)
	if strings.HasPrefix(clean, "..") {
		return fmt.Errorf("browse: relative path escapes root: %s", relPath)
	}
	for _, part := range strings.Split(relPath, string(filepath.Separator)) {
		if part == ".." {
			return fmt.Errorf("browse: path component '..' not allowed")
		}
	}
	return nil
}

// countChildren counts the number of subdirectory and audio-file children
// in a directory (non-recursive). Returns 0 on error.
func countChildren(dir string) int {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0
	}
	count := 0
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".") {
			continue
		}
		if e.IsDir() {
			count++
		} else if _, ok := audioExtensions[strings.ToLower(filepath.Ext(e.Name()))]; ok {
			count++
		}
	}
	return count
}

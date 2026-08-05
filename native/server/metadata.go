package server

import (
	"fmt"
	"os"
	"sync"
)

// TrackTags is the subset of audio metadata the DLNA server exposes in
// DIDL-Lite so control points can show artist/album/cover/etc.
type TrackTags struct {
	Title       string
	Artist      string
	Album       string
	AlbumArtist string
	Genre       string
	TrackNumber int
	DurationSec int
	SampleRate  int // Hz
	BitDepth    int
	BitrateKbps int // average kbps, as reported by the scanner
}

// MetadataProvider reads embedded tags and cover art for a file. It is injected
// by the platform bridge (which owns the tag/cover readers in go_backend); when
// no provider is set the server falls back to filename-only titles, so this
// stays optional and dependency-free at the server layer.
type MetadataProvider interface {
	// ReadTags returns tags for absPath; ok=false means fall back to filename.
	ReadTags(absPath string) (tags TrackTags, ok bool)
	// ReadCover returns embedded cover bytes and their MIME; ok=false = no art.
	ReadCover(absPath string) (data []byte, mime string, ok bool)
}

// tagCache memoizes ReadTags by path + modtime so repeated browses of the same
// folder don't re-parse every file.
type tagCache struct {
	mu sync.Mutex
	m  map[string]tagCacheEntry
}

type tagCacheEntry struct {
	modUnixNano int64
	tags        TrackTags
	ok          bool
}

func newTagCache() *tagCache { return &tagCache{m: make(map[string]tagCacheEntry)} }

// get returns cached tags for absPath, reading (and caching) via provider on a
// miss or when the file's modtime changed.
func (c *tagCache) get(absPath string, provider MetadataProvider) (TrackTags, bool) {
	var mod int64
	if fi, err := os.Stat(absPath); err == nil {
		mod = fi.ModTime().UnixNano()
	}

	c.mu.Lock()
	if e, ok := c.m[absPath]; ok && e.modUnixNano == mod {
		c.mu.Unlock()
		return e.tags, e.ok
	}
	c.mu.Unlock()

	tags, ok := provider.ReadTags(absPath)

	c.mu.Lock()
	c.m[absPath] = tagCacheEntry{modUnixNano: mod, tags: tags, ok: ok}
	c.mu.Unlock()
	return tags, ok
}

// formatDuration renders seconds as the UPnP res@duration form "H:MM:SS".
// Returns "" for non-positive input so the attribute can be omitted.
func formatDuration(sec int) string {
	if sec <= 0 {
		return ""
	}
	return fmt.Sprintf("%d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
}

// protocolInfoFor returns the DLNA protocolInfo for a MIME type, including
// byte-seek (DLNA.ORG_OP=01) and streaming flags so renderers allow scrubbing.
// FLAC/AAC/ALAC/OGG have no universally-honoured DLNA.ORG_PN, so we ship just
// the MIME + flags, which every mainstream control point accepts.
func protocolInfoFor(mime string) string {
	const flags = "DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"
	if mime == "audio/mpeg" {
		return "http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;" + flags
	}
	return "http-get:*:" + mime + ":" + flags
}

// bitrateBytesPerSec converts kbps to the bytes/second that UPnP res@bitrate
// expects. UPnP defines bitrate in BYTES per second, not bits — a well-known
// spec quirk. Returns 0 (omit) for non-positive input.
func bitrateBytesPerSec(kbps int) int {
	if kbps <= 0 {
		return 0
	}
	return kbps * 1000 / 8
}

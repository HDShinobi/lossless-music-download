package gobackend

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// copyFixtureFLAC copies the tiny real FLAC fixture to a temp file so tests can
// embed into it without mutating the shared fixture.
func copyFixtureFLAC(t *testing.T) string {
	t.Helper()
	src, err := os.ReadFile("testdata/silence.flac")
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	dst := filepath.Join(t.TempDir(), "track.flac")
	if err := os.WriteFile(dst, src, 0644); err != nil {
		t.Fatalf("write temp flac: %v", err)
	}
	return dst
}

func TestEmbedMetadataAfterDownloadEmbedsLyricsWhenEnabled(t *testing.T) {
	flacPath := copyFixtureFLAC(t)

	original := lyricsLRCFetcher
	defer func() { lyricsLRCFetcher = original }()
	lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
		return "[00:01.00]test lyric line", nil
	}

	req := DownloadRequest{
		EmbedMetadata: true,
		EmbedLyrics:   true,
		TrackName:     "Opalite",
		ArtistName:    "Taylor Swift",
	}
	resp := DownloadResponse{FilePath: flacPath}

	embedMetadataAfterDownload(resp, req, false)

	md, err := ReadMetadata(flacPath)
	if err != nil {
		t.Fatalf("read metadata back: %v", err)
	}
	if !strings.Contains(md.Lyrics, "test lyric line") {
		t.Fatalf("expected lyrics embedded, got %q", md.Lyrics)
	}
}

func TestEmbedMetadataAfterDownloadPrefersRespLyricsOverFetch(t *testing.T) {
	flacPath := copyFixtureFLAC(t)

	original := lyricsLRCFetcher
	defer func() { lyricsLRCFetcher = original }()
	called := false
	lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
		called = true
		return "should not be fetched", nil
	}

	req := DownloadRequest{
		EmbedMetadata: true,
		EmbedLyrics:   true,
		TrackName:     "Opalite",
		ArtistName:    "Taylor Swift",
	}
	resp := DownloadResponse{FilePath: flacPath, LyricsLRC: "[00:01.00]resp lyric line"}

	embedMetadataAfterDownload(resp, req, false)

	if called {
		t.Fatal("lyrics fetcher must not be called when resp already has LyricsLRC")
	}
	md, err := ReadMetadata(flacPath)
	if err != nil {
		t.Fatalf("read metadata back: %v", err)
	}
	if !strings.Contains(md.Lyrics, "resp lyric line") {
		t.Fatalf("expected resp lyrics embedded, got %q", md.Lyrics)
	}
}

func TestEmbedMetadataAfterDownloadSkipsLyricsWhenDisabled(t *testing.T) {
	flacPath := copyFixtureFLAC(t)

	original := lyricsLRCFetcher
	defer func() { lyricsLRCFetcher = original }()
	called := false
	lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
		called = true
		return "should not be fetched", nil
	}

	req := DownloadRequest{
		EmbedMetadata: true,
		EmbedLyrics:   false,
		TrackName:     "Opalite",
		ArtistName:    "Taylor Swift",
	}
	resp := DownloadResponse{FilePath: flacPath}

	embedMetadataAfterDownload(resp, req, false)

	if called {
		t.Fatal("lyrics fetcher must not be called when EmbedLyrics is false")
	}
	md, err := ReadMetadata(flacPath)
	if err != nil {
		t.Fatalf("read metadata back: %v", err)
	}
	if md.Lyrics != "" {
		t.Fatalf("expected no lyrics, got %q", md.Lyrics)
	}
}

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

// The lyrics fetch is a network call, so it must stay behind the same guards
// upstream's embedExtensionDownloadMetadata applies -- otherwise every lossy
// download (tagged on the Dart FFmpeg side instead) and every already-on-disk
// skip would pay for a lyrics lookup nothing consumes.
func TestEmbedMetadataAfterDownloadSkipsFetchForNonFLAC(t *testing.T) {
	m4aPath := filepath.Join(t.TempDir(), "track.m4a")
	if err := os.WriteFile(m4aPath, []byte("not a flac"), 0644); err != nil {
		t.Fatalf("write temp m4a: %v", err)
	}

	original := lyricsLRCFetcher
	defer func() { lyricsLRCFetcher = original }()
	called := false
	lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
		called = true
		return "should not be fetched", nil
	}

	req := DownloadRequest{EmbedMetadata: true, EmbedLyrics: true, TrackName: "Opalite"}
	embedMetadataAfterDownload(DownloadResponse{FilePath: m4aPath}, req, false)

	if called {
		t.Fatal("lyrics fetcher must not be called for a non-FLAC output path")
	}
}

func TestEmbedMetadataAfterDownloadSkipsFetchWhenAlreadyExists(t *testing.T) {
	flacPath := copyFixtureFLAC(t)

	original := lyricsLRCFetcher
	defer func() { lyricsLRCFetcher = original }()
	called := false
	lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
		called = true
		return "should not be fetched", nil
	}

	req := DownloadRequest{EmbedMetadata: true, EmbedLyrics: true, TrackName: "Opalite"}
	embedMetadataAfterDownload(DownloadResponse{FilePath: flacPath}, req, true)

	if called {
		t.Fatal("lyrics fetcher must not be called when the file already exists")
	}
}

// "[instrumental:true]" is a sentinel from the lyrics providers, not lyrics --
// embedding it verbatim would put that literal string in the LYRICS tag.
func TestEmbedMetadataAfterDownloadDropsInstrumentalSentinel(t *testing.T) {
	for _, tc := range []struct{ name, respLRC, fetchedLRC string }{
		{"from resp", "[instrumental:true]", ""},
		{"from fetch", "", "[instrumental:true]"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			flacPath := copyFixtureFLAC(t)

			original := lyricsLRCFetcher
			defer func() { lyricsLRCFetcher = original }()
			lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
				return tc.fetchedLRC, nil
			}

			req := DownloadRequest{EmbedMetadata: true, EmbedLyrics: true, TrackName: "Opalite"}
			resp := DownloadResponse{FilePath: flacPath, LyricsLRC: tc.respLRC}

			embedMetadataAfterDownload(resp, req, false)

			md, err := ReadMetadata(flacPath)
			if err != nil {
				t.Fatalf("read metadata back: %v", err)
			}
			if md.Lyrics != "" {
				t.Fatalf("expected the instrumental sentinel to be dropped, got %q", md.Lyrics)
			}
		})
	}
}

// Whitespace-only lyrics on resp count as absent, so the fallback fetch runs.
func TestEmbedMetadataAfterDownloadTreatsBlankRespLyricsAsAbsent(t *testing.T) {
	flacPath := copyFixtureFLAC(t)

	original := lyricsLRCFetcher
	defer func() { lyricsLRCFetcher = original }()
	lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
		return "[00:01.00]fetched lyric line", nil
	}

	req := DownloadRequest{EmbedMetadata: true, EmbedLyrics: true, TrackName: "Opalite"}
	resp := DownloadResponse{FilePath: flacPath, LyricsLRC: "   \n  "}

	embedMetadataAfterDownload(resp, req, false)

	md, err := ReadMetadata(flacPath)
	if err != nil {
		t.Fatalf("read metadata back: %v", err)
	}
	if !strings.Contains(md.Lyrics, "fetched lyric line") {
		t.Fatalf("expected the fallback fetch to fill blank resp lyrics, got %q", md.Lyrics)
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

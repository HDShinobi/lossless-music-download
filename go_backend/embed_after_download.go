package gobackend

// This file holds LosslessMusic-v2's only intentional divergence from the
// vendored upstream (SpotiFLAC) post-download embed path: we resolve lyrics
// ourselves when the extension didn't supply any.
//
// Everything else -- field precedence, cover art, the FLAC writer -- is
// upstream's embedExtensionDownloadMetadata, which we *call* rather than copy,
// so upstream improvements to it land on a sync without touching this file.
// The only upstream touch-points are the embedMetadataAfterDownload(...) hooks
// at the extension download call sites (see docs/UPSTREAM-SYNC.md).

import "strings"

// instrumentalSentinel is what GetLyricsLRC returns for a track with no lyrics
// (see exports.go). It is a marker, not lyrics -- embedding it verbatim would
// write that literal string into the LYRICS tag.
const instrumentalSentinel = "[instrumental:true]"

// lyricsLRCFetcher fetches synced/plain lyrics (LRC) for a track from the
// configured lyrics providers. It is a package var so tests can stub the
// network boundary. filePath is intentionally empty here so it fetches online
// rather than re-reading the freshly downloaded (untagged) file.
var lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
	return GetLyricsLRC(spotifyID, trackName, artistName, "", durationMs)
}

// embedMetadataAfterDownload writes full tags + cover art + lyrics into a
// freshly downloaded local FLAC file. Lyrics are resolved here (our addition);
// the write itself is upstream's.
//
// Non-FLAC formats (Opus/M4A/MP3) are gated out by canEmbedGenreLabel and are
// tagged on the Dart side via FFmpeg instead.
func embedMetadataAfterDownload(resp DownloadResponse, req DownloadRequest, alreadyExists bool) {
	// resp is a value copy, so overwriting LyricsLRC only affects the handoff
	// below. These guards mirror upstream's own early returns: resolving lyrics
	// costs a network call, and upstream discards the result in every one of
	// these cases.
	if req.EmbedLyrics && req.EmbedMetadata && !alreadyExists &&
		canEmbedGenreLabel(strings.TrimSpace(resp.FilePath)) {
		resp.LyricsLRC = resolveLyricsLRC(resp, req)
	}

	embedExtensionDownloadMetadata(resp, req, alreadyExists)
}

// resolveLyricsLRC prefers lyrics the extension already resolved and only falls
// back to our own providers when it supplied none. Most extensions never
// populate resp.LyricsLRC, so without this fallback the majority of downloads
// would carry no lyrics -- which is why we hook the embed path at all.
func resolveLyricsLRC(resp DownloadResponse, req DownloadRequest) string {
	lrc := strings.TrimSpace(resp.LyricsLRC)
	if lrc == "" {
		fetched, err := lyricsLRCFetcher(req.SpotifyID, req.TrackName, req.ArtistName, int64(req.DurationMS))
		if err != nil {
			GoLog("[DownloadWithExtensionFallback] Warning: failed to fetch lyrics: %v\n", err)
			return ""
		}
		lrc = strings.TrimSpace(fetched)
	}
	if lrc == instrumentalSentinel {
		return ""
	}
	return lrc
}

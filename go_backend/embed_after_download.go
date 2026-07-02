package gobackend

// This file holds LosslessMusic-v2's own post-download metadata embedding,
// kept separate from the vendored upstream (SpotiFLAC) sources so that
// `git diff upstream/main -- go_backend/` stays clean and future upstream
// syncs are easy. The only upstream touch-points are the two one-line
// embedMetadataAfterDownload(...) hooks in extension_providers.go.

import "strings"

// lyricsLRCFetcher fetches synced/plain lyrics (LRC) for a track from the
// configured lyrics providers. It is a package var so tests can stub the
// network boundary. filePath is intentionally empty here so it fetches online
// rather than re-reading the freshly downloaded (untagged) file.
var lyricsLRCFetcher = func(spotifyID, trackName, artistName string, durationMs int64) (string, error) {
	return GetLyricsLRC(spotifyID, trackName, artistName, "", durationMs)
}

// embedMetadataAfterDownload writes full tags + cover art + lyrics into a
// freshly downloaded local FLAC file using the native Go writer. Non-FLAC
// formats (Opus/M4A/MP3) are gated out by canEmbedGenreLabel and are tagged
// on the Dart side via FFmpeg instead.
//
// Fields prefer resp (the resolved download result) over req (the original
// request) via firstNonEmptyTrimmed/firstPositiveInt, matching upstream's
// v4.7.1 embedExtensionDownloadMetadata -- resp reflects what was actually
// downloaded, which can differ from the pre-download search request.
func embedMetadataAfterDownload(resp DownloadResponse, req DownloadRequest, alreadyExists bool) {
	if alreadyExists || !req.EmbedMetadata {
		return
	}
	filePath := strings.TrimSpace(resp.FilePath)
	if !canEmbedGenreLabel(filePath) {
		return
	}

	// 1. Download cover art if available
	var coverData []byte
	if coverURL := firstNonEmptyTrimmed(resp.CoverURL, req.CoverURL); coverURL != "" {
		data, err := downloadCoverToMemory(coverURL, req.EmbedMaxQualityCover)
		if err != nil {
			GoLog("[DownloadWithExtensionFallback] Warning: failed to download cover art: %v\n", err)
		} else {
			coverData = data
		}
	}

	// 2. Build metadata struct
	metadata := Metadata{
		Title:         firstNonEmptyTrimmed(resp.Title, req.TrackName),
		Artist:        firstNonEmptyTrimmed(resp.Artist, req.ArtistName),
		Album:         firstNonEmptyTrimmed(resp.Album, req.AlbumName),
		AlbumArtist:   firstNonEmptyTrimmed(resp.AlbumArtist, req.AlbumArtist),
		ArtistTagMode: req.ArtistTagMode,
		Date:          firstNonEmptyTrimmed(resp.ReleaseDate, req.ReleaseDate),
		TrackNumber:   firstPositiveInt(resp.TrackNumber, req.TrackNumber),
		TotalTracks:   firstPositiveInt(resp.TotalTracks, req.TotalTracks),
		DiscNumber:    firstPositiveInt(resp.DiscNumber, req.DiscNumber),
		TotalDiscs:    firstPositiveInt(resp.TotalDiscs, req.TotalDiscs),
		ISRC:          firstNonEmptyTrimmed(resp.ISRC, req.ISRC),
		Genre:         firstNonEmptyTrimmed(resp.Genre, req.Genre),
		Label:         firstNonEmptyTrimmed(resp.Label, req.Label),
		Copyright:     firstNonEmptyTrimmed(resp.Copyright, req.Copyright),
		Composer:      firstNonEmptyTrimmed(resp.Composer, req.Composer),
	}

	// 2b. Attach lyrics (LRC) so they are embedded as Vorbis
	// LYRICS/UNSYNCEDLYRICS comments, matching SpotiFLAC behaviour. Prefer
	// lyrics the extension/provider already resolved on resp; only hit our
	// own lyrics providers when it didn't supply any, so most extensions
	// (which don't populate LyricsLRC) still get lyrics embedded.
	if req.EmbedLyrics {
		lrc := strings.TrimSpace(resp.LyricsLRC)
		if lrc == "" {
			fetched, err := lyricsLRCFetcher(req.SpotifyID, req.TrackName, req.ArtistName, int64(req.DurationMS))
			if err != nil {
				GoLog("[DownloadWithExtensionFallback] Warning: failed to fetch lyrics: %v\n", err)
			} else {
				lrc = strings.TrimSpace(fetched)
			}
		}
		if lrc != "" && lrc != "[instrumental:true]" {
			metadata.Lyrics = lrc
		}
	}

	// 3. Embed metadata and cover
	if len(coverData) > 0 {
		if err := EmbedMetadataWithCoverData(filePath, metadata, coverData); err != nil {
			GoLog("[DownloadWithExtensionFallback] Warning: failed to embed metadata with cover: %v\n", err)
		} else {
			GoLog("[DownloadWithExtensionFallback] Embedded metadata with cover\n")
		}
	} else {
		if err := EmbedMetadata(filePath, metadata, ""); err != nil {
			GoLog("[DownloadWithExtensionFallback] Warning: failed to embed metadata: %v\n", err)
		} else {
			GoLog("[DownloadWithExtensionFallback] Embedded metadata without cover\n")
		}
	}
}

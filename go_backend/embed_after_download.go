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
func embedMetadataAfterDownload(req DownloadRequest, filePath string) {
	if !req.EmbedMetadata || !canEmbedGenreLabel(filePath) {
		return
	}

	// 1. Download cover art if available
	var coverData []byte
	var coverErr error
	if req.EmbedMaxQualityCover && req.CoverURL != "" {
		coverData, coverErr = downloadCoverToMemory(req.CoverURL, true)
	} else if req.CoverURL != "" {
		coverData, coverErr = downloadCoverToMemory(req.CoverURL, false)
	}
	if coverErr != nil {
		GoLog("[DownloadWithExtensionFallback] Warning: failed to download cover art: %v\n", coverErr)
	}

	// 2. Build metadata struct
	metadata := Metadata{
		Title:         req.TrackName,
		Artist:        req.ArtistName,
		Album:         req.AlbumName,
		AlbumArtist:   req.AlbumArtist,
		ArtistTagMode: req.ArtistTagMode,
		Date:          req.ReleaseDate,
		TrackNumber:   req.TrackNumber,
		TotalTracks:   req.TotalTracks,
		DiscNumber:    req.DiscNumber,
		TotalDiscs:    req.TotalDiscs,
		ISRC:          req.ISRC,
		Genre:         req.Genre,
		Label:         req.Label,
		Copyright:     req.Copyright,
		Composer:      req.Composer,
	}

	// 2b. Fetch and attach lyrics (LRC) so they are embedded as Vorbis
	// LYRICS/UNSYNCEDLYRICS comments, matching SpotiFLAC behaviour.
	if req.EmbedLyrics {
		if lrc, err := lyricsLRCFetcher(req.SpotifyID, req.TrackName, req.ArtistName, int64(req.DurationMS)); err != nil {
			GoLog("[DownloadWithExtensionFallback] Warning: failed to fetch lyrics: %v\n", err)
		} else {
			lrc = strings.TrimSpace(lrc)
			if lrc != "" && lrc != "[instrumental:true]" {
				metadata.Lyrics = lrc
			}
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

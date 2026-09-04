// Package bridge is the unified gomobile entry point.
// It re-exports selected functions from the hello smoke-test and the
// SpotiFLAC go_backend so that both packages are compiled into a single
// AAR (avoiding duplicate go.Seq / libgojni.so conflicts).
package bridge

import (
	"encoding/json"
	"net/http"
	"sync"

	"github.com/zarz/spotiflac_android/go_backend"
	"xyz.losslessmusic/server"
)

// goBackendMetadata adapts go_backend's tag/cover readers to the DLNA server's
// MetadataProvider, so the MediaServer can expose real artist/album/cover/etc.
// without the server package depending on go_backend.
type goBackendMetadata struct{}

func (goBackendMetadata) ReadTags(absPath string) (server.TrackTags, bool) {
	js, err := gobackend.ReadAudioMetadataJSON(absPath)
	if err != nil || js == "" {
		return server.TrackTags{}, false
	}
	var r struct {
		TrackName   string `json:"trackName"`
		ArtistName  string `json:"artistName"`
		AlbumName   string `json:"albumName"`
		AlbumArtist string `json:"albumArtist"`
		Genre       string `json:"genre"`
		TrackNumber int    `json:"trackNumber"`
		Duration    int    `json:"duration"`
		SampleRate  int    `json:"sampleRate"`
		BitDepth    int    `json:"bitDepth"`
		Bitrate     int    `json:"bitrate"`
	}
	if err := json.Unmarshal([]byte(js), &r); err != nil {
		return server.TrackTags{}, false
	}
	return server.TrackTags{
		Title:       r.TrackName,
		Artist:      r.ArtistName,
		Album:       r.AlbumName,
		AlbumArtist: r.AlbumArtist,
		Genre:       r.Genre,
		TrackNumber: r.TrackNumber,
		DurationSec: r.Duration,
		SampleRate:  r.SampleRate,
		BitDepth:    r.BitDepth,
		BitrateKbps: r.Bitrate,
	}, true
}

func (goBackendMetadata) ReadCover(absPath string) ([]byte, string, bool) {
	data, err := gobackend.ExtractCoverArt(absPath)
	if err != nil || len(data) == 0 {
		return nil, "", false
	}
	return data, http.DetectContentType(data), true
}

// --- DLNA MediaServer (Serve) ---------------------------------------------

var (
	mediaServerMu sync.Mutex
	mediaServer   *server.MediaServer
)

func mediaServerStatusJSON(running bool, url, name string) string {
	b, _ := json.Marshal(map[string]any{
		"running": running,
		"url":     url,
		"name":    name,
	})
	return string(b)
}

// StartMediaServer starts the DLNA MediaServer exposing rootDir on the LAN.
// Idempotent: returns the current status JSON if already running.
//
// lanIP is the device's Wi-Fi IPv4 as resolved by the Android framework
// (ConnectivityManager). Go's net.Interfaces() is blocked by SELinux on
// Android 11+, so the platform layer must supply the LAN IP; pass "" on hosts
// where the Go-side fallback (net.Interfaces) works.
func StartMediaServer(rootDir, friendlyName, lanIP string) (string, error) {
	mediaServerMu.Lock()
	defer mediaServerMu.Unlock()
	if mediaServer != nil {
		if running, url, name := mediaServer.Status(); running {
			return mediaServerStatusJSON(true, url, name), nil
		}
	}
	ms := server.NewMediaServer(rootDir, friendlyName, lanIP)
	ms.SetMetadataProvider(goBackendMetadata{})
	if _, err := ms.Start(); err != nil {
		return "", err
	}
	mediaServer = ms
	running, url, name := ms.Status()
	return mediaServerStatusJSON(running, url, name), nil
}

// StopMediaServer stops the DLNA MediaServer if running.
func StopMediaServer() error {
	mediaServerMu.Lock()
	defer mediaServerMu.Unlock()
	if mediaServer == nil {
		return nil
	}
	err := mediaServer.Stop()
	mediaServer = nil
	return err
}

// GetMediaServerStatus returns the server status as JSON
// {"running":bool,"url":string,"name":string}.
func GetMediaServerStatus() string {
	mediaServerMu.Lock()
	defer mediaServerMu.Unlock()
	if mediaServer == nil {
		return mediaServerStatusJSON(false, "", "")
	}
	running, url, name := mediaServer.Status()
	return mediaServerStatusJSON(running, url, name)
}

// Ping returns a fixed string to prove the gomobile bridge works.
func Ping() string {
	return "pong"
}

// GetAudioQualityJSON probes a local audio file and returns its measured
// quality (bit_depth, sample_rate, bitrate, codec, duration) as JSON. Used by
// the Library + Verified screens to show real quality instead of placeholders.
func GetAudioQualityJSON(filePath string) (string, error) {
	q, err := gobackend.GetAudioQuality(filePath)
	if err != nil {
		return "", err
	}
	b, err := json.Marshal(q)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// --- Extension management ---

// SetExtensionStorageMasterKey installs the platform-keystore-backed key the
// engine uses to encrypt extension settings/credentials at rest. As of the
// v4.9.5 sync InitExtensionSystem refuses to configure the extension
// directories until this key is set, so the host MUST call this (with a base64
// 32-byte key stored in Android Keystore via flutter_secure_storage) BEFORE
// InitExtensionSystem — otherwise every extension install/upgrade fails with
// "extension directory is not configured" and no extensions load.
func SetExtensionStorageMasterKey(encodedKey string) error {
	return gobackend.SetExtensionStorageMasterKey(encodedKey)
}

// InitExtensionSystem initialises the extension subsystem with the given
// extensions directory and data directory. Call SetExtensionStorageMasterKey
// first (see above).
func InitExtensionSystem(extensionsDir, dataDir string) error {
	return gobackend.InitExtensionSystem(extensionsDir, dataDir)
}

// LoadExtensionFromPath installs an extension from a local file path and
// returns a JSON-encoded result or an error.
func LoadExtensionFromPath(filePath string) (string, error) {
	return gobackend.LoadExtensionFromPath(filePath)
}

// GetInstalledExtensions returns a JSON-encoded list of installed extensions.
func GetInstalledExtensions() (string, error) {
	return gobackend.GetInstalledExtensions()
}

// LoadExtensionsFromDir scans a directory and loads every persisted extension
// into the runtime, so extensions installed in a previous session reappear
// after an app restart. Returns a JSON summary {"loaded":[...],"errors":[...]}.
func LoadExtensionsFromDir(dirPath string) (string, error) {
	return gobackend.LoadExtensionsFromDir(dirPath)
}

// HandleURLWithExtensionJSON resolves a shared/deep-link URL (Spotify, Deezer,
// Tidal, ...) via the installed extensions, returning the resolved
// track/album/playlist as JSON ({"type":...,"track":{...}|"tracks":[...]}).
func HandleURLWithExtensionJSON(url string) (string, error) {
	return gobackend.HandleURLWithExtensionJSON(url)
}

// FindURLHandlerJSON returns JSON describing which installed extension (if any)
// can handle the given URL.
func FindURLHandlerJSON(url string) string {
	return gobackend.FindURLHandlerJSON(url)
}

// SetExtensionEnabledByID enables or disables an extension by its ID.
func SetExtensionEnabledByID(id string, enabled bool) error {
	return gobackend.SetExtensionEnabledByID(id, enabled)
}

// RemoveExtensionByID uninstalls the extension with the given ID.
func RemoveExtensionByID(id string) error {
	return gobackend.RemoveExtensionByID(id)
}

// SetExtensionSessionGrantByID stores a signed-session auth grant (received
// via the spotiflac://session-grant deep link) for the given extension, so
// its JS runtime can exchange it for a session via session.completeGrant().
func SetExtensionSessionGrantByID(extensionID, grant string) {
	gobackend.SetExtensionSessionGrantByID(extensionID, grant)
}

// InvokeExtensionActionJSON calls a named action exported by an extension's
// JS runtime (e.g. "completeGrant") and returns its JSON-encoded result.
func InvokeExtensionActionJSON(extensionID, actionName string) (string, error) {
	return gobackend.InvokeExtensionActionJSON(extensionID, actionName)
}

// GetExtensionPendingAuthJSON returns the pending browser-auth challenge (if
// any) an extension raised -- {"extension_id","auth_url","callback_url"} -- or
// an empty string if there's no pending challenge for it.
func GetExtensionPendingAuthJSON(extensionID string) (string, error) {
	return gobackend.GetExtensionPendingAuthJSON(extensionID)
}

// GetExtensionHomeFeedJSON re-exports the go_backend home-feed fetch.
func GetExtensionHomeFeedJSON(extensionID string) (string, error) {
	return gobackend.GetExtensionHomeFeedJSON(extensionID)
}

// --- Search ---

// SearchTracksWithMetadataProvidersJSON searches for tracks using all
// available metadata providers and returns a JSON-encoded result.
func SearchTracksWithMetadataProvidersJSON(query string, limit int, includeExtensions bool) (string, error) {
	return gobackend.SearchTracksWithMetadataProvidersJSON(query, limit, includeExtensions)
}

// --- Download ---

// DownloadByStrategy starts a download using the strategy encoded in
// requestJSON and returns a JSON-encoded result.
func DownloadByStrategy(requestJSON string) (string, error) {
	return gobackend.DownloadByStrategy(requestJSON)
}

// GetAllDownloadProgress returns a JSON-encoded snapshot of all active
// download progress entries.
func GetAllDownloadProgress() string {
	return gobackend.GetAllDownloadProgress()
}

// CancelDownload cancels the download identified by itemID.
func CancelDownload(itemID string) {
	gobackend.CancelDownload(itemID)
}

// SetDownloadDirectory sets the default output directory for downloads.
func SetDownloadDirectory(path string) error {
	return gobackend.SetDownloadDirectory(path)
}

// AllowDownloadDir grants the backend access to a directory (used on
// platforms that require explicit directory permission grants).
func AllowDownloadDir(path string) {
	gobackend.AllowDownloadDir(path)
}

// --- Extension settings ---

// GetExtensionSettingsJSON returns a JSON-encoded map of settings for the
// extension identified by id.
func GetExtensionSettingsJSON(id string) (string, error) {
	return gobackend.GetExtensionSettingsJSON(id)
}

// SetExtensionSettingsJSON stores settings for the extension identified by id
// from a JSON-encoded map. Returns an error if the JSON is invalid.
func SetExtensionSettingsJSON(id, settingsJSON string) error {
	return gobackend.SetExtensionSettingsJSON(id, settingsJSON)
}

// GetProviderMetadataJSON fetches metadata for a specific resource (track,
// album, artist, playlist) from a named provider extension by its raw ID.
// providerID is the extension ID (e.g. "qobuz", "tidal"), resourceType is
// "artist", "album", "track", or "playlist", and resourceID is the
// provider-native ID (without any prefix).
func GetProviderMetadataJSON(providerID, resourceType, resourceID string) (string, error) {
	return gobackend.GetProviderMetadataJSON(providerID, resourceType, resourceID)
}

// --- Lyrics ---

// GetLyricsLRC fetches synced/plain lyrics as LRC text for a track. When
// filePath is non-empty it reads embedded lyrics from that file; when empty it
// fetches online from the configured lyrics providers by spotifyID/name/artist.
// Used by the Dart FFmpeg path to embed lyrics into non-FLAC downloads.
func GetLyricsLRC(spotifyID, trackName, artistName, filePath string, durationMs int64) (string, error) {
	return gobackend.GetLyricsLRC(spotifyID, trackName, artistName, filePath, durationMs)
}

// --- Library management (edit / re-enrich) ---------------------------------
//
// Thin re-exports of the vendored go_backend functions so they reach Dart via
// the MethodChannel. go_backend stays pristine (diffable against upstream);
// only this bridge file changes.

// EditFileMetadata writes the given metadata (JSON map of UPPERCASE tag keys)
// into the audio file at filePath. Returns a JSON result indicating the method
// used: "native"/"native_*" when the Go backend wrote the tags directly (FLAC,
// WAV, AIFF, APE…), or "ffmpeg" with a fields map for the Dart FFmpeg path to
// finish (MP3/Opus/M4A).
func EditFileMetadata(filePath, metadataJSON string) (string, error) {
	return gobackend.EditFileMetadata(filePath, metadataJSON)
}

// ReEnrichFile re-fetches metadata/cover/lyrics for an existing local file from
// the configured providers and re-embeds them. requestJSON matches the backend
// reEnrichRequest shape. Returns a JSON result (enriched fields + method).
func ReEnrichFile(requestJSON string) (string, error) {
	return gobackend.ReEnrichFile(requestJSON)
}

// --- Entity search (resolve artist/album by name) --------------------------

// CustomSearchWithExtensionJSON runs an extension's custom search with the
// given JSON options (e.g. {"filter":"artist","limit":10}) and returns the
// results as a JSON array of entity maps ({id,name,artists,images,item_type,
// provider_id,...}). Used to resolve an artist/album ID from a name when a
// track's metadata didn't include it.
func CustomSearchWithExtensionJSON(extensionID, query, optionsJSON string) (string, error) {
	return gobackend.CustomSearchWithExtensionJSON(extensionID, query, optionsJSON)
}

// --- Provider priority ---

// GetProviderPriorityJSON returns the current download provider priority as a
// JSON-encoded array of provider/extension IDs.
func GetProviderPriorityJSON() (string, error) { return gobackend.GetProviderPriorityJSON() }

// SetProviderPriorityJSON sets the download provider priority from a
// JSON-encoded array of provider/extension IDs.
func SetProviderPriorityJSON(j string) error { return gobackend.SetProviderPriorityJSON(j) }

// GetMetadataProviderPriorityJSON returns the current metadata provider
// priority as a JSON-encoded array of provider/extension IDs.
func GetMetadataProviderPriorityJSON() (string, error) {
	return gobackend.GetMetadataProviderPriorityJSON()
}

// SetMetadataProviderPriorityJSON sets the metadata provider priority from a
// JSON-encoded array of provider/extension IDs.
func SetMetadataProviderPriorityJSON(j string) error {
	return gobackend.SetMetadataProviderPriorityJSON(j)
}

// SetExtensionFallbackProviderIDsJSON sets the fallback provider/extension ID
// pool (used for auto-fallback on download failure) from a JSON-encoded
// array of provider/extension IDs.
func SetExtensionFallbackProviderIDsJSON(idsJSON string) error {
	return gobackend.SetExtensionFallbackProviderIDsJSON(idsJSON)
}

// --- Duplicate detection ---

// CheckDuplicate checks whether a track identified by isrc already exists
// in outputDir and returns a JSON-encoded {"exists":bool,"filepath":string}.
//
// Upstream v4.8.5 retired the single-track CheckDuplicate in favour of the
// batched CheckDuplicatesBatch (backed by a prebuilt ISRC index). We adapt the
// single call by querying the batch with a one-element track list and
// unwrapping the first result, preserving our Dart-facing shape.
func CheckDuplicate(outputDir, isrc string) (string, error) {
	tracksJSON, err := json.Marshal([]map[string]string{{"isrc": isrc}})
	if err != nil {
		return "", err
	}
	batchJSON, err := gobackend.CheckDuplicatesBatch(outputDir, string(tracksJSON))
	if err != nil {
		return "", err
	}
	var results []struct {
		Exists   bool   `json:"exists"`
		FilePath string `json:"file_path"`
	}
	if err := json.Unmarshal([]byte(batchJSON), &results); err != nil {
		return "", err
	}
	out := map[string]any{"exists": false, "filepath": ""}
	if len(results) > 0 {
		out["exists"] = results[0].Exists
		out["filepath"] = results[0].FilePath
	}
	b, err := json.Marshal(out)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// --- App version ---

// spotiflacBaselineVersion is the SpotiFLAC-Mobile version our vendored
// go_backend engine corresponds to (docs/UPSTREAM-SYNC.md "Current baseline").
// BUMP THIS ON EVERY UPSTREAM SYNC.
//
// The extension ecosystem gates installs on the SpotiFLAC app version via each
// manifest's minAppVersion (as of the v4.8.5 sync the engine enforces this),
// and the resolve/extension User-Agent is "SpotiFLAC-Mobile/<version>". Our
// fork's own 0.x version is meaningless there and, being below any 4.x
// minAppVersion, makes the engine reject every upstream extension. So we report
// the vendored SpotiFLAC baseline to the engine, not the fork version. The fork
// version is still what users see and what in-app auto-update compares.
const spotiflacBaselineVersion = "4.9.5"

// SetAppVersion is called at startup with the fork's versionName, but reports
// the vendored SpotiFLAC baseline (see spotiflacBaselineVersion) to the engine
// so extension minAppVersion gates pass and the User-Agent matches upstream.
func SetAppVersion(version string) {
	_ = version // fork version intentionally not forwarded; see above
	gobackend.SetAppVersion(spotiflacBaselineVersion)
}

// --- Library scan ---

// SetLibraryCoverCacheDir configures the directory where the library scanner
// extracts and caches embedded cover art images. Must be called before
// ScanLibraryFolderJSON for cover art to be extracted.
func SetLibraryCoverCacheDir(cacheDir string) {
	gobackend.SetLibraryCoverCacheDir(cacheDir)
}

// ScanLibraryFolderJSON scans a directory for audio files, reads their
// embedded metadata (ID3/Vorbis/M4A tags) and extracts cover art, then
// returns a JSON-encoded array of LibraryScanResult objects.
func ScanLibraryFolderJSON(folderPath string) (string, error) {
	return gobackend.ScanLibraryFolderJSON(folderPath)
}

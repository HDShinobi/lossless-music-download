// Package bridge is the unified gomobile entry point.
// It re-exports selected functions from the hello smoke-test and the
// SpotiFLAC go_backend so that both packages are compiled into a single
// AAR (avoiding duplicate go.Seq / libgojni.so conflicts).
package bridge

import (
	"encoding/json"
	"sync"

	"github.com/zarz/spotiflac_android/go_backend"
	"xyz.losslessmusic/server"
)

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
func StartMediaServer(rootDir, friendlyName string) (string, error) {
	mediaServerMu.Lock()
	defer mediaServerMu.Unlock()
	if mediaServer != nil {
		if running, url, name := mediaServer.Status(); running {
			return mediaServerStatusJSON(true, url, name), nil
		}
	}
	ms := server.NewMediaServer(rootDir, friendlyName)
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

// GetDownloadProgress delegates to the SpotiFLAC backend and returns
// a JSON-encoded progress snapshot.
func GetDownloadProgress() string {
	return gobackend.GetDownloadProgress()
}

// --- Extension management ---

// InitExtensionSystem initialises the extension subsystem with the given
// extensions directory and data directory.
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

// --- Duplicate detection ---

// CheckDuplicate checks whether a track identified by isrc already exists
// in outputDir and returns a JSON-encoded result.
func CheckDuplicate(outputDir, isrc string) (string, error) {
	return gobackend.CheckDuplicate(outputDir, isrc)
}

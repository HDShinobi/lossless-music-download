// Package bridge is the unified gomobile entry point.
// It re-exports selected functions from the hello smoke-test and the
// SpotiFLAC go_backend so that both packages are compiled into a single
// AAR (avoiding duplicate go.Seq / libgojni.so conflicts).
package bridge

import (
	"github.com/zarz/spotiflac_android/go_backend"
)

// Ping returns a fixed string to prove the gomobile bridge works.
func Ping() string {
	return "pong"
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

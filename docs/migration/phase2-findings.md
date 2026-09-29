# Rust engine migration — phase 2 findings (2026-09-29)

Branch: `feat/rust-engine-phase2`. Device evidence below was recorded by the controller in the phase-2 SDD ledger; this document does not claim a new device run. The per-method mapping is reconstructed from `NativeEngine.kt`, `GoEngine.kt`, `RustEngine.kt`, `RustCore.kt`, and `UniffiRustCore.kt`.

## Device and profile

- LG V30 (US998), Android 9, kernel 4.4, sdcardfs. Populated Go-era profile: nine installed extensions, including Qobuz and Amazon. Phase 1 established the upgrade retained the encrypted extension data.
- A/B used the same captured/restored profile. Run 1 had no FLAC in the default music directory. Run 2 seeded FLAC and Opus files. The comparison covers 13 calls; it compares JSON shape, except audio-quality values were also checked manually.

## A/B parity

| Step | Run 1 | Run 2 | Evidence / limit |
| --- | --- | --- | --- |
| `getInstalledExtensions` | same | same | Nine extensions loaded. |
| `getDownloadPriority` | same | same | Shape parity. |
| `getMetadataPriority` | same | same | Shape parity. |
| `getExtensionSettings` | same | same | Shape parity. |
| `getExtensionPendingAuth` | same | same | Shape parity. |
| `findUrlHandler` | same | same | Shape parity. |
| `handleUrl` | same | same | Shape parity. |
| `searchTracks` | same | same | Search returned nonempty results on both engines. |
| `getLyricsLRC` | same | same | Shape parity. |
| `checkDuplicate` | same | same | Shape parity. |
| `scanLibraryFolder` | same | same | Values also identical in run 2. |
| `getAudioQuality` | both_error | differs | Run 1: no FLAC in default directory. Run 2: Go and Rust values equal for 24-bit, 96 kHz, 195 s, FLAC; Rust alone adds `bitrate`. |
| `getAllDownloadProgress` | same | same | Shape parity. |

Run 1 summary: 12 same, 0 differs, 1 both_error. Run 2: 12 same, 1 differs, 0 errors. The Rust-only `bitrate` is additive; the compared Go-era quality values match. The A/B harness is a shape comparison, so value equality outside the explicitly checked audio-quality and library-scan results is not established by its `same` status.

## Rust-mode end-to-end smoke

| Check | Result | Device evidence / limit |
| --- | --- | --- |
| Engine selection | PASS | Log showed `engine=RUST`; phase-2 exit changes the debug default to Rust. Release remains Go until phase 5. `files/engine_go` and `files/engine_rust` override debug selection per device; Go flag wins if both exist. |
| Extensions, home feed, search | PASS | Nine extensions loaded; home feed and search returned results. |
| Zarz verification and session grant | PASS | Verification browser auto-opened; deep link completed the grant. Rust consumed the nonce itself; the app's best-effort consume logged `already used`. No grant or state value is reproduced here. |
| Qobuz FLAC | PASS | Download completed with tags and a 1000 px cover. |
| Amazon FLAC | PASS | File header was `fLaC`; `flac -t` passed; encrypted source was decrypted once. |
| Download progress | PASS | Progress bar advanced. |
| Cancel and retry | PASS | Cancel returned in-band `download cancelled`; the same item downloaded on retry. |
| Duplicate download | PASS | Re-download was skipped. |
| Library scan | PASS | 51 files listed. |
| Lyrics | PASS | Lyrics displayed. |
| Deep-link activity re-creation | PASS | No `already_initialized` error. |
| FFmpeg pump on device | NOT VERIFIED | Neither Amazon Opus nor E-AC-3 was delivered as a pumped format; Rust returned FLAC. No FFmpeg-command execution evidence exists. |
| DLNA | NOT VERIFIED IN RUST | DLNA remains on Go in phase 2. |

The ledger does not establish separate outcomes for notification progress, custom download directory, spectral/preview playback, tag editing, re-enrichment, extension installation, replay rejection, or rotation. These are not counted as passed here.

## Bugs found and fixed during the device gate

1. Amazon Opus 320 initially failed on Rust with `resolve album folder: Invalid argument (os error 22)`. The vendored `files.rs` `publish_new` path used `renameat2(RENAME_NOREPLACE)`, unsupported by this device's sdcardfs. `LM-FORK publish-noreplace-fallback` supplies the fallback. The exact item (`12 Mix`) then completed on Rust and produced a 61.8 MB FLAC that passed `flac -t`; Amazon supplied FLAC on retest, so Opus delivery itself remains unproven. The renamed-extension publication path on sdcardfs was exercised.
2. The Dart featured-artist regex truncated `Daft Punk` to folder `Da/`. The regex fix restored `Daft Punk/` on device. Existing downloads in `Da/` are not moved automatically. New Dart cases for `A [feat. B]` and `A (with B)` pass on the host without another production change.

Amazon lossy/spatial delivery was inconsistent outside the engine: Go Opus attempts returned Zarz HTTP 502 / `Download API failed for ASIN`; Rust Opus and E-AC-3 requests returned FLAC. This does not establish a Rust-specific quality regression or pump success.

## NativeEngine legacy-to-Rust mapping

Each row represents one `NativeEngine` method. `RustCore` names below map to UniFFI `ExtensionManager` or `ExtensionEnvironment` through `UniffiRustCore`. JSON strings remain the Android channel boundary unless noted.

| NativeEngine method | Go `Bridge` call | Rust `RustCore` / UniFFI call | Adaptation or behaviour |
| --- | --- | --- | --- |
| `setAppVersion` | `setAppVersion` | Factory `withLyricsSettings` | Rust ignores call; factory uses pinned `EngineVersion`. |
| `setExtensionStorageMasterKey` | `setExtensionStorageMasterKey` | Factory `withLyricsSettings` | Records key for one-time init. |
| `initExtensionSystem` | `initExtensionSystem` | Factory `withLyricsSettings` | Copies Go extension data to isolated Rust dirs; READY gate. |
| `loadExtensionsFromDir` | `loadExtensionsFromDir` | `loadAll` → `manager.loadAll` | Checks source dir; reapplies buffered priorities/fallback. |
| `loadExtensionFromPath` | `loadExtensionFromPath` | `install` → `manager.install` | Direct result. |
| `getInstalledExtensions` | `getInstalledExtensions` | `installed` → `manager.installed` | Direct JSON. |
| `setExtensionEnabled` | `setExtensionEnabledByID` | `setEnabled` → `manager.setEnabled` | Direct. |
| `removeExtension` | `removeExtensionByID` | `remove` → `manager.remove` | Direct. |
| `getExtensionSettings` | `getExtensionSettingsJSON` | `settings` → `environment.settings` | Direct JSON. |
| `setExtensionSettings` | `setExtensionSettingsJSON` | `updateSettings` → `manager.updateSettings` | Direct. |
| `getExtensionPendingAuth` | `getExtensionPendingAuthJSON` | `pendingAuthJson` → `manager.getExtensionPendingAuthJson` | Direct JSON. |
| `getExtensionHomeFeed` | `getExtensionHomeFeedJSON` | `homeFeedJson` → `manager.getExtensionHomeFeedJson` | Uses request lease. |
| `customSearchWithExtension` | `customSearchWithExtensionJSON` | `customSearchJson` → `manager.customSearchJson` | Uses request lease. |
| `completeSessionGrant` | `consumeExtensionCallbackState` + `setExtensionSessionGrantByID` + `invokeExtensionActionJSON` | `resolveCallbackState` + `setSessionGrant` + `invokeAction` + `consumeCallbackState` | Rust peeks nonce first, invokes checked `completeGrant`, then best-effort consumes; wraps failures with extension id. |
| `searchTracks` | `searchTracksWithMetadataProvidersJSON` | `searchMetadataProviders` → `manager.searchMetadataProviders` | Passes empty cursor and timeout. |
| `handleUrl` | `handleURLWithExtensionJSON` | `handleUrlJson` → `manager.handleUrlJson` | Direct JSON. |
| `findUrlHandler` | `findURLHandlerJSON` | `findUrlHandler` → `manager.findUrlHandler` | Null/error becomes empty string. |
| `getProviderMetadata` | `getProviderMetadataJSON` | `getProviderMetadataJson` → `manager.getProviderMetadataJson` | Passes null optional argument. |
| `getDownloadPriority` | `getProviderPriorityJSON` | `providerPriorities` → `manager.providerPriorities` | Extracts `download` array; uses buffered value until ready. |
| `setDownloadPriority` | `setProviderPriorityJSON` | `setProviderPriority("download", ids)` → `manager.setProviderPriority` | Parses JSON IDs and buffers before init/load. |
| `getMetadataPriority` | `getMetadataProviderPriorityJSON` | `providerPriorities` → `manager.providerPriorities` | Extracts `metadata` array; uses buffered value until ready. |
| `setMetadataPriority` | `setMetadataProviderPriorityJSON` | `setProviderPriority("metadata", ids)` → `manager.setProviderPriority` | Parses JSON IDs and buffers before init/load. |
| `setDownloadFallbackProviderIds` | `setExtensionFallbackProviderIDsJSON` | `setFallbackProviders` → `manager.setFallbackProviders` | Parses JSON IDs or null; buffers before init/load. |
| `downloadByStrategy` | `downloadByStrategy` | `downloadWithPump` → `manager.downloadByStrategy` + `runPostProcessing` | Scoped output-dir grant; FFmpeg command pump; successful ISRC indexing; exceptions become in-band error JSON. |
| `getAllDownloadProgress` | `getAllDownloadProgress` | `allProgress` → `environment.downloadState().allProgress` | Unready/error returns `{\"items\":{}}`. |
| `cancelDownload` | `cancelDownload` | `cancelDownload` → `environment.downloadState().cancelDownload` | Returns silently when the engine is not READY; engine exceptions are logged and swallowed. |
| `setDownloadDirectory` | `setDownloadDirectory` | `setAllowedDownloadDirectories` → `environment.setAllowedDownloadDirectories` | Records canonical dir in allow-list. |
| `allowDownloadDir` | `allowDownloadDir` | `setAllowedDownloadDirectories` → `environment.setAllowedDownloadDirectories` | Same allow-list, but errors logged. |
| `checkDuplicate` | `checkDuplicate` | `checkIsrcExists` → `environment.checkIsrcExists` | Scoped grant; path becomes `{exists, filepath}`. |
| `getAudioQuality` | `getAudioQualityJSON` | `readAudioMetadata` → `manager.readAudioMetadata` | Scoped grant; camelCase to Go keys, `total_samples=0`; optional Rust `bitrate`. |
| `editFileMetadata` | `editFileMetadata` | `editFileMetadata` → `manager.editFileMetadata` | Canonical file path and scoped grant. |
| `reEnrichFile` | `reEnrichFile` | `reenrichFile` → `manager.reenrichFile` | Canonical path unless preview-only; scoped grant on the parent dir; empty path passed through unchanged. |
| `getLyricsLRC` | `getLyricsLRC` | `getLyricsLrc` → `manager.getLyricsLrc` | Builds `LyricsRequest`; grants nonblank file path. |
| `setLibraryCoverCacheDir` | `setLibraryCoverCacheDir` | `setLibraryCoverCacheDirectory` → `manager.setLibraryCoverCacheDirectory` | Blank ignored; keeps a cover-directory lease. |
| `scanLibraryFolder` | `scanLibraryFolderJSON` | `scanLibraryFolder` → `manager.scanLibraryFolder` | Scoped folder grant; JSON passed through. |

## Carry-over to phase 3

- Implement PostDownload fixes 1 and 4; implement or retire `signed-session-mint` under the success criterion, with test proof. Hoàng reviews both fork PR contents before the upstream PRs are sent (`signed-session-mint` and `publish-noreplace-fallback`). Include macOS `ENOTSUP` in the fallback PR review; ruling R11 did not add it to Android code.
- Obtain a deliverable pump-only format and verify FFmpeg-command execution on device. Investigate Amazon lossy/spatial quality selection and Go server errors separately.
- Note legacy `Da/` downloads in the changelog; the new folder rule does not migrate existing files. Revisit the broad `with` stripping rule, which can shorten a genuine artist name such as `Kids With Buns`.
- Retain the deferred phase-2 minor issues in the SDD ledger for prioritization; the device run did not close them.

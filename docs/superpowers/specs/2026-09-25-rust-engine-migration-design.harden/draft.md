# Rust Engine Migration (SpotiFLAC v5.0.0) — Design

**Date:** 2026-09-25
**Status:** Approved in conversation (all 6 design sections confirmed by Hoàng); pending written-spec review
**Goal:** Replace the vendored Go engine (`go_backend/`, SpotiFLAC v4.9.6) with upstream's
Rust engine (`rust_backend/`, SpotiFLAC v5.0.0, UniFFI) so we keep syncing upstream cheaply,
keep our own UI and features, and stay compatible with extensions that target v5+.

---

## 1. Background & decisions

Upstream v5.0.0 (tag commit `1e3414b3`, 2026-09-23) deleted `go_backend/` entirely (185 files)
and replaced it with a Rust Cargo workspace (`crates/{core,network,providers,extensions,mobile,bindgen}`)
built into a single `libspotiflac_mobile.so` with UniFFI Kotlin bindings (`com.spotiflac.backend`).
Migration commit `aa997264` (2026-09-14) removed Go for good; there are **no** Go commits between
v4.9.6 and it, so v4.9.6 is the final Go engine. Our `scripts/sync-upstream.sh` (Go-only
`INHERIT_PATHS`) cannot follow this move.

Decisions (with alternatives rejected), in order taken:

| # | Decision | Rejected alternatives |
|---|---|---|
| D1 | **Full migration to `rust_backend`** | Freeze on Go v4.9.6 + backports; freeze now/migrate later |
| D2 | **DLNA server ported to Kotlin** | Keep a Go-only AAR for DLNA (2 runtimes, keep gomobile); own Rust crate (edits upstream workspace/`Cargo.lock`, or a 2nd `.so` duplicating tokio/hyper and pinning uniffi) |
| D3 | **3-layer ownership model** (below) | Real GitHub fork of upstream with our app on top (0 shared `lib/` files → ~45 UI commits dragged per sync) |
| D4 | **Sync mechanism M1**: copied tree + baseline tag + 3-way diff | Git submodule (pulls whole upstream repo, needs fork/patch step for any LM-FORK); git subtree |
| D5 | **Our own Kotlin glue**; vendor only upstream's `CoreBackend.kt` | Vendor upstream `SelectedCoreBackend.kt` (extension fns on *their* `MainActivity`, their channel names, their 2k-line finalizer) |
| D6 | **Fixes 1 & 4 relocated to Kotlin glue**, not Dart (covers both download paths) | Dart post-download (misses `DownloadForegroundService`) |
| D7 | **Go and Rust coexist during phases 1–4** behind an `engine = go\|rust` flag | Hard cut-over in phase 2 |
| D8 | **Ktor server-cio** for the DLNA HTTP server | NanoHTTPD (unmaintained, manual Range); raw `ServerSocket` |

Independent reviews (Fable, Codex) both endorsed D3 + D4 and verified the fix-relocation claims
in code (see §5).

---

## 2. Architecture — 3 layers

```
┌──────────────────────────────────────────────┐
│ Layer 3 — OUR UI + FEATURES                  │  lib/ (Flutter), onboarding, spectral,
│ never synced; upstream reviewed per sync     │  l10n, DLNA (Kotlin), landing
├──────────────────────────────────────────────┤
│ Layer 2 — OUR KOTLIN GLUE                    │  EngineBridge over UniFFI; keeps channel
│ absorbs every engine API change              │  + method names → Dart unchanged
├──────────────────────────────────────────────┤
│ Layer 1 — UPSTREAM ENGINE (synced)           │  rust_backend/ + build_rust_backend.sh
│ byte-identical target, 1 temporary LM-FORK   │  + CoreBackend.kt
└──────────────────────────────────────────────┘
```

Repo layout after migration:

```
rust_backend/                                   L1 inherited (v5.0.0, byte-identical)
scripts/build_rust_backend.sh                   L1 inherited
android/app/src/main/kotlin/
  com/zarz/spotiflac/CoreBackend.kt             L1 inherited (FFmpeg-pump contract)
  xyz/losslessmusic/app/
    MainActivity.kt                             channel xyz.losslessmusic/native (method names unchanged)
    engine/Engine.kt                            thin interface over UniFFI objects (fakeable)
    engine/EngineBridge.kt                      NEW — the only caller of com.spotiflac.backend.*
    engine/EngineShims.kt                       NEW — NativeDownloadFinalizer.runFFmpegArguments shim
    engine/PostDownload.kt                      NEW — fix 1 (lyrics) + fix 4 (error reclassify)
    dlna/…                                      NEW — Kotlin port of native/server
    DownloadForegroundService.kt, Mp4FlacUnwrapper.kt, NonFlacMetadataEmbedder.kt  (call EngineBridge)
lib/                                            L3, effectively unchanged
✗ go_backend/, native/bridge/, native/server/, gobackend.aar   removed in phase 5
```

Boundary rules:
- Layer 1 is not edited, except the single temporary LM-FORK in
  `rust_backend/crates/extensions/src/signed_session/fetch.rs` (fix 3), which is also PR'd upstream.
- Only `EngineBridge` touches UniFFI types. An engine API change means editing `EngineBridge` only.
- The MethodChannel contract (method names + returned JSON shapes) is frozen. Rust differences
  (snake_case keys, cover-to-file, leases, request ids) are adapted inside `EngineBridge`.

Build:
- Our own Gradle `buildRustBackend` Exec task (copied from upstream, ~20 lines, not inherited)
  runs `scripts/build_rust_backend.sh android` before `preBuild`; adds
  `rust_backend/target/android/jniLibs` and the generated Kotlin bindings dir as sources;
  adds JNA 5.19.1 (aar); ProGuard keeps `com.spotiflac.backend.**`.
- ABI: **arm64-v8a only** (as today).
- Toolchain pinned: Rust 1.98.1 via `rust_backend/rust-toolchain.toml`, NDK 29.0.14206865,
  `cargo --locked`. Our AGP/Kotlin/Gradle/JDK stay unless JNA/uniffi force a bump (verified in phase 1).

---

## 3. Layer 2 — Kotlin glue

### 3.1 `EngineBridge`
Singleton; depends on an `Engine` interface (UniFFI classes are `final`, so tests use a fake).

The channel exposes **41 distinct `Bridge.*` methods** today, in exactly four groups
(21 + 14 + 2 + 4 = 41). The exhaustive per-method table (arguments, success shape, error shape,
state effects, cancellation) is a phase-2 plan deliverable, generated from the current channel
registrations and checked against this grouping.

- **Changed shape — group 1, init (3):** one `ExtensionManager.withLyricsSettings(srcDir, dataDir, masterKey, appVersion, …)`
  replaces `initExtensionSystem` + `setExtensionStorageMasterKey` + `setAppVersion`. Dart keeps
  calling all three in the existing order; Kotlin buffers the arguments and constructs once all
  are present. `appVersion = SPOTIFLAC_ENGINE_VERSION = "5.0.0"` — the upstream engine version the
  extension `minAppVersion` gate (`environment.rs:704`) checks; bumped on every sync (enforced, §6).
  **Init state machine** `UNINITIALIZED → INITIALIZING → READY | FAILED(reason)`:
  - **Init arguments are immutable per process.** Each init method records its value and
    returns success immediately; the **first complete set** (all three present) is frozen and
    construction runs once from it, serialized by a mutex (concurrent init calls queue). Dart
    sends the same three values once per process (dirs, master key from secure storage, version
    constant), so a changed value within one process is a caller bug, not a use case.
  - **Idempotency / conflicts (every state):** repeating an init method with the frozen (or
    already-recorded) value is a no-op. Any *different* value for an already-recorded argument is
    rejected with `error_type:"already_initialized"` and logged, in every state
    (`UNINITIALIZED`, `INITIALIZING`, `READY`, `FAILED`). A new process starts from
    `UNINITIALIZED` with nothing recorded.
  - **Pre-ready calls:** methods that need the manager wait on a readiness gate (bounded timeout,
    value set in the plan) and then run; on timeout or `FAILED` they return
    `{success:false, error_type:"engine_not_ready", error:<reason>}`. Methods that don't need the
    manager (which ones is pinned in the phase-2 table) run immediately.
  - **Constructor failure:** state `FAILED(reason)`, partially created UniFFI objects are closed,
    waiting calls get `engine_not_ready`. **Retry:** the next init call with the same values
    (e.g. Dart re-running extension init) moves `FAILED → INITIALIZING` and rebuilds from the same
    frozen set; recovering with different values requires an app restart.
- **1:1 (21):** rename + snake_case ↔ legacy JSON shape conversion — `downloadByStrategy`,
  `cancelDownload`, `getAllDownloadProgress`, `editFileMetadata`, `reEnrichFile`, `getLyricsLRC`,
  `scanLibraryFolderJSON`, `setLibraryCoverCacheDir`, `findURLHandlerJSON`,
  `handleURLWithExtensionJSON`, `getInstalledExtensions`, `loadExtensionFromPath`,
  `loadExtensionsFromDir`, `removeExtensionByID`, `setExtensionEnabledByID`,
  `getExtensionSettingsJSON`, `setExtensionSettingsJSON`, `invokeExtensionActionJSON`,
  `getExtensionPendingAuthJSON`, `searchTracksWithMetadataProvidersJSON`, `getProviderMetadataJSON`.
- **Changed shape — groups 2–6 (11):**
  - `customSearchWithExtension`, `getExtensionHomeFeed`: allocate `request_id` via
    `CancellationRegistry`, release lease in `finally`.
  - `get/setProviderPriorityJSON`, `get/setMetadataProviderPriorityJSON` → `setProviderPriority(kind)` / `providerPriorities()`.
  - `consumeExtensionCallbackState` + `setExtensionSessionGrantByID` → `completeAuthCallback(state, code, grant)`;
    nonce → extension-id resolution kept as fixed in v0.9.1.
  - `allowDownloadDir` → `grantDownloadDirectories` lease held for app lifetime;
    `setDownloadDirectory` → `setAllowedDownloadDirectories`.
  - `setExtensionFallbackProviderIDs` → `setDownloadFallbackExtensionIds`.
- **Bridge-local (4 methods):** `ping` (answered by `EngineBridge` itself) and
  `startMediaServer` / `stopMediaServer` / `getMediaServerStatus` (served by the Kotlin DLNA
  server, §4). `extractCoverArt` is not a channel method; the DLNA metadata provider uses
  `extractCoverToFile` directly (§4).
- **Removed upstream (2 methods):**
  - `checkDuplicate` → `check_isrc_exists(dir, isrc)` (`crates/mobile/src/index.rs:26`).
  - `getAudioQuality` → `readAudioMetadata(path)` `bitDepth`/`sampleRate`; if absent in real
    output (checked in phase 2), fall back to ffprobe via ffmpeg-kit.
- **Errors:** every UniFFI exception is caught in `EngineBridge` and returned as
  `{success:false, error, error_type}` exactly as Dart parses today. Nothing throws across the channel.

### 3.2 FFmpeg pump
The Rust engine hands FFmpeg commands back to Kotlin. We vendor `CoreBackend.kt` unchanged
(`withCoreFFmpegExecution`, `executeCoreFFmpegCommand`). Its only external dependency is
`NativeDownloadFinalizer.runFFmpegArguments` (line 102). `engine/EngineShims.kt` declares
`internal object NativeDownloadFinalizer` in package `com.zarz.spotiflac` with extension
`runFFmpegArguments(arguments, shouldCancel, trackFinalizerSession): Pair<Boolean, String>`,
implemented with our `com.antonkarpenko:ffmpeg-kit-full` (currently 2.1.0; upstream 2.2.1 —
bump only if required), polling `shouldCancel` to cancel the session.

Every `downloadByStrategy` / `postProcess` call runs inside `withCoreFFmpegExecution`;
`EngineBridge.download()` wraps it so no path can call the engine without the pump.

### 3.3 Single download path
Both download paths — Dart queue (via `MainActivity`) and `DownloadForegroundService.kt:311` —
call the same function:

```
EngineBridge.download(req)
  └─ withCoreFFmpegExecution { mgr.downloadByStrategy(req) }
       └─ PostDownload.apply(result, req)   // fix 1 + fix 4
            └─ legacy-shaped JSON back to Dart / FGService
```

`Mp4FlacUnwrapper` / `NonFlacMetadataEmbedder` keep their logic; phase 2 checks whether the v5
engine already performs that work through the pump and removes any double-processing.

### 3.4 Coexistence flag
`engine = go | rust` is **process-scoped**: read once at process start (debug-only setting,
default `go` until phase 2 exits), applied to every channel method for that process's lifetime.
Changing it takes effect only after an app restart; nothing (init, leases, request ids,
cancellation, pending auth, downloads) ever crosses engines within one process. A/B runs are
therefore two separate process runs over the same inputs. Removed in phase 5.

**Data isolation during coexistence:** the Rust engine never writes the Go engine's data dirs
before cutover. On the first `engine=rust` start, `EngineBridge` copies the Go-era engine data
(extensions dir + extension data/storage dir) into an engine-specific `engine-rust/` dir and
points the Rust engine there; later Rust starts reuse that copy (for day-to-day development). The Go dirs stay canonical and
untouched, so `engine=go` runs and the rollback path remain valid throughout phases 1–4.
**Cutover (one-way) happens in phase 5:** the shipped Rust-only build uses the original dirs
in place (the §3.5 upgrade path), and the `engine-rust/` copy is deleted on first launch.

### 3.5 Persisted data across the engine switch
Engine-private state lives under the app's extension/data dirs: installed extensions, encrypted
extension storage (credentials, session grants), extension settings, provider priorities.
- **Upgrade (Go → Rust):** we rely on upstream's own in-place upgrade path — their users moved
  from v4.9.x Go to v5.0.0 Rust on the same on-disk data (e.g. `storage.rs:258` decrypts the
  legacy credentials key). Phase 1 verifies this on a **populated v0.9.1 profile** (via the `engine-rust/` copy, §3.4; re-checked in place on the release build in phase 6) (extensions
  installed, signed-in Qobuz/Amazon sessions, custom priorities): after upgrading to the Rust
  build, all extensions load, sessions still work or cleanly request re-verification, settings
  are preserved. If any item fails, `EngineBridge` performs a one-time migration for that item
  (designed in phase 1) before first use; unrecoverable items fall back to "reinstall/re-sign-in"
  with a user-visible message, never a crash or silent loss.
- **Rollback (Rust → Go):** engine-private state written by Rust is **not guaranteed readable**
  by the Go build. Rollback accepts that extensions may need reinstall and sessions re-sign-in.
  User files (downloads, library, `.lrc`) and app-level Dart settings are never touched by the
  engine switch in either direction. This is stated in the rollback notes.
- The populated-profile upgrade test is part of the E2E gate (§8).

---

## 4. Layer 3 — DLNA server in Kotlin

Port of `native/server` (~1,450 lines code + ~1,430 lines tests) into
`xyz.losslessmusic.app.dlna`, file-for-file:

| Go | Kotlin | Notes |
|---|---|---|
| `ssdp.go`, `ssdp_mcast_*.go` | `Ssdp.kt` | `MulticastSocket` 239.255.255.250:1900; NOTIFY alive/byebye; M-SEARCH replies; bound to the LAN IP passed in (never enumerate interfaces — Android 11+ restriction) |
| `device.go` | `DeviceDescription.kt` | Device XML; **UDN uses the exact `StableUDN` algorithm** so renderers keep recognising the server |
| `contentdirectory.go`, `didl.go` | `ContentDirectory.kt`, `Didl.kt` | SOAP Browse parse, ObjectID encode/decode, **path-traversal rejection**, XML escaping |
| `server.go` | `MediaServer.kt` | Ktor server-cio; routes `/description.xml`, `/cd/scpd`, `/cd/control`, `/media/`, `/art/`; PartialContent (Range/206), AutoHeadResponse, keep-alive |
| `metadata.go` | `TrackTagsProvider.kt` | Tags via `EngineBridge.readAudioMetadata`; cover via `extractCoverToFile` with cache |
| `lan.go` | — | Kotlin already resolves LAN IP via `ConnectivityManager` |

Channel methods unchanged (`startMediaServer`, `stopMediaServer`, `getMediaServerStatus`).

**Lifecycle (explicit state machine)** — `STOPPED → STARTING → RUNNING → STOPPING → STOPPED`,
plus `FAILED(reason)`:
- **Owner:** a process-level singleton (same scope as today's Go server). The server lives as
  long as the process; no foreground service. Background casting after the process is killed is
  out of scope (unchanged from today).
- **start:** idempotent — `RUNNING`/`STARTING` returns current status. Acquires `MulticastLock`,
  binds HTTP, then starts SSDP. If any step fails, everything already acquired is released in
  reverse order and state becomes `FAILED(reason)`; a later `start` retries from scratch.
- **start while `STOPPING`:** waits for `STOPPED`, then starts normally.
- **stop while `FAILED`:** no-op cleanup (already released), normalizes state to `STOPPED`.
- **stop:** idempotent; sends SSDP byebye (best effort), stops SSDP, stops Ktor, releases
  `MulticastLock`, → `STOPPED`. `stop` while `STARTING` cancels startup and cleans up.
- **Runtime failure** (Ktor or SSDP coroutine dies): full cleanup as in stop, → `FAILED(reason)`.
- **Network change:** if the bound LAN IP disappears or changes (existing `ConnectivityManager`
  callback), the server stops and reports `FAILED(network_changed)`; the user restarts it from
  the UI (no auto-restart — matches today's behaviour and avoids announcing on the wrong network).
- **Status:** `getMediaServerStatus` returns `{running, url, name}` as today, plus `state` and
  `error` fields (additive; existing Dart parsing ignores unknown keys).

---

## 5. Our fixes (replacing the 4 Go LM-FORKs)

### Fix 1 — lyrics fallback (was `embed_after_download.go`) → `PostDownload`
On successful download, for embeddable files (FLAC; MP4/Opus as `embed_lyrics_to_file` supports),
when the "embed lyrics" setting is on:
1. Skip if the file already has a `LYRICS` tag (engine embedded extension-supplied `lyrics_lrc`,
   `backend/downloads.rs:1229`).
2. Else lyrics = result `lyrics_lrc`, else `getLyricsLrc(LyricsRequest{title, artist, album, duration, isrc})`.
3. Drop the `[instrumental:true]` sentinel.
4. `embed_lyrics_to_file(path, lrc)` (`crates/mobile/src/lyrics.rs:40`).
Failures are logged, never fail the download. Dart `.lrc` sidecar logic unchanged.

### Fix 4 — preflight error type (was `exports_extensions.go`) → `PostDownload`
v5 returns `failure(provider, "Could not start verification for X: err", "", 0)`
(`backend/downloads.rs:190-196`); `failure()` (`:1737`) derives `error_type` by keyword
(`download/mod.rs:37-52`), usually `network`/`unknown`. If `message` starts with
`"Could not start verification for"`, set `error_type = "verification_required"` so
`extension_auth_launcher.dart` reopens verification. A Kotlin unit test pins the exact upstream
string; if upstream rewords it, the test fails during sync verify.

### Fix 3 — signed-session `needsVerification` → the only Rust LM-FORK
`rust_backend/crates/extensions/src/signed_session/fetch.rs`, the `self.bootstrap(&check)?` sites
(~lines 33, 42, 62): map a bootstrap `Err` to `Ok(self.verification_required(String::new()))`
(`coordinator.rs:237`), matching the Go fix. Each site wrapped in
`// LM-FORK(signed-session-mint): <why>` … `// END LM-FORK`; no reformatting. Test in a **new file**
`crates/extensions/tests/lm_signed_session_mint_failure.rs` (or `#[cfg(test)]` inside the LM-FORK
block if the needed API is private). A PR with the fix + test goes to
`spotiflacapp/SpotiFLAC-Mobile` — **content reviewed by Hoàng before sending** (outward action).
Retire the LM-FORK when upstream merges.

### Fix 2 — `extension_fallback.go` call-site
No longer applicable (no hook point in Rust; fix 1 lives in Kotlin).

### Registry (`docs/UPSTREAM-SYNC.md`)
- 4 Go rows → "Retired (engine migrated to Rust)", each pointing at its new home.
- New row: `fetch.rs` LM-FORK (3 sites) + PR link.
- New row: `EngineShims.kt` shim (ours) depending on the inherited `CoreBackend.kt` contract.

---

## 6. Sync tooling, contract, Go removal, rollback

**`scripts/sync-upstream.sh`:**
- `INHERIT_PATHS=(rust_backend scripts/build_rust_backend.sh android/app/src/main/kotlin/com/zarz/spotiflac/CoreBackend.kt)`.
- **Watch list** (not inherited, reported as diff-stat so glue changes get hand-ported):
  `android/app/src/rust/kotlin/**/SelectedCoreBackend.kt`, `android/**/NativeFinalizer*.kt`,
  `NativeDownloadFinalizer.kt`, the Rust task in `android/app/build.gradle.kts`,
  `lib/services/platform_bridge.dart`.
- Verify after `--apply`: `cargo build --locked -p spotiflac-mobile`; `cargo test -p spotiflac-extensions`;
  generate Kotlin bindings; `./gradlew assembleDebug` + Kotlin unit tests;
  **fail if `SPOTIFLAC_ENGINE_VERSION` ≠ target tag version**.
- `vendor/spotiflac-base` moves to `1e3414b3` (v5.0.0) in phase 1; `go_backend/` is frozen from then.
- **LM-FORK survival (same 3-way model as today):** the script builds the upstream patch
  `base..target` for `INHERIT_PATHS` and applies it with `git apply --3way` onto our working tree,
  so local LM-FORK hunks are the "ours" side and are never overwritten silently:
  - upstream didn't touch the hunk → our edit survives untouched;
  - upstream edited nearby → conflict markers; resolve keeping our intent, or take upstream's if
    it now contains the fix;
  - **guard before advancing the baseline:** every LM-FORK block carries a logical fork id
    (`// LM-FORK(<id>): <why>`; fix 3 = `signed-session-mint`, used by all 3 sites). Verify fails
    unless the set of **unique ids** found in `rust_backend/` equals the set of active Rust rows in
    the registry (one row per id), and the LM-FORK test (`lm_signed_session_mint_failure.rs`) passes.
- **Retirement:** when upstream merges the fix, the sync takes upstream's version of those
  hunks, the registry row moves to "Retired", and the LM-FORK test is kept only if upstream's
  own test doesn't cover the case. The id-set guard then expects the empty set.

**Contract snapshot:** replace `snapshot-bridge-contract.sh` with `snapshot-engine-contract.sh` —
collect UniFFI functions called by `EngineBridge.kt`, extract matching `pub fn` signatures from
`rust_backend/crates/mobile/src/*.rs` into `docs/engine-contract.txt`; `--check` diffs. Kotlin
compilation remains the authoritative net. Add a **required-call-order checklist** (constructor
arguments + init order) to `UPSTREAM-SYNC.md`.

**Go removal (phase 5, only after the end-of-phase-4 E2E run passes, §8):** delete `go_backend/`, `native/bridge/`,
`native/server/`, gomobile steps in `scripts/build_android.sh`, `gobackend.aar`, the engine flag,
`.gomobile` ignores, Go-only fixtures (`android/app/src/test/resources/lyrics_usability_cases.tsv`
if nothing else reads it). Update `integration_test/extension_engine_test.dart` (asserts Go
behaviour); replace `native/bridge/bridge_appversion_test.go` with a Kotlin test. Update
`docs/UPSTREAM-SYNC.md`, `CLAUDE.md` "Upstream Inheritance Protocol" (`go_backend` → `rust_backend`),
and the extension-gate memory.

**Rollback:** before Go removal, create branch **`release/0.9.x-go`** from the v0.9.1 release
commit (`bee1943e`) and keep it buildable for **one release cycle**, for hotfix APKs if the Rust
engine has a critical issue.

**Build prerequisites** (no CI; local builds): document in `docs/`: `rustup` (auto-reads
`rust-toolchain.toml`), target `aarch64-linux-android`, NDK 29.0.14206865, `--locked`.

---

## 7. Phases

Each phase on its own branch, ends with build + tests green.

1. **Vendor & build:** copy `rust_backend/`, `scripts/build_rust_backend.sh`, `CoreBackend.kt` at
   v5.0.0; add Gradle task, JNA, ProGuard; produce `.so` + bindings; Go still active. Move baseline tag;
   switch sync script paths. Check JDK/AGP/ffmpeg-kit needs. Verify persisted-data upgrade on a
   populated v0.9.1 profile (§3.5); design any one-time migration it reveals.
2. **Glue:** `Engine`, `EngineBridge`, `EngineShims`, flag; migrate all 41 distinct `Bridge.*` methods incl.
   FFmpeg pump and both download paths; A/B parity test.
3. **Fixes:** `PostDownload` (fix 1, fix 4); Rust LM-FORK fix 3 + test; draft upstream PR (review before send).
4. **DLNA:** Kotlin port + tests + real-TV cast. **Exit gate:** full E2E matrix on the
   coexistence build with `engine=rust`, evidence committed (§8).
5. **Remove Go & retool:** rollback branch; delete Go; contract snapshot; docs/CLAUDE.md/memory.
6. **Verify & release:** re-run the full E2E matrix on the Rust-only release candidate
   (+ in-place upgrade of a populated v0.9.1 profile), metrics, v0.10.0 release.

---

## 8. Testing

| Layer | Tests |
|---|---|
| Rust | `lm_signed_session_mint_failure.rs` (run by sync verify) |
| Kotlin glue | JUnit with fake `Engine`: name mapping, JSON conversion, all 14 changed-shape methods via their 6 group scenarios (init state machine incl. pre-ready/duplicate/failure/retry; search+feed request-id leases; 4 priority methods; auth callback; download-dir lease; fallback ids) + 2 replaced functions, exception → error JSON; `PostDownload` (lyrics present/absent, instrumental sentinel, verification reclassify); FFmpeg shim cancel; `SPOTIFLAC_ENGINE_VERSION` |
| DLNA | JUnit ports of Go tests; Range test against a local Ktor server; `StableUDN` golden values from Go |
| Dart | Existing 430+ tests pass **without modification** (proves the channel contract held) |

**A/B parity (phases 2–4):** debug-build integration test calls the same method set through
`engine=go` and `engine=rust` and compares JSON **shape** (key sets, types), not values.
**Deterministic reset:** a populated profile is captured once as an immutable fixture snapshot.
Before each paired run, a debug-only reset restores **both** the Go dirs and `engine-rust/` from
that snapshot, so both engines start from identical state; the Go run and the Rust run are then
executed as separate processes.

**E2E matrix on device** — run and recorded **twice**: (1) at the end of phase 4 on the
coexistence build with `engine=rust` (the gate for Go removal in phase 5), and (2) again in
phase 6 on the Rust-only release candidate (the gate for release). Both runs commit their
evidence checklist.
- Sources: Qobuz, Tidal, Amazon, Deezer, YT Music (Deezer on emulator/other network — LG V30 DNS blocks it).
- Formats: FLAC 16/24-bit, Amazon encrypted FLAC-in-MP4, Opus/MP4 (pump path).
- Flows: search/album/playlist; Dart queue + foreground service; cancel; duplicate check; lyrics
  embed + `.lrc`; expired session → verification browser reopens (fixes 3 & 4); extension
  install/update (`minAppVersion` gate); library scan; spectral; preview; DLNA cast to a real TV.

- Upgrade: populated v0.9.1 profile → Rust build (§3.5).

**Required coverage (not the full cross-product):** every source with FLAC; every format on at
least one source that produces it; every flow at least once; the verification-reopen flow on
both Qobuz and Amazon (shared Zarz gateway). Each case records pass/fail + evidence (screenshot
or log excerpt) in a checklist file committed with the phase-6 work. A case passes when the
file lands in the output dir with correct tags/cover/lyrics (or the flow's visible outcome
occurs) and no error toast appears.

**Metrics vs v0.9.1:** arm64 APK size is a **gate** (report actual; if > +20%, stop for
decision). Cold start and RAM during download are **informational** (measured the same way on
both builds, reported in the release notes, no threshold).

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Rust port is ~3 weeks old | Coexistence flag + A/B; rollback branch for one cycle |
| FFmpeg pump not driven → non-FLAC post-processing hangs | `EngineBridge.download()` always wraps `withCoreFFmpegExecution`; E2E Amazon/Opus |
| `minAppVersion` gate rejects extensions | `SPOTIFLAC_ENGINE_VERSION` constant + sync-verify check + test |
| Required-order init regression (cf. v4.9.5 master key) | Buffered init in `EngineBridge`; order checklist in docs |
| Text-coupled fix 4 | Pinned-string unit test |
| Toolchain drift / non-reproducible builds | `rust-toolchain.toml`, `--locked`, pinned NDK; prerequisites doc |
| Removed APIs (`CheckDuplicatesBatch`, `GetAudioQuality`) | Replacements in §3.1, verified in phase 2 |
| APK size growth | Measured in phase 6; decision gate at +20% |
| DLNA renderer quirks after rewrite | Ktor PartialContent/HEAD; stable UDN; real-TV E2E before Go removal |

---

## 10. Success criteria

1. APK ships only the Rust engine; no Go code or runtime.
2. 430+ Dart tests pass unmodified.
3. E2E matrix passes on device.
4. `scripts/sync-upstream.sh v5.0.0` on the migrated tree reports no changes and verify passes.
5. Either (a) the registry lists exactly one active Rust LM-FORK id (`signed-session-mint`) and
   its upstream PR has been sent (after review), or (b) zero active Rust LM-FORK ids because the
   synced upstream target already contains the fix, verified by either the retained LM-FORK test
   passing on unmodified upstream code, or an identified upstream test that covers the same
   failure case (named in the registry's retired row).

## Deferred to plan
- Readiness-gate timeout value and the list of manager-independent methods (§3.1).
- Exhaustive 41-method legacy→Rust table (args, success/error shape, state effects, cancellation) — phase-2 plan, from the grouping in §3.1.

## Out of scope
Upstream Mornye UI/player/AutoMix/profiles; porting upstream `lib/` features (tracked separately
from the v5 app-review list); armeabi-v7a; iOS; commits on upstream `main` after v5.0.0
(next sync).

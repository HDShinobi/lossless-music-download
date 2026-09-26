# Rust Engine Migration — Phase 2 (EngineBridge) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put every native engine call behind one `NativeEngine` interface with two implementations — `GoEngine` (today's behaviour, unchanged) and `RustEngine` (the vendored SpotiFLAC v5.0.0 Rust engine via UniFFI) — selectable per process, with a device A/B harness proving the Rust path returns the same JSON shapes as Go.

**Architecture:** `MainActivity`, `DownloadForegroundService`, `Mp4FlacUnwrapper` and `NonFlacMetadataEmbedder` stop calling `Bridge.*` and call `Engines.current` instead. `GoEngine` delegates 1:1 to the gomobile `Bridge`. `RustEngine` adapts the Go-era contract onto a thin `RustCore` interface (fakeable in JVM tests) whose real implementation `UniffiRustCore` wraps the UniFFI objects and runs downloads through the vendored `withCoreFFmpegExecution` FFmpeg pump. Dart and the MethodChannel contract do not change.

**Tech Stack:** Kotlin (Android, JVM unit tests with JUnit 4 + org.json, host Rust dylib via JNA), UniFFI bindings `com.spotiflac.backend`, gomobile AAR `xyz.losslessmusic.backend.bridge.Bridge`, bash + adb.

**Spec:** `docs/superpowers/specs/2026-09-25-rust-engine-migration-design.md` (§3.1, §3.2, §3.3, §3.4, §3.5, §8). Research inputs this plan was derived from: the Go contract (every method's args, return JSON, Dart keys read, error behaviour) and the Rust UniFFI mapping — summarised inline where needed.

## Rulings made while planning (spec text vs. reality)

- **R-P1 Error behaviour follows the real Go contract, not the spec's wording.** Spec §3.1 says UniFFI exceptions are "returned as `{success:false,…}` … nothing throws across the channel". Today a Go error becomes a thrown Kotlin exception → `result.error("BACKEND_ERROR", message)` → Dart `PlatformException`, and only `downloadByStrategy` reports failures in-band. `RustEngine` therefore **throws where Go throws** and returns defaults where Go cannot fail (`getAllDownloadProgress`, `cancelDownload`, `allowDownloadDir`, `findUrlHandler`, `setLibraryCoverCacheDir`, `setAppVersion`). The spec's intent ("exactly as Dart parses today") wins over its literal text.
- **R-P2 Session-grant on Rust follows upstream's Rust flow**: `resolveCallbackState` (peek) → `setSessionGrant` → `invokeAction("completeGrant")` → require `success:true`. The Go path keeps today's consume-then-grant flow unchanged. Rationale: this is how the engine we vendor completes a grant; consuming the nonce first may break the engine's own completion.
- **R-P3 `allowDownloadDir` / `setDownloadDirectory` feed one permanent allow-list** re-applied with `setAllowedDownloadDirectories` (upstream's pattern), instead of spec §3.1's "lease held for app lifetime" — same effect, no leaked handle. Scoped `grantDownloadDirectories` leases are used per operation (download, scan, tag edit, audio probe) and for the library cover cache.
- **R-P4 Pre-init configuration is buffered, not gated.** `main()` calls `setDownloadFallbackProviderIds`, `setDownloadDirectory`, `allowDownloadDir` before extension init; priorities/cover-cache setters can also precede it. These are recorded and applied at construction (and immediately once READY). Only calls that need the manager wait on the readiness gate (15 s). Progress polling never waits.
- **R-P5 Readiness-gate timeout = 15 000 ms; `engine_not_ready: <reason>` is the thrown message** (spec deferred both to the plan).
- **R-P6 Engine selection mechanism:** debug builds read flag files in `filesDir` once per process (`engine_go` wins over `engine_rust`, else the debug default); **release builds are always Go** until phase 5. Phase-2 exit (Task 6) flips the debug default to Rust.

## Global Constraints

- Work on branch `feat/rust-engine-phase2` created from `main` (`14dd4389`). Never checkout/switch to `main`, never merge, never push. Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Layer 1 is byte-identical to upstream v5.0.0 and must stay so: `rust_backend/`, `scripts/build_rust_backend.sh`, `android/app/src/main/kotlin/com/zarz/spotiflac/CoreBackend.kt`. `scripts/sync-upstream.sh --check-vendored` must pass at the end of every task.
- **Never run `grep -r`/`find` over `rust_backend/`** (4.3 GB build output under `target/`). Use `git grep`.
- The MethodChannel contract (method names, argument keys, returned JSON shapes) is frozen; `lib/` is not modified; the 430 Dart tests pass unmodified.
- The Go engine remains the default in phase 2 until Task 6 flips the **debug** default; release builds always use Go.
- `SPOTIFLAC_ENGINE_VERSION = "5.0.0"` (`EngineVersion.kt`) is what the Rust engine receives as `app_version`.
- The Rust engine only ever uses the `engine-rust/` copy of the Go data dirs (`EngineDataIsolation.ensureRustCopy`); it never writes `<filesDir>/extensions` or `<filesDir>/ext_data`.
- Classes used by JVM unit tests must not touch `android.*` APIs (no `android.util.Log`, no `Context`) — inject loggers as `(String) -> Unit`.
- Gradle: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`; run from `android/` as `./gradlew …`. `:app:buildRustBackend` should be `UP-TO-DATE`; if it starts a full Rust rebuild without Rust inputs having changed, stop and report.

## Review Focus

1. **Progress polling before init** (EventChannel starts polling every 300 ms before extensions are initialised) → `getAllDownloadProgress` returns `{"items":{}}` immediately, never blocks. Pinned in Task 4 (`progressBeforeInitReturnsEmptyWithoutWaiting`).
2. **`main()` setters before init** (`setDownloadFallbackProviderIds`, `setDownloadDirectory`, `allowDownloadDir`) → return at once, and are applied to the engine at construction. Pinned in Task 4 (`preInitConfigIsBufferedAndAppliedAtConstruction`).
3. **Release build with an `engine_rust` flag file present** → still Go. Pinned in Task 1 (`releaseBuildAlwaysUsesGo`).
4. **Session-grant deep link with an unknown/expired nonce, or an extension whose `completeGrant` fails** → reported as failure (no crash); success requires `completeGrant` to return `success:true`. Pinned in Task 4 (`sessionGrant*` tests).
5. **Directory leases on every exit path** (success, in-band failure, thrown exception) → always released. Pinned in Task 4 (`grantScopesAreReleasedOnEveryPath`).

---

## File Structure

| Path | Kind | Responsibility |
|---|---|---|
| `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/NativeEngine.kt` | Create | The engine contract (Go-era method semantics) + `EngineKind` + `SessionGrantFailure` |
| `.../engine/GoEngine.kt` | Create | 1:1 delegation to gomobile `Bridge` |
| `.../engine/Engines.kt` | Create | `EngineSelection` (pure) + `Engines` process-scoped holder |
| `.../engine/RustCore.kt` | Create | Thin interface over the UniFFI objects + `RustCoreFactory` |
| `.../engine/UniffiRustCore.kt` | Create | Real `RustCore` over `com.spotiflac.backend.*`, FFmpeg pump for downloads |
| `.../engine/RustJson.kt` | Create | Pure JSON adapters (priorities, ids, duplicate, audio quality) |
| `.../engine/RustEngine.kt` | Create | `NativeEngine` on Rust: init state machine, config buffer, dir allow-list, leases, method mapping |
| `.../engine/ab/JsonShape.kt` | Create | Shape extraction + diff for A/B |
| `.../engine/ab/AbHarness.kt` | Create | Debug-only fixture capture/restore, record script, compare |
| `.../app/MainActivity.kt` | Modify | Use `Engines.current`; init engine early; A/B hooks; probe only on Go |
| `.../app/DownloadForegroundService.kt` | Modify | Use `Engines.current` |
| `.../app/Mp4FlacUnwrapper.kt`, `.../app/NonFlacMetadataEmbedder.kt` | Modify | Use `Engines.current` |
| `scripts/ab-parity.sh` | Create | adb orchestration of the A/B run |
| `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/…Test.kt` | Create | JVM tests |
| `docs/migration/phase2-findings.md` | Create | Device A/B + E2E results |

---

### Task 1: `NativeEngine` contract, `GoEngine`, engine selection, rewire call sites

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/NativeEngine.kt`, `GoEngine.kt`, `Engines.kt`
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/MainActivity.kt`, `DownloadForegroundService.kt`, `Mp4FlacUnwrapper.kt`, `NonFlacMetadataEmbedder.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/EngineSelectionTest.kt`

**Interfaces:**
- Produces: `interface NativeEngine` (below), `enum class EngineKind { GO, RUST }`, `class SessionGrantFailure(val extensionId: String?, message: String) : Exception(message)`, `object GoEngine : NativeEngine`, `object EngineSelection { const val RUST_FLAG_FILE = "engine_rust"; const val GO_FLAG_FILE = "engine_go"; fun select(isDebug: Boolean, filesDir: File, debugDefault: EngineKind): EngineKind }`, `object Engines { val DEBUG_DEFAULT: EngineKind; fun init(context: Context); val current: NativeEngine; val kind: EngineKind }`.
- In this task `Engines.init` can only build `GoEngine`; the `RUST` branch is wired in Task 4. Until then `select(...)` returning `RUST` must fall back to `GoEngine` with a log line (`"Rust engine not wired yet; using Go"`).

- [ ] **Step 0: Branch**

```bash
cd /Users/dinhvanhoang/Projects/LosslessMusic-v2
git switch -c feat/rust-engine-phase2   # from main 14dd4389; the only allowed branch switch
git branch --show-current               # feat/rust-engine-phase2
```

- [ ] **Step 1: Write the failing test**

`android/app/src/test/kotlin/xyz/losslessmusic/app/engine/EngineSelectionTest.kt`:
```kotlin
package xyz.losslessmusic.app.engine

import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class EngineSelectionTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun debugWithoutFlagsUsesDebugDefault() {
        val files = tmp.newFolder("files")
        assertEquals(EngineKind.GO, EngineSelection.select(true, files, EngineKind.GO))
        assertEquals(EngineKind.RUST, EngineSelection.select(true, files, EngineKind.RUST))
    }

    @Test fun debugRustFlagSelectsRust() {
        val files = tmp.newFolder("files")
        File(files, EngineSelection.RUST_FLAG_FILE).createNewFile()
        assertEquals(EngineKind.RUST, EngineSelection.select(true, files, EngineKind.GO))
    }

    @Test fun goFlagWinsOverRustFlag() {
        val files = tmp.newFolder("files")
        File(files, EngineSelection.RUST_FLAG_FILE).createNewFile()
        File(files, EngineSelection.GO_FLAG_FILE).createNewFile()
        assertEquals(EngineKind.GO, EngineSelection.select(true, files, EngineKind.RUST))
    }

    @Test fun releaseBuildAlwaysUsesGo() {
        val files = tmp.newFolder("files")
        File(files, EngineSelection.RUST_FLAG_FILE).createNewFile()
        assertEquals(EngineKind.GO, EngineSelection.select(false, files, EngineKind.RUST))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.EngineSelectionTest'; cd ..`
Expected: FAIL — `Unresolved reference: EngineSelection` / `EngineKind`.

- [ ] **Step 3: Create `NativeEngine.kt`**

```kotlin
package xyz.losslessmusic.app.engine

enum class EngineKind { GO, RUST }

/** A session-grant exchange failed; [extensionId] is null when the callback state itself was rejected. */
class SessionGrantFailure(val extensionId: String?, message: String) : Exception(message)

/**
 * The native engine contract, in the Go-era shapes the MethodChannel and Dart already expect
 * (see spec §3.1). Methods that throw in Go throw here (→ Dart PlatformException "BACKEND_ERROR");
 * getAllDownloadProgress, cancelDownload, allowDownloadDir, findUrlHandler, setLibraryCoverCacheDir
 * and setAppVersion never throw. downloadByStrategy reports failures in-band ({"success":false,…}).
 * All methods block; call them off the main thread.
 */
interface NativeEngine {
    val kind: EngineKind

    // init (group 1) — call order today: setAppVersion (Kotlin), setExtensionStorageMasterKey, initExtensionSystem
    fun setAppVersion(version: String)
    fun setExtensionStorageMasterKey(masterKey: String)
    fun initExtensionSystem(extDir: String, dataDir: String)
    fun loadExtensionsFromDir(dirPath: String): String

    // extensions
    fun loadExtensionFromPath(path: String): String
    fun getInstalledExtensions(): String
    fun setExtensionEnabled(id: String, enabled: Boolean)
    fun removeExtension(id: String)
    fun getExtensionSettings(id: String): String
    fun setExtensionSettings(id: String, settingsJson: String)
    fun getExtensionPendingAuth(extensionId: String): String
    fun getExtensionHomeFeed(extensionId: String): String
    fun customSearchWithExtension(extensionId: String, query: String, optionsJson: String): String
    /** Resolves the deep-link callback state, stores the grant and completes it; returns the extension id. */
    fun completeSessionGrant(callbackState: String, grant: String): String

    // search / metadata / priorities
    fun searchTracks(query: String, limit: Long, includeExtensions: Boolean): String
    fun handleUrl(url: String): String
    fun findUrlHandler(url: String): String
    fun getProviderMetadata(providerId: String, resourceType: String, resourceId: String): String
    fun getDownloadPriority(): String
    fun setDownloadPriority(priorityJson: String)
    fun getMetadataPriority(): String
    fun setMetadataPriority(priorityJson: String)
    fun setDownloadFallbackProviderIds(idsJson: String)

    // downloads / files
    fun downloadByStrategy(requestJson: String): String
    fun getAllDownloadProgress(): String
    fun cancelDownload(itemId: String)
    fun setDownloadDirectory(path: String)
    fun allowDownloadDir(path: String)
    fun checkDuplicate(outputDir: String, isrc: String): String
    fun getAudioQuality(path: String): String
    fun editFileMetadata(filePath: String, metadataJson: String): String
    fun reEnrichFile(requestJson: String): String
    fun getLyricsLRC(spotifyId: String, trackName: String, artistName: String, filePath: String, durationMs: Long): String
    fun setLibraryCoverCacheDir(cacheDir: String)
    fun scanLibraryFolder(folderPath: String): String
}
```

- [ ] **Step 4: Create `GoEngine.kt`** (exact calls MainActivity/FGService make today)

```kotlin
package xyz.losslessmusic.app.engine

import xyz.losslessmusic.backend.bridge.Bridge

/** Today's engine: 1:1 delegation to the gomobile Bridge. Behaviour must not change. */
object GoEngine : NativeEngine {
    override val kind = EngineKind.GO

    override fun setAppVersion(version: String) = Bridge.setAppVersion(version)
    override fun setExtensionStorageMasterKey(masterKey: String) = Bridge.setExtensionStorageMasterKey(masterKey)
    override fun initExtensionSystem(extDir: String, dataDir: String) = Bridge.initExtensionSystem(extDir, dataDir)
    override fun loadExtensionsFromDir(dirPath: String): String = Bridge.loadExtensionsFromDir(dirPath)

    override fun loadExtensionFromPath(path: String): String = Bridge.loadExtensionFromPath(path)
    override fun getInstalledExtensions(): String = Bridge.getInstalledExtensions()
    override fun setExtensionEnabled(id: String, enabled: Boolean) = Bridge.setExtensionEnabledByID(id, enabled)
    override fun removeExtension(id: String) = Bridge.removeExtensionByID(id)
    override fun getExtensionSettings(id: String): String = Bridge.getExtensionSettingsJSON(id)
    override fun setExtensionSettings(id: String, settingsJson: String) = Bridge.setExtensionSettingsJSON(id, settingsJson)
    override fun getExtensionPendingAuth(extensionId: String): String = Bridge.getExtensionPendingAuthJSON(extensionId)
    override fun getExtensionHomeFeed(extensionId: String): String = Bridge.getExtensionHomeFeedJSON(extensionId)
    override fun customSearchWithExtension(extensionId: String, query: String, optionsJson: String): String =
        Bridge.customSearchWithExtensionJSON(extensionId, query, optionsJson)

    override fun completeSessionGrant(callbackState: String, grant: String): String {
        // `state` is a one-time nonce (not the extension id): consume it first (v0.9.1 fix).
        val extensionId = try {
            Bridge.consumeExtensionCallbackState(callbackState)
        } catch (e: Exception) {
            throw SessionGrantFailure(null, e.message ?: "callback state rejected")
        }
        try {
            Bridge.setExtensionSessionGrantByID(extensionId, grant)
            Bridge.invokeExtensionActionJSON(extensionId, "completeGrant")
        } catch (e: Exception) {
            throw SessionGrantFailure(extensionId, e.message ?: "session grant failed")
        }
        return extensionId
    }

    override fun searchTracks(query: String, limit: Long, includeExtensions: Boolean): String =
        Bridge.searchTracksWithMetadataProvidersJSON(query, limit, includeExtensions)
    override fun handleUrl(url: String): String = Bridge.handleURLWithExtensionJSON(url)
    override fun findUrlHandler(url: String): String = Bridge.findURLHandlerJSON(url)
    override fun getProviderMetadata(providerId: String, resourceType: String, resourceId: String): String =
        Bridge.getProviderMetadataJSON(providerId, resourceType, resourceId)
    override fun getDownloadPriority(): String = Bridge.getProviderPriorityJSON()
    override fun setDownloadPriority(priorityJson: String) = Bridge.setProviderPriorityJSON(priorityJson)
    override fun getMetadataPriority(): String = Bridge.getMetadataProviderPriorityJSON()
    override fun setMetadataPriority(priorityJson: String) = Bridge.setMetadataProviderPriorityJSON(priorityJson)
    override fun setDownloadFallbackProviderIds(idsJson: String) = Bridge.setExtensionFallbackProviderIDsJSON(idsJson)

    override fun downloadByStrategy(requestJson: String): String = Bridge.downloadByStrategy(requestJson)
    override fun getAllDownloadProgress(): String = Bridge.getAllDownloadProgress()
    override fun cancelDownload(itemId: String) = Bridge.cancelDownload(itemId)
    override fun setDownloadDirectory(path: String) = Bridge.setDownloadDirectory(path)
    override fun allowDownloadDir(path: String) = Bridge.allowDownloadDir(path)
    override fun checkDuplicate(outputDir: String, isrc: String): String = Bridge.checkDuplicate(outputDir, isrc)
    override fun getAudioQuality(path: String): String = Bridge.getAudioQualityJSON(path)
    override fun editFileMetadata(filePath: String, metadataJson: String): String = Bridge.editFileMetadata(filePath, metadataJson)
    override fun reEnrichFile(requestJson: String): String = Bridge.reEnrichFile(requestJson)
    override fun getLyricsLRC(spotifyId: String, trackName: String, artistName: String, filePath: String, durationMs: Long): String =
        Bridge.getLyricsLRC(spotifyId, trackName, artistName, filePath, durationMs)
    override fun setLibraryCoverCacheDir(cacheDir: String) = Bridge.setLibraryCoverCacheDir(cacheDir)
    override fun scanLibraryFolder(folderPath: String): String = Bridge.scanLibraryFolderJSON(folderPath)
}
```
If a gomobile signature differs (e.g. a `Long` vs `Int` parameter), match the existing call in `MainActivity.kt` exactly — that code compiles today.

- [ ] **Step 5: Create `Engines.kt`**

```kotlin
package xyz.losslessmusic.app.engine

import android.content.Context
import android.util.Log
import xyz.losslessmusic.app.BuildConfig
import java.io.File

/** Pure selection rule (spec §3.4, ruling R-P6). Read once per process. */
object EngineSelection {
    const val RUST_FLAG_FILE = "engine_rust"
    const val GO_FLAG_FILE = "engine_go"

    fun select(isDebug: Boolean, filesDir: File, debugDefault: EngineKind): EngineKind {
        if (!isDebug) return EngineKind.GO
        if (File(filesDir, GO_FLAG_FILE).exists()) return EngineKind.GO
        if (File(filesDir, RUST_FLAG_FILE).exists()) return EngineKind.RUST
        return debugDefault
    }
}

/** Process-scoped engine holder: chosen on the first init() and never changed for the process lifetime. */
object Engines {
    /** Debug-build default. Phase-2 exit flips this to RUST; release builds are always GO until phase 5. */
    val DEBUG_DEFAULT = EngineKind.GO

    @Volatile private var engine: NativeEngine? = null

    fun init(context: Context) {
        if (engine != null) return
        synchronized(this) {
            if (engine != null) return
            val files = context.applicationContext.filesDir
            val selected = EngineSelection.select(BuildConfig.DEBUG, files, DEBUG_DEFAULT)
            engine = build(selected, files)
            Log.i("Engines", "engine=${engine!!.kind} (selected=$selected)")
        }
    }

    private fun build(kind: EngineKind, filesDir: File): NativeEngine = when (kind) {
        EngineKind.GO -> GoEngine
        EngineKind.RUST -> {
            Log.w("Engines", "Rust engine not wired yet; using Go")
            GoEngine
        }
    }

    val current: NativeEngine
        get() = engine ?: error("Engines.init(context) must run before the engine is used")

    val kind: EngineKind get() = current.kind
}
```

- [ ] **Step 6: Rewire call sites (no behaviour change)**

`MainActivity.kt`:
- Remove `import xyz.losslessmusic.backend.bridge.Bridge` except where the DLNA/bridge-local calls need it (`ping`, `startMediaServer`, `stopMediaServer`, `getMediaServerStatus` keep using `Bridge` — they are not engine calls). Add `import xyz.losslessmusic.app.engine.Engines` and `import xyz.losslessmusic.app.engine.EngineKind` and `import xyz.losslessmusic.app.engine.SessionGrantFailure`.
- First line of `onCreate`, **before** `super.onCreate(savedInstanceState)` (FlutterActivity calls `configureFlutterEngine` from inside `super.onCreate`): `Engines.init(applicationContext)`. Also call `Engines.init(applicationContext)` as the first line of `configureFlutterEngine` (idempotent).
- `configureFlutterEngine`: `Bridge.setAppVersion(versionName)` → `Engines.current.setAppVersion(versionName)`; progress `EventChannel` loop: `Bridge.getAllDownloadProgress()` → `Engines.current.getAllDownloadProgress()`.
- `handleSessionGrantIntent` executor body becomes:
```kotlin
        bridgeExecutor.execute {
            try {
                val extensionId = Engines.current.completeSessionGrant(callbackState, grant)
                mainHandler.post { notifySessionGrantCompleted(extensionId, true) }
            } catch (e: SessionGrantFailure) {
                android.util.Log.w("MainActivity", "session-grant exchange failed: ${e.message}")
                val id = e.extensionId
                if (!id.isNullOrEmpty()) mainHandler.post { notifySessionGrantCompleted(id, false) }
            } catch (e: Exception) {
                android.util.Log.w("MainActivity", "session-grant exchange failed: ${e.message}")
            }
        }
```
- `dispatch`: replace every engine call with `Engines.current.<method>` using this exact mapping (channel name → engine method; argument extraction unchanged):
  `getAudioQuality`→`getAudioQuality(path)`; `setExtensionStorageMasterKey`→`setExtensionStorageMasterKey`; `initExtensionSystem`→`initExtensionSystem`; `loadExtensionFromPath`→`loadExtensionFromPath`; `getInstalledExtensions`→`getInstalledExtensions`; `loadExtensionsFromDir`→`loadExtensionsFromDir`; `setExtensionEnabled`→`setExtensionEnabled`; `removeExtension`→`removeExtension`; `searchTracks`→`searchTracks`; `downloadByStrategy`→`downloadByStrategy`; `getAllProgress`→`getAllDownloadProgress`; `cancelDownload`→`cancelDownload`; `setDownloadDirectory`→`setDownloadDirectory`; `allowDownloadDir`→`allowDownloadDir`; `checkDuplicate`→`checkDuplicate`; `getExtensionSettings`→`getExtensionSettings`; `setExtensionSettings`→`setExtensionSettings`; `getDownloadPriority`→`getDownloadPriority`; `setDownloadPriority`→`setDownloadPriority`; `getMetadataPriority`→`getMetadataPriority`; `setMetadataPriority`→`setMetadataPriority`; `getExtensionHomeFeed`→`getExtensionHomeFeed`; `setDownloadFallbackProviderIds`→`setDownloadFallbackProviderIds`; `handleUrl`→`handleUrl`; `findUrlHandler`→`findUrlHandler`; `getProviderMetadata`→`getProviderMetadata`; `setLibraryCoverCacheDir`→`setLibraryCoverCacheDir`; `scanLibraryFolder`→`scanLibraryFolder`; `getLyricsLRC`→`getLyricsLRC`; `editFileMetadata`→`editFileMetadata`; `reEnrichFile`→`reEnrichFile`; `customSearchWithExtension`→`customSearchWithExtension`; `getExtensionPendingAuth`→`getExtensionPendingAuth`.
- The phase-1 probe in the `loadExtensionsFromDir` branch runs only when `Engines.kind == EngineKind.GO` (the probe opens its own Rust manager on the same `engine-rust/` dirs — it must never run next to `RustEngine`): wrap the existing `probeStartGate.afterLoad(...)` call in `if (Engines.kind == EngineKind.GO) { … }`.

`DownloadForegroundService.kt`: add `Engines.init(applicationContext)` as the first line of `onCreate()` (add an `override fun onCreate()` calling `super.onCreate()` first if none exists); replace `Bridge.downloadByStrategy`, `Bridge.checkDuplicate`, `Bridge.getAllDownloadProgress`, `Bridge.getLyricsLRC` with the `Engines.current` equivalents; update the two comments that mention `Bridge.cancelDownload()` to say `Engines.current.cancelDownload()`; drop the `Bridge` import.

`Mp4FlacUnwrapper.kt`: `Bridge.editFileMetadata(flacPath, md.toString())` → `Engines.current.editFileMetadata(flacPath, md.toString())`; drop the `Bridge` import.
`NonFlacMetadataEmbedder.kt`: `Bridge.getLyricsLRC(...)` → `Engines.current.getLyricsLRC(...)`; drop the `Bridge` import.

After editing, this must list only the bridge-local calls in MainActivity:
```bash
git grep -n 'Bridge\.' -- android/app/src/main/kotlin/xyz/losslessmusic/app
```
Expected: only `Bridge.ping`, `Bridge.startMediaServer`, `Bridge.stopMediaServer`, `Bridge.getMediaServerStatus` (MainActivity) and `Bridge.*` inside `engine/GoEngine.kt`.

- [ ] **Step 7: Run tests and build**

Run:
```bash
cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug; cd ..
flutter test
scripts/sync-upstream.sh --check-vendored
```
Expected: all unit tests PASS (existing 17 + 4 new), `BUILD SUCCESSFUL`, `+430: All tests passed!`, `✓ Layer 1 vendored cleanly.`

- [ ] **Step 8: Commit**

```bash
git branch --show-current   # feat/rust-engine-phase2
git add android/app/src/main/kotlin/xyz/losslessmusic/app/engine/NativeEngine.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/GoEngine.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/Engines.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/EngineSelectionTest.kt android/app/src/main/kotlin/xyz/losslessmusic/app/MainActivity.kt android/app/src/main/kotlin/xyz/losslessmusic/app/DownloadForegroundService.kt android/app/src/main/kotlin/xyz/losslessmusic/app/Mp4FlacUnwrapper.kt android/app/src/main/kotlin/xyz/losslessmusic/app/NonFlacMetadataEmbedder.kt
git commit -m "refactor(engine): route all engine calls through NativeEngine (Go default)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `RustCore` + `UniffiRustCore` (real engine, FFmpeg pump)

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustCore.kt`, `UniffiRustCore.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/UniffiRustCoreTest.kt` (runs the real engine from the host dylib via `jna.library.path`, already configured in Gradle)

**Interfaces:**
- Consumes: UniFFI `com.spotiflac.backend.{ExtensionManager, ExtensionEnvironment, CancellationRegistry, CancellationDomain, RequestLease, LyricsRequest, DownloadDirectoryScope}`; vendored `com.zarz.spotiflac.{CoreExtensionExecution, CoreFFmpegCommand, parseCoreFFmpegCommands, withCoreFFmpegExecution}` (Kotlin `internal`, same module — accessible).
- Produces: `interface RustCore : AutoCloseable` (below), `fun interface RustCoreFactory { fun create(sourceDirectory: String, dataDirectory: String, masterKey: String, appVersion: String): RustCore }`, `class UniffiRustCore : RustCore` with `companion object { val FACTORY: RustCoreFactory }`.

- [ ] **Step 1: Write the failing test**

`android/app/src/test/kotlin/xyz/losslessmusic/app/engine/UniffiRustCoreTest.kt`:
```kotlin
package xyz.losslessmusic.app.engine

import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Base64

class UniffiRustCoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private val key = Base64.getEncoder().encodeToString(ByteArray(32) { it.toByte() })
    private lateinit var core: RustCore
    private lateinit var out: File

    @Before fun setUp() {
        val src = tmp.newFolder("extensions")
        val data = tmp.newFolder("ext_data")
        out = tmp.newFolder("downloads")
        core = UniffiRustCore.FACTORY.create(src.canonicalPath, data.canonicalPath, key, "5.0.0")
        core.setAllowedDownloadDirectories(listOf(out.canonicalPath, out.absolutePath))
    }

    @After fun tearDown() { core.close() }

    @Test fun freshEngineHasNoExtensionsAndEmptyPriorities() {
        assertEquals(0, JSONArray(core.installed()).length())
        val p = JSONObject(core.providerPriorities())
        assertEquals(0, p.getJSONArray("download").length())
        assertEquals(0, p.getJSONArray("metadata").length())
    }

    @Test fun progressIsAnItemsObject() {
        assertTrue(JSONObject(core.allProgress()).has("items"))
    }

    @Test fun readAudioMetadataReportsQuality() {
        val flac = File(out, "silence.flac")
        File("../../go_backend/testdata/silence.flac").copyTo(flac)
        val scope = core.grantDownloadDirectories(listOf(out.canonicalPath))
        try {
            val m = JSONObject(core.readAudioMetadata(flac.canonicalPath))
            assertTrue(m.toString(), m.optInt("sampleRate") > 0)
        } finally {
            scope.close()
        }
    }

    @Test fun isrcLookupOnEmptyDirIsEmptyString() {
        assertEquals("", core.checkIsrcExists(out.canonicalPath, "USUM71703861"))
    }

    @Test fun downloadThroughPumpReturnsInBandFailureWhenExtensionsDisabled() {
        val req = JSONObject()
            .put("item_id", "t1").put("output_dir", out.canonicalPath)
            .put("use_extensions", false).put("track_name", "x").put("artist_name", "y")
        val res = JSONObject(core.downloadWithPump(req.toString()))
        assertFalse(res.getBoolean("success"))
        assertTrue(res.optString("error").isNotBlank())
    }

    @Test fun unknownCallbackStateThrows() {
        var threw = false
        try { core.resolveCallbackState("no-such-state") } catch (e: Exception) { threw = true }
        assertTrue(threw)
    }
}
```
The test JVM's working directory is `android/app`, so `../../go_backend/testdata/silence.flac` is the repo fixture. If `downloadWithPump` returns the failure JSON with a different key for the message, assert on the key the Rust envelope actually uses (`error`, per `crates/extensions/src/download/mod.rs`) and note it in the report.

- [ ] **Step 2: Run it to verify it fails**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.UniffiRustCoreTest'; cd ..`
Expected: FAIL — `Unresolved reference: RustCore` / `UniffiRustCore`.

- [ ] **Step 3: Create `RustCore.kt`**

```kotlin
package xyz.losslessmusic.app.engine

/**
 * The slice of the UniFFI API RustEngine uses, in plain Kotlin types so RustEngine can be tested
 * with a fake. One implementation talks to the real engine: UniffiRustCore.
 */
interface RustCore : AutoCloseable {
    // extensions
    fun loadAll(): String
    fun installed(): String
    fun install(packagePath: String): String
    fun setEnabled(extensionId: String, enabled: Boolean)
    fun remove(extensionId: String)
    fun settings(extensionId: String): String
    fun updateSettings(extensionId: String, settingsJson: String)
    fun pendingAuthJson(extensionId: String): String
    fun invokeAction(extensionId: String, action: String): String
    fun homeFeedJson(extensionId: String): String
    fun customSearchJson(extensionId: String, query: String, optionsJson: String): String
    fun resolveCallbackState(state: String): String
    fun setSessionGrant(extensionId: String, grant: String)

    // search / metadata / priorities
    fun searchMetadataProviders(query: String, limit: Long, includeExtensions: Boolean): String
    fun handleUrlJson(url: String): String
    fun findUrlHandler(url: String): String?
    fun getProviderMetadataJson(providerId: String, resourceType: String, resourceId: String): String
    fun providerPriorities(): String
    fun setProviderPriority(kind: String, ids: List<String>)
    fun setFallbackProviders(ids: List<String>?)

    // downloads / files
    fun downloadWithPump(requestJson: String): String
    fun allProgress(): String
    fun cancelDownload(itemId: String)
    fun setAllowedDownloadDirectories(directories: List<String>)
    /** Scoped directory lease; close() releases it. */
    fun grantDownloadDirectories(directories: List<String>): AutoCloseable
    fun checkIsrcExists(directory: String, isrc: String): String
    fun addToIsrcIndex(directory: String, isrc: String, path: String)
    fun readAudioMetadata(path: String): String
    fun editFileMetadata(path: String, metadataJson: String): String
    fun reenrichFile(requestJson: String): String
    fun getLyricsLrc(spotifyId: String, track: String, artist: String, filePath: String, durationMs: Long): String
    fun setLibraryCoverCacheDirectory(directory: String)
    fun scanLibraryFolder(folder: String): String
}

fun interface RustCoreFactory {
    fun create(sourceDirectory: String, dataDirectory: String, masterKey: String, appVersion: String): RustCore
}
```

- [ ] **Step 4: Create `UniffiRustCore.kt`**

```kotlin
package xyz.losslessmusic.app.engine

import com.spotiflac.backend.CancellationDomain
import com.spotiflac.backend.CancellationRegistry
import com.spotiflac.backend.ExtensionEnvironment
import com.spotiflac.backend.ExtensionManager
import com.spotiflac.backend.LyricsRequest
import com.spotiflac.backend.RequestLease
import com.zarz.spotiflac.CoreExtensionExecution
import com.zarz.spotiflac.CoreFFmpegCommand
import com.zarz.spotiflac.parseCoreFFmpegCommands
import com.zarz.spotiflac.withCoreFFmpegExecution
import java.util.UUID

/** RustCore over the real UniFFI engine. Every call blocks; never call from the main thread. */
class UniffiRustCore private constructor(private val manager: ExtensionManager) : RustCore {
    companion object {
        private const val TIMEOUT_MS: ULong = 30_000uL
        private const val POST_PROCESS_TIMEOUT_MS: ULong = 120_000uL

        val FACTORY = RustCoreFactory { source, data, masterKey, appVersion ->
            UniffiRustCore(ExtensionManager.withLyricsSettings(source, data, masterKey, appVersion, TIMEOUT_MS, "[]", "{}"))
        }
    }

    private val requests = CancellationRegistry(CancellationDomain.EXTENSION_REQUEST)

    private inline fun <T> env(block: (ExtensionEnvironment) -> T): T = manager.environment().use(block)

    private inline fun <T> withLease(block: (RequestLease) -> T): T {
        val lease = requests.acquire(UUID.randomUUID().toString())
        try {
            return block(lease)
        } finally {
            try { lease.release() } finally { lease.close() }
        }
    }

    override fun loadAll(): String = manager.loadAll()
    override fun installed(): String = manager.installed()
    override fun install(packagePath: String): String = manager.install(packagePath)
    override fun setEnabled(extensionId: String, enabled: Boolean) = manager.setEnabled(extensionId, enabled)
    override fun remove(extensionId: String) = manager.remove(extensionId)
    override fun settings(extensionId: String): String = env { it.settings(extensionId) }
    override fun updateSettings(extensionId: String, settingsJson: String) = manager.updateSettings(extensionId, settingsJson)
    override fun pendingAuthJson(extensionId: String): String = manager.getExtensionPendingAuthJson(extensionId)
    override fun invokeAction(extensionId: String, action: String): String = manager.invokeAction(extensionId, action)
    override fun homeFeedJson(extensionId: String): String = withLease { manager.getExtensionHomeFeedJson(extensionId, it) }
    override fun customSearchJson(extensionId: String, query: String, optionsJson: String): String =
        withLease { manager.customSearchJson(extensionId, query, optionsJson, it) }
    override fun resolveCallbackState(state: String): String = env { it.resolveCallbackState(state) }
    override fun setSessionGrant(extensionId: String, grant: String) = env { it.setSessionGrant(extensionId, grant) }

    override fun searchMetadataProviders(query: String, limit: Long, includeExtensions: Boolean): String =
        manager.searchMetadataProviders(query, limit, includeExtensions, "", TIMEOUT_MS)
    override fun handleUrlJson(url: String): String = manager.handleUrlJson(url)
    override fun findUrlHandler(url: String): String? = manager.findUrlHandler(url)
    override fun getProviderMetadataJson(providerId: String, resourceType: String, resourceId: String): String =
        manager.getProviderMetadataJson(providerId, resourceType, resourceId, null)
    override fun providerPriorities(): String = manager.providerPriorities()
    override fun setProviderPriority(kind: String, ids: List<String>) = manager.setProviderPriority(kind, ids)
    override fun setFallbackProviders(ids: List<String>?) = manager.setFallbackProviders(ids)

    override fun downloadWithPump(requestJson: String): String {
        val commands = env { it.ffmpegCommands() }
        val execution = object : CoreExtensionExecution {
            override fun download(requestJson: String): String = manager.downloadByStrategy(requestJson)
            override fun postProcess(inputJson: String, metadataJson: String): String =
                manager.runPostProcessing(inputJson, metadataJson, POST_PROCESS_TIMEOUT_MS)
            override fun waitPending(timeoutMs: Long): List<CoreFFmpegCommand> =
                parseCoreFFmpegCommands(commands.waitPending(timeoutMs))
            override fun commandIsActive(commandId: String): Boolean = commands.getCommand(commandId).isNotEmpty()
            override fun complete(commandId: String, success: Boolean, output: String, error: String) {
                commands.complete(commandId, success, output, error)
            }
            override fun close() = commands.close()
        }
        // withCoreFFmpegExecution runs FFmpeg commands through NativeDownloadFinalizer.runFFmpegArguments
        // (our EngineShims → ffmpeg-kit) on a pump thread and closes `execution` when done.
        return withCoreFFmpegExecution(execution) { it.download(requestJson) }
    }

    override fun allProgress(): String = env { e -> e.downloadState().use { it.allProgress() } }
    override fun cancelDownload(itemId: String) = env { e -> e.downloadState().use { it.cancelDownload(itemId) } }
    override fun setAllowedDownloadDirectories(directories: List<String>) = env { it.setAllowedDownloadDirectories(directories) }
    override fun grantDownloadDirectories(directories: List<String>): AutoCloseable {
        val scope = env { it.grantDownloadDirectories(directories) }
        return AutoCloseable { try { scope.release() } finally { scope.close() } }
    }
    override fun checkIsrcExists(directory: String, isrc: String): String = env { it.checkIsrcExists(directory, isrc, null) }
    override fun addToIsrcIndex(directory: String, isrc: String, path: String) = env { it.addToIsrcIndex(directory, isrc, path, null) }
    override fun readAudioMetadata(path: String): String = manager.readAudioMetadata(path, "", "", null)
    override fun editFileMetadata(path: String, metadataJson: String): String = manager.editFileMetadata(path, metadataJson, null)
    override fun reenrichFile(requestJson: String): String = manager.reenrichFile(requestJson, null)
    override fun getLyricsLrc(spotifyId: String, track: String, artist: String, filePath: String, durationMs: Long): String =
        manager.getLyricsLrc(LyricsRequest(spotifyId, track, artist, filePath, durationMs), null)
    override fun setLibraryCoverCacheDirectory(directory: String) = manager.setLibraryCoverCacheDirectory(directory)
    override fun scanLibraryFolder(folder: String): String = manager.scanLibraryFolder(folder, null)

    override fun close() {
        try { requests.shutdown() } catch (_: Exception) {}
        requests.close()
        try { manager.shutdown() } catch (_: Exception) {}
        manager.close()
    }
}
```
If `use` does not resolve on a UniFFI object, use the bindings' own `Disposable`/`AutoCloseable` `use` extension; if a constructor/argument name differs from the generated `spotiflac_mobile.kt`, use the generated one and note it.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.UniffiRustCoreTest'; cd ..`
Expected: 6 tests PASS.

- [ ] **Step 6: Full unit tests + build + vendored check, then commit**

```bash
cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug; cd ..
scripts/sync-upstream.sh --check-vendored
git branch --show-current
git add android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustCore.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/UniffiRustCore.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/UniffiRustCoreTest.kt
git commit -m "feat(engine): RustCore over UniFFI with FFmpeg-pumped downloads

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `RustJson` adapters

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustJson.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/RustJsonTest.kt`

**Interfaces:**
- Produces: `object RustJson { const val EMPTY_PROGRESS = "{\"items\":{}}"; fun ids(json: String): List<String>; fun idsOrNull(json: String?): List<String>?; fun priorities(raw: String, kind: String): String; fun duplicate(path: String): String; fun audioQuality(raw: String): String }`.
- Go shapes these must reproduce (Dart reads them): priorities = JSON array of ids; duplicate = `{"exists":bool,"filepath":string}` (key `filepath`, not `file_path`); audio quality = `{bit_depth, sample_rate, total_samples, duration, bitrate?, codec?}` (Dart reads `bit_depth, sample_rate, bitrate, duration, codec`). Rust `readAudioMetadata` is camelCase: `bitDepth`, `sampleRate`, `duration`, `bitrate` (each omitted when 0) and `format` (codec name for MP4-family, else container ext).

- [ ] **Step 1: Write the failing test**

```kotlin
package xyz.losslessmusic.app.engine

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RustJsonTest {
    @Test fun idsParsesAnArray() = assertEquals(listOf("a", "b"), RustJson.ids("[\"a\",\"b\"]"))

    @Test(expected = Exception::class) fun idsRejectsMalformedJson() { RustJson.ids("not json") }

    @Test fun idsOrNullTreatsBlankAndNullAsClear() {
        assertNull(RustJson.idsOrNull(null)); assertNull(RustJson.idsOrNull("")); assertNull(RustJson.idsOrNull(" null "))
        assertEquals(listOf("x"), RustJson.idsOrNull("[\"x\"]"))
    }

    @Test fun prioritiesUnwrapsTheRequestedKind() {
        val raw = "{\"download\":[\"qobuz-web\",\"amazon\"],\"metadata\":[\"deezer\"]}"
        assertEquals(listOf("qobuz-web", "amazon"), RustJson.ids(RustJson.priorities(raw, "download")))
        assertEquals(listOf("deezer"), RustJson.ids(RustJson.priorities(raw, "metadata")))
        assertEquals("[]", RustJson.priorities("{}", "download"))
    }

    @Test fun duplicateKeepsTheGoKeyNames() {
        val hit = JSONObject(RustJson.duplicate("/m/a.flac"))
        assertTrue(hit.getBoolean("exists")); assertEquals("/m/a.flac", hit.getString("filepath"))
        val miss = JSONObject(RustJson.duplicate(""))
        assertFalse(miss.getBoolean("exists")); assertEquals("", miss.getString("filepath"))
    }

    @Test fun audioQualityMapsCamelCaseToGoShape() {
        val q = JSONObject(RustJson.audioQuality("{\"bitDepth\":24,\"sampleRate\":96000,\"duration\":245,\"bitrate\":2300,\"format\":\"flac\"}"))
        assertEquals(24, q.getInt("bit_depth")); assertEquals(96000, q.getInt("sample_rate"))
        assertEquals(245, q.getInt("duration")); assertEquals(2300, q.getInt("bitrate"))
        assertEquals("flac", q.getString("codec")); assertEquals(0, q.getInt("total_samples"))
    }

    @Test fun audioQualityOmitsAbsentOptionalFields() {
        val q = JSONObject(RustJson.audioQuality("{\"sampleRate\":44100}"))
        assertEquals(0, q.getInt("bit_depth")); assertFalse(q.has("bitrate")); assertFalse(q.has("codec"))
    }

    @Test fun emptyProgressIsAnEmptyItemsObject() =
        assertEquals(0, JSONObject(RustJson.EMPTY_PROGRESS).getJSONObject("items").length())
}
```

- [ ] **Step 2: Run to verify it fails** — `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.RustJsonTest'; cd ..` → FAIL (`Unresolved reference: RustJson`).

- [ ] **Step 3: Implement**

```kotlin
package xyz.losslessmusic.app.engine

import org.json.JSONArray
import org.json.JSONObject

/** Pure JSON adapters between Rust engine shapes and the Go-era shapes Dart reads. */
object RustJson {
    const val EMPTY_PROGRESS = "{\"items\":{}}"

    fun ids(json: String): List<String> {
        val array = JSONArray(json)
        return List(array.length()) { array.getString(it) }
    }

    fun idsOrNull(json: String?): List<String>? {
        val trimmed = json?.trim() ?: return null
        if (trimmed.isEmpty() || trimmed == "null") return null
        return ids(trimmed)
    }

    fun priorities(raw: String, kind: String): String =
        JSONObject(raw).optJSONArray(kind)?.toString() ?: "[]"

    fun duplicate(path: String): String =
        JSONObject().put("exists", path.isNotEmpty()).put("filepath", path).toString()

    fun audioQuality(raw: String): String {
        val m = JSONObject(raw)
        val out = JSONObject()
            .put("bit_depth", m.optInt("bitDepth", 0))
            .put("sample_rate", m.optInt("sampleRate", 0))
            .put("total_samples", 0)
            .put("duration", m.optInt("duration", 0))
        if (m.has("bitrate")) out.put("bitrate", m.optInt("bitrate"))
        val format = m.optString("format", "")
        if (format.isNotEmpty()) out.put("codec", format)
        return out.toString()
    }
}
```

- [ ] **Step 4: Run to verify it passes** (8 tests), then `cd android && ./gradlew :app:testDebugUnitTest; cd ..`.

- [ ] **Step 5: Commit**

```bash
git branch --show-current
git add android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustJson.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/RustJsonTest.kt
git commit -m "feat(engine): JSON adapters from Rust shapes to the Go-era contract

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `RustEngine` (state machine, config buffer, dirs, leases, all methods) + wire into `Engines`

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustEngine.kt`
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/Engines.kt` (RUST branch)
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/FakeRustCore.kt`, `RustEngineTest.kt`

**Interfaces:**
- Consumes: `NativeEngine`, `EngineKind`, `SessionGrantFailure` (Task 1); `RustCore`, `RustCoreFactory`, `UniffiRustCore.FACTORY` (Task 2); `RustJson` (Task 3); `EngineDataIsolation.ensureRustCopy(goExtDir: File, goDataDir: File): Dirs` and `EngineVersion.SPOTIFLAC_ENGINE_VERSION` (phase 1); vendored `com.zarz.spotiflac.requireSuccessfulExtensionAction(extensionId: String, actionName: String, response: String)` (throws `IllegalStateException` unless `success:true`).
- Produces: `class RustEngine(factory: RustCoreFactory, filesDir: File, readyTimeoutMs: Long = RustEngine.DEFAULT_READY_TIMEOUT_MS, log: (String) -> Unit = {}) : NativeEngine` with `companion object { const val DEFAULT_READY_TIMEOUT_MS = 15_000L; const val NOT_READY = "engine_not_ready"; const val MISSING_KEY = "extension storage master key is not configured" }` and `val state: RustEngine.State` (for tests).

Behaviour (spec §3.1 init state machine + rulings R-P1..R-P5):
- `setExtensionStorageMasterKey` / `initExtensionSystem` record their values; a **different** value for an already-recorded argument throws `IllegalStateException("already_initialized: …")` in every state.
- `initExtensionSystem` constructs synchronously (the Dart call returns after construction, like Go): without a recorded key it throws `MISSING_KEY` (Go's message). Construction = `EngineDataIsolation.ensureRustCopy(goExt, goData)` → `factory.create(copy.extensions, copy.data, key, EngineVersion.SPOTIFLAC_ENGINE_VERSION)` → apply buffered config → READY. Any failure: close the core, state FAILED, rethrow. A later `initExtensionSystem` with the same values retries.
- Buffered config (R-P4): download dirs (from `setDownloadDirectory` + `allowDownloadDir`), download/metadata priority JSON, fallback ids JSON, cover-cache dir. Setters record under the lock and, when READY, apply at once. Construction applies all of them. The allow-list is always the full list: `[filesDir canonical, filesDir absolute] + [canonical, absolute] of every known download dir` (R-P3).
- `requireCore()` waits on the readiness gate up to `readyTimeoutMs`; FAILED or timeout throws `IllegalStateException("engine_not_ready: <reason>")` (R-P5). Non-waiting (`coreOrNull`) for `getAllDownloadProgress` (→ `EMPTY_PROGRESS` before READY or on error) and `cancelDownload` (no-op / swallow).
- Priority getters before READY return the buffered JSON (or `"[]"`), after READY `RustJson.priorities(core.providerPriorities(), kind)`.
- `setAppVersion` is a no-op: the engine always receives `EngineVersion.SPOTIFLAC_ENGINE_VERSION` at construction (the fork's own version would fail every extension `minAppVersion` gate).
- `loadExtensionsFromDir(dirPath)`: canonical `dirPath` must equal the recorded Go ext dir, else throw `"Extension source directory does not match the initialized owner"`; then `core.loadAll()`.
- Directory leases (`withGrant`): `downloadByStrategy` (request `output_dir`), `checkDuplicate`, `getAudioQuality`/`editFileMetadata`/`reEnrichFile`/`getLyricsLRC` with a file (parent dir), `scanLibraryFolder` (folder). Lease closed in `finally`. Cover cache holds one lease for the current dir (new lease opened before the old is closed; on failure the new lease is closed).
- `downloadByStrategy`: after a result with `success:true`, non-blank `file_path` and an ISRC (result `isrc`, else request `isrc`), best-effort `core.addToIsrcIndex(output_dir, isrc, file_path)` so the next duplicate check sees it. Result returned unchanged.
- `editFileMetadata` canonicalises the path; `reEnrichFile` canonicalises `file_path` unless `preview_only`.
- `completeSessionGrant` (R-P2): `resolveCallbackState` (failure → `SessionGrantFailure(null, …)`) → `setSessionGrant` → `requireSuccessfulExtensionAction(id, "completeGrant", invokeAction(id, "completeGrant"))` (failure → `SessionGrantFailure(id, …)`) → return id.
- `findUrlHandler` never throws (→ `""`); `setLibraryCoverCacheDir` never throws (logs).

- [ ] **Step 1: Write the fake**

`android/app/src/test/kotlin/xyz/losslessmusic/app/engine/FakeRustCore.kt`:
```kotlin
package xyz.losslessmusic.app.engine

/** Records calls; return values are configurable per test. Thread-safe enough for these tests. */
class FakeRustCore : RustCore {
    val calls = mutableListOf<String>()
    var openLeases = 0
    var leasesOpened = 0
    var allowed: List<String> = emptyList()
    var priorities = "{\"download\":[],\"metadata\":[]}"
    var progress = "{\"items\":{\"a\":{\"item_id\":\"a\",\"progress\":0.5}}}"
    var downloadResult = "{\"success\":true,\"file_path\":\"/out/a.flac\",\"isrc\":\"ISRC1\"}"
    var downloadThrows: Exception? = null
    var isrcPath = ""
    var audioMetadata = "{\"bitDepth\":16,\"sampleRate\":44100,\"duration\":10,\"format\":\"flac\"}"
    var resolveResult: () -> String = { "qobuz-web" }
    var actionResult = "{\"success\":true}"
    var findResult: String? = "qobuz-web"
    var closed = false

    private fun rec(s: String) { synchronized(calls) { calls += s } }

    override fun loadAll() = "{\"loaded\":[],\"errors\":[]}".also { rec("loadAll") }
    override fun installed() = "[]".also { rec("installed") }
    override fun install(packagePath: String) = "{}".also { rec("install:$packagePath") }
    override fun setEnabled(extensionId: String, enabled: Boolean) = rec("setEnabled:$extensionId:$enabled")
    override fun remove(extensionId: String) = rec("remove:$extensionId")
    override fun settings(extensionId: String) = "{}".also { rec("settings:$extensionId") }
    override fun updateSettings(extensionId: String, settingsJson: String) = rec("updateSettings:$extensionId")
    override fun pendingAuthJson(extensionId: String) = "".also { rec("pendingAuth:$extensionId") }
    override fun invokeAction(extensionId: String, action: String) = actionResult.also { rec("invokeAction:$extensionId:$action") }
    override fun homeFeedJson(extensionId: String) = "{}".also { rec("homeFeed:$extensionId") }
    override fun customSearchJson(extensionId: String, query: String, optionsJson: String) = "[]".also { rec("customSearch:$extensionId:$query") }
    override fun resolveCallbackState(state: String) = resolveResult().also { rec("resolve:$state") }
    override fun setSessionGrant(extensionId: String, grant: String) = rec("setSessionGrant:$extensionId")
    override fun searchMetadataProviders(query: String, limit: Long, includeExtensions: Boolean) = "[]".also { rec("search:$query:$limit:$includeExtensions") }
    override fun handleUrlJson(url: String) = "{}".also { rec("handleUrl:$url") }
    override fun findUrlHandler(url: String) = findResult.also { rec("findUrlHandler:$url") }
    override fun getProviderMetadataJson(providerId: String, resourceType: String, resourceId: String) = "{}".also { rec("providerMetadata:$providerId") }
    override fun providerPriorities() = priorities.also { rec("providerPriorities") }
    override fun setProviderPriority(kind: String, ids: List<String>) = rec("setProviderPriority:$kind:${ids.joinToString(",")}")
    override fun setFallbackProviders(ids: List<String>?) = rec("setFallbackProviders:${ids?.joinToString(",")}")
    override fun downloadWithPump(requestJson: String): String { rec("download"); downloadThrows?.let { throw it }; return downloadResult }
    override fun allProgress() = progress.also { rec("allProgress") }
    override fun cancelDownload(itemId: String) = rec("cancel:$itemId")
    override fun setAllowedDownloadDirectories(directories: List<String>) { allowed = directories; rec("setAllowed") }
    override fun grantDownloadDirectories(directories: List<String>): AutoCloseable {
        synchronized(calls) { openLeases++; leasesOpened++; calls += "grant:${directories.first()}" }
        return AutoCloseable { synchronized(calls) { openLeases--; calls += "release" } }
    }
    override fun checkIsrcExists(directory: String, isrc: String) = isrcPath.also { rec("checkIsrc:$directory:$isrc") }
    override fun addToIsrcIndex(directory: String, isrc: String, path: String) = rec("addIsrc:$directory:$isrc:$path")
    override fun readAudioMetadata(path: String) = audioMetadata.also { rec("readAudio:$path") }
    override fun editFileMetadata(path: String, metadataJson: String) = "{\"success\":true,\"method\":\"native\"}".also { rec("edit:$path") }
    override fun reenrichFile(requestJson: String) = "{}".also { rec("reenrich:$requestJson") }
    override fun getLyricsLrc(spotifyId: String, track: String, artist: String, filePath: String, durationMs: Long) = "[00:00.00]x".also { rec("lyrics:$track") }
    override fun setLibraryCoverCacheDirectory(directory: String) = rec("coverCache:$directory")
    override fun scanLibraryFolder(folder: String) = "[]".also { rec("scan:$folder") }
    override fun close() { closed = true; rec("close") }
}
```

- [ ] **Step 2: Write the failing tests**

`android/app/src/test/kotlin/xyz/losslessmusic/app/engine/RustEngineTest.kt`:
```kotlin
package xyz.losslessmusic.app.engine

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class RustEngineTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var files: File
    private lateinit var ext: File
    private lateinit var data: File
    private lateinit var fake: FakeRustCore
    private var creates = 0
    private var createArgs: List<String> = emptyList()
    private var failCreate: Exception? = null
    private lateinit var engine: RustEngine

    @Before fun setUp() {
        files = tmp.newFolder("files")
        ext = File(files, "extensions").apply { mkdirs() }
        data = File(files, "ext_data").apply { mkdirs() }
        fake = FakeRustCore()
        engine = RustEngine({ s, d, k, v ->
            creates++; createArgs = listOf(s, d, k, v); failCreate?.let { throw it }; fake
        }, files, readyTimeoutMs = 100)
    }

    private fun init() {
        engine.setExtensionStorageMasterKey("KEY")
        engine.initExtensionSystem(ext.path, data.path)
    }

    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit): T {
        try { block() } catch (t: Throwable) { if (t is T) return t; throw t }
        fail("expected ${T::class.simpleName}"); throw IllegalStateException()
    }

    // --- init state machine ---
    @Test fun initWithoutKeyThrowsGoMessage() {
        val e = assertThrows<IllegalStateException> { engine.initExtensionSystem(ext.path, data.path) }
        assertEquals(RustEngine.MISSING_KEY, e.message)
        assertEquals(0, creates)
    }

    @Test fun initConstructsOnceOnTheEngineRustCopyWithBaselineVersion() {
        init(); engine.initExtensionSystem(ext.path, data.path)
        assertEquals(1, creates)
        assertEquals(RustEngine.State.READY, engine.state)
        assertTrue(createArgs[0].endsWith("engine-rust/extensions"))
        assertTrue(createArgs[1].endsWith("engine-rust/ext_data"))
        assertEquals("KEY", createArgs[2]); assertEquals("5.0.0", createArgs[3])
    }

    @Test fun conflictingValuesAreRejectedInEveryState() {
        engine.setExtensionStorageMasterKey("KEY")
        assertThrows<IllegalStateException> { engine.setExtensionStorageMasterKey("OTHER") }
        engine.initExtensionSystem(ext.path, data.path)
        assertThrows<IllegalStateException> { engine.initExtensionSystem(File(files, "x").path, data.path) }
        assertThrows<IllegalStateException> { engine.setExtensionStorageMasterKey("OTHER") }
        engine.setExtensionStorageMasterKey("KEY") // same value is a no-op
    }

    @Test fun constructorFailureLeavesFailedStateAndRetrySucceeds() {
        failCreate = IllegalStateException("boom")
        engine.setExtensionStorageMasterKey("KEY")
        assertThrows<IllegalStateException> { engine.initExtensionSystem(ext.path, data.path) }
        assertEquals(RustEngine.State.FAILED, engine.state)
        val e = assertThrows<IllegalStateException> { engine.getInstalledExtensions() }
        assertTrue(e.message!!.startsWith(RustEngine.NOT_READY))
        failCreate = null
        engine.initExtensionSystem(ext.path, data.path)
        assertEquals(RustEngine.State.READY, engine.state)
    }

    @Test fun managerCallsBeforeInitTimeOutWithNotReady() {
        val e = assertThrows<IllegalStateException> { engine.getInstalledExtensions() }
        assertTrue(e.message!!.startsWith(RustEngine.NOT_READY))
    }

    @Test fun progressBeforeInitReturnsEmptyWithoutWaiting() {
        val t0 = System.nanoTime()
        assertEquals(RustJson.EMPTY_PROGRESS, engine.getAllDownloadProgress())
        assertTrue((System.nanoTime() - t0) / 1_000_000 < 50)
        engine.cancelDownload("x") // no-op, no throw
    }

    @Test fun preInitConfigIsBufferedAndAppliedAtConstruction() {
        val out = tmp.newFolder("music")
        engine.setDownloadFallbackProviderIds("[\"amazon\"]")
        engine.setDownloadDirectory(out.path)
        engine.allowDownloadDir(out.path)
        engine.setDownloadPriority("[\"qobuz-web\"]")
        engine.setMetadataPriority("[\"deezer\"]")
        assertEquals("[\"qobuz-web\"]", engine.getDownloadPriority())
        assertEquals(0, creates)
        init()
        assertTrue(fake.calls.contains("setFallbackProviders:amazon"))
        assertTrue(fake.calls.contains("setProviderPriority:download:qobuz-web"))
        assertTrue(fake.calls.contains("setProviderPriority:metadata:deezer"))
        assertTrue(fake.allowed.contains(out.canonicalPath))
        assertTrue(fake.allowed.contains(files.canonicalPath))
    }

    @Test fun settersAfterReadyApplyImmediatelyWithFullAllowList() {
        init()
        val a = tmp.newFolder("a"); val b = tmp.newFolder("b")
        engine.allowDownloadDir(a.path); engine.allowDownloadDir(b.path)
        assertTrue(fake.allowed.containsAll(listOf(a.canonicalPath, b.canonicalPath, files.canonicalPath)))
        engine.setDownloadFallbackProviderIds("")
        assertTrue(fake.calls.contains("setFallbackProviders:null"))
    }

    @Test fun malformedPriorityJsonThrowsLikeGo() {
        init()
        assertThrows<Exception> { engine.setDownloadPriority("oops") }
    }

    @Test fun prioritiesUnwrapAfterReady() {
        init(); fake.priorities = "{\"download\":[\"amazon\"],\"metadata\":[\"deezer\"]}"
        assertEquals("[\"amazon\"]", engine.getDownloadPriority())
        assertEquals("[\"deezer\"]", engine.getMetadataPriority())
    }

    @Test fun loadExtensionsFromDirChecksTheInitDir() {
        init()
        engine.loadExtensionsFromDir(ext.path)
        assertTrue(fake.calls.contains("loadAll"))
        assertThrows<IllegalStateException> { engine.loadExtensionsFromDir(tmp.newFolder("other").path) }
    }

    @Test fun setAppVersionIsIgnored() { engine.setAppVersion("0.10.0"); init(); assertEquals("5.0.0", createArgs[3]) }

    // --- methods ---
    @Test fun downloadGrantsOutputDirAndIndexesTheFile() {
        init()
        val res = engine.downloadByStrategy("{\"item_id\":\"1\",\"output_dir\":\"/out\",\"isrc\":\"REQ\"}")
        assertTrue(JSONObject(res).getBoolean("success"))
        assertTrue(fake.calls.contains("grant:/out") || fake.calls.any { it.startsWith("grant:") })
        assertTrue(fake.calls.contains("addIsrc:/out:ISRC1:/out/a.flac"))
        assertEquals(0, fake.openLeases)
    }

    @Test fun inBandDownloadFailureIsReturnedUnchangedAndNotIndexed() {
        init(); fake.downloadResult = "{\"success\":false,\"error\":\"x\",\"error_type\":\"network\"}"
        val res = JSONObject(engine.downloadByStrategy("{\"output_dir\":\"/out\"}"))
        assertFalse(res.getBoolean("success")); assertEquals("network", res.getString("error_type"))
        assertFalse(fake.calls.any { it.startsWith("addIsrc") })
    }

    @Test fun grantScopesAreReleasedOnEveryPath() {
        init()
        engine.downloadByStrategy("{\"output_dir\":\"/out\"}")
        fake.downloadResult = "{\"success\":false}"; engine.downloadByStrategy("{\"output_dir\":\"/out\"}")
        fake.downloadThrows = IllegalStateException("structural")
        assertThrows<IllegalStateException> { engine.downloadByStrategy("{\"output_dir\":\"/out\"}") }
        engine.scanLibraryFolder("/lib"); engine.checkDuplicate("/out", "I")
        assertEquals(0, fake.openLeases)
        assertTrue(fake.leasesOpened >= 5)
    }

    @Test fun checkDuplicateUsesGoShape() {
        init(); fake.isrcPath = "/out/a.flac"
        val r = JSONObject(engine.checkDuplicate("/out", "I"))
        assertTrue(r.getBoolean("exists")); assertEquals("/out/a.flac", r.getString("filepath"))
    }

    @Test fun audioQualityIsRemapped() {
        init()
        val q = JSONObject(engine.getAudioQuality(File(tmp.root, "x.flac").path))
        assertEquals(16, q.getInt("bit_depth")); assertEquals(44100, q.getInt("sample_rate"))
    }

    @Test fun progressAndCancelDelegateAfterReady() {
        init()
        assertTrue(JSONObject(engine.getAllDownloadProgress()).getJSONObject("items").has("a"))
        engine.cancelDownload("a"); assertTrue(fake.calls.contains("cancel:a"))
    }

    @Test fun findUrlHandlerNeverThrowsAndMapsNull() {
        init(); fake.findResult = null
        assertEquals("", engine.findUrlHandler("https://x"))
    }

    @Test fun reEnrichCanonicalisesFilePathUnlessPreview() {
        init()
        val f = File(tmp.root, "d/../song.flac")
        engine.reEnrichFile(JSONObject().put("file_path", f.path).toString())
        assertTrue(fake.calls.any { it.startsWith("reenrich:") && it.contains(File(tmp.root, "song.flac").canonicalPath.replace("/", "\\/")) || it.contains(File(tmp.root, "song.flac").canonicalPath) })
    }

    @Test fun coverCacheKeepsOneLease() {
        init()
        engine.setLibraryCoverCacheDir(tmp.newFolder("c1").path)
        engine.setLibraryCoverCacheDir(tmp.newFolder("c2").path)
        assertEquals(1, fake.openLeases)
    }

    // --- session grant (R-P2) ---
    @Test fun sessionGrantSuccessPeeksGrantsAndCompletes() {
        init()
        assertEquals("qobuz-web", engine.completeSessionGrant("nonce", "grant"))
        assertTrue(fake.calls.containsAll(listOf("resolve:nonce", "setSessionGrant:qobuz-web", "invokeAction:qobuz-web:completeGrant")))
    }

    @Test fun sessionGrantUnknownStateFailsWithoutExtensionId() {
        init(); fake.resolveResult = { throw IllegalStateException("unknown state") }
        val e = assertThrows<SessionGrantFailure> { engine.completeSessionGrant("bad", "g") }
        assertNull(e.extensionId)
    }

    @Test fun sessionGrantCompleteGrantFailureCarriesExtensionId() {
        init(); fake.actionResult = "{\"success\":false,\"error\":\"denied\"}"
        val e = assertThrows<SessionGrantFailure> { engine.completeSessionGrant("nonce", "g") }
        assertEquals("qobuz-web", e.extensionId)
    }
}
```

- [ ] **Step 3: Run to verify they fail** — `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.RustEngineTest'; cd ..` → FAIL (`Unresolved reference: RustEngine`).

- [ ] **Step 4: Implement `RustEngine.kt`**

```kotlin
package xyz.losslessmusic.app.engine

import com.zarz.spotiflac.requireSuccessfulExtensionAction
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * NativeEngine on the vendored Rust engine (spec §3.1). Keeps the Go-era contract: throws where Go
 * throws, returns defaults where Go cannot fail (R-P1). Pure JVM (no android.*) so it is unit-tested
 * with FakeRustCore.
 */
class RustEngine(
    private val factory: RustCoreFactory,
    private val filesDir: File,
    private val readyTimeoutMs: Long = DEFAULT_READY_TIMEOUT_MS,
    private val log: (String) -> Unit = {},
) : NativeEngine {
    companion object {
        const val DEFAULT_READY_TIMEOUT_MS = 15_000L
        const val NOT_READY = "engine_not_ready"
        const val MISSING_KEY = "extension storage master key is not configured"
    }

    enum class State { UNINITIALIZED, INITIALIZING, READY, FAILED }

    override val kind = EngineKind.RUST

    private val lock = ReentrantLock()
    private val stateChanged = lock.newCondition()
    @Volatile var state = State.UNINITIALIZED
        private set
    private var failure: String? = null
    private var core: RustCore? = null

    // Recorded init arguments (immutable per process once recorded).
    private var masterKey: String? = null
    private var goExtDir: String? = null
    private var goDataDir: String? = null

    // Buffered configuration (R-P4).
    private val downloadDirs = LinkedHashSet<String>()
    private var downloadPriorityJson: String? = null
    private var metadataPriorityJson: String? = null
    private var fallbackIdsJson: String? = null
    private var coverCacheDir: String? = null
    private var coverLease: AutoCloseable? = null

    // ---------------- init (group 1) ----------------

    override fun setAppVersion(version: String) {
        // Intentionally ignored: the engine always gets EngineVersion.SPOTIFLAC_ENGINE_VERSION.
    }

    override fun setExtensionStorageMasterKey(masterKey: String) = lock.withLock {
        this.masterKey = recorded("masterKey", this.masterKey, masterKey)
    }

    override fun initExtensionSystem(extDir: String, dataDir: String) {
        val args = lock.withLock {
            goExtDir = recorded("extDir", goExtDir, canonical(extDir))
            goDataDir = recorded("dataDir", goDataDir, canonical(dataDir))
            when (state) {
                State.READY -> return
                State.INITIALIZING -> null
                State.UNINITIALIZED, State.FAILED -> {
                    val key = masterKey ?: throw IllegalStateException(MISSING_KEY)
                    state = State.INITIALIZING
                    Triple(goExtDir!!, goDataDir!!, key)
                }
            }
        }
        if (args == null) { requireCore(); return }
        val (ext, data, key) = args
        val created = try {
            val copy = EngineDataIsolation.ensureRustCopy(File(ext), File(data))
            factory.create(copy.extensions.canonicalPath, copy.data.canonicalPath, key, EngineVersion.SPOTIFLAC_ENGINE_VERSION)
        } catch (e: Throwable) {
            fail(e); throw e
        }
        lock.withLock {
            try {
                applyConfig(created)
            } catch (e: Throwable) {
                runCatching { created.close() }
                failLocked(e); throw e
            }
            core = created
            state = State.READY
            failure = null
            stateChanged.signalAll()
        }
    }

    override fun loadExtensionsFromDir(dirPath: String): String {
        val c = requireCore()
        val expected = lock.withLock { goExtDir }
        if (canonical(dirPath) != expected) throw IllegalStateException("Extension source directory does not match the initialized owner")
        return c.loadAll()
    }

    // ---------------- extensions ----------------

    override fun loadExtensionFromPath(path: String): String = requireCore().install(path)
    override fun getInstalledExtensions(): String = requireCore().installed()
    override fun setExtensionEnabled(id: String, enabled: Boolean) = requireCore().setEnabled(id, enabled)
    override fun removeExtension(id: String) = requireCore().remove(id)
    override fun getExtensionSettings(id: String): String = requireCore().settings(id)
    override fun setExtensionSettings(id: String, settingsJson: String) = requireCore().updateSettings(id, settingsJson)
    override fun getExtensionPendingAuth(extensionId: String): String = requireCore().pendingAuthJson(extensionId)
    override fun getExtensionHomeFeed(extensionId: String): String = requireCore().homeFeedJson(extensionId)
    override fun customSearchWithExtension(extensionId: String, query: String, optionsJson: String): String =
        requireCore().customSearchJson(extensionId, query, optionsJson)

    override fun completeSessionGrant(callbackState: String, grant: String): String {
        val c = requireCore()
        val id = try {
            c.resolveCallbackState(callbackState)
        } catch (e: Exception) {
            throw SessionGrantFailure(null, e.message ?: "callback state rejected")
        }
        try {
            c.setSessionGrant(id, grant)
            requireSuccessfulExtensionAction(id, "completeGrant", c.invokeAction(id, "completeGrant"))
        } catch (e: Exception) {
            throw SessionGrantFailure(id, e.message ?: "session grant failed")
        }
        return id
    }

    // ---------------- search / metadata / priorities ----------------

    override fun searchTracks(query: String, limit: Long, includeExtensions: Boolean): String =
        requireCore().searchMetadataProviders(query, limit, includeExtensions)
    override fun handleUrl(url: String): String = requireCore().handleUrlJson(url)
    override fun findUrlHandler(url: String): String =
        try { requireCore().findUrlHandler(url) ?: "" } catch (e: Exception) { log("findUrlHandler: ${e.message}"); "" }
    override fun getProviderMetadata(providerId: String, resourceType: String, resourceId: String): String =
        requireCore().getProviderMetadataJson(providerId, resourceType, resourceId)

    override fun getDownloadPriority(): String = priority("download") { downloadPriorityJson }
    override fun getMetadataPriority(): String = priority("metadata") { metadataPriorityJson }

    override fun setDownloadPriority(priorityJson: String) {
        val ids = RustJson.ids(priorityJson)
        lock.withLock { downloadPriorityJson = priorityJson; core?.takeIf { state == State.READY }?.setProviderPriority("download", ids) }
    }

    override fun setMetadataPriority(priorityJson: String) {
        val ids = RustJson.ids(priorityJson)
        lock.withLock { metadataPriorityJson = priorityJson; core?.takeIf { state == State.READY }?.setProviderPriority("metadata", ids) }
    }

    override fun setDownloadFallbackProviderIds(idsJson: String) {
        val ids = RustJson.idsOrNull(idsJson)
        lock.withLock { fallbackIdsJson = idsJson; core?.takeIf { state == State.READY }?.setFallbackProviders(ids) }
    }

    // ---------------- downloads / files ----------------

    override fun downloadByStrategy(requestJson: String): String {
        val c = requireCore()
        val request = JSONObject(requestJson)
        val outputDir = request.optString("output_dir", "")
        val result = withGrant(c, outputDir) { c.downloadWithPump(requestJson) }
        indexIfSucceeded(c, outputDir, request, result)
        return result
    }

    override fun getAllDownloadProgress(): String {
        val c = coreOrNull() ?: return RustJson.EMPTY_PROGRESS
        return try { c.allProgress() } catch (e: Exception) { log("allProgress: ${e.message}"); RustJson.EMPTY_PROGRESS }
    }

    override fun cancelDownload(itemId: String) {
        val c = coreOrNull() ?: return
        try { c.cancelDownload(itemId) } catch (e: Exception) { log("cancelDownload: ${e.message}") }
    }

    override fun setDownloadDirectory(path: String) = addDownloadDir(path)

    override fun allowDownloadDir(path: String) {
        try { addDownloadDir(path) } catch (e: Exception) { log("allowDownloadDir: ${e.message}") }
    }

    override fun checkDuplicate(outputDir: String, isrc: String): String {
        val c = requireCore()
        return RustJson.duplicate(withGrant(c, outputDir) { c.checkIsrcExists(outputDir, isrc) })
    }

    override fun getAudioQuality(path: String): String {
        val c = requireCore()
        val p = canonical(path)
        return RustJson.audioQuality(withGrant(c, parentOf(p)) { c.readAudioMetadata(p) })
    }

    override fun editFileMetadata(filePath: String, metadataJson: String): String {
        val c = requireCore()
        val p = canonical(filePath)
        return withGrant(c, parentOf(p)) { c.editFileMetadata(p, metadataJson) }
    }

    override fun reEnrichFile(requestJson: String): String {
        val c = requireCore()
        val request = JSONObject(requestJson)
        val raw = request.optString("file_path", "")
        if (raw.isEmpty()) return c.reenrichFile(requestJson)
        val p = if (request.optBoolean("preview_only", false)) raw else canonical(raw).also { request.put("file_path", it) }
        return withGrant(c, parentOf(p)) { c.reenrichFile(request.toString()) }
    }

    override fun getLyricsLRC(spotifyId: String, trackName: String, artistName: String, filePath: String, durationMs: Long): String {
        val c = requireCore()
        if (filePath.isBlank()) return c.getLyricsLrc(spotifyId, trackName, artistName, "", durationMs)
        val p = canonical(filePath)
        return withGrant(c, parentOf(p)) { c.getLyricsLrc(spotifyId, trackName, artistName, p, durationMs) }
    }

    override fun setLibraryCoverCacheDir(cacheDir: String) {
        try {
            lock.withLock {
                coverCacheDir = cacheDir
                core?.takeIf { state == State.READY }?.let { openCoverLease(it, cacheDir) }
            }
        } catch (e: Exception) {
            log("setLibraryCoverCacheDir: ${e.message}")
        }
    }

    override fun scanLibraryFolder(folderPath: String): String {
        val c = requireCore()
        return withGrant(c, folderPath) { c.scanLibraryFolder(folderPath) }
    }

    // ---------------- internals ----------------

    private fun recorded(name: String, current: String?, value: String): String {
        if (current != null && current != value) throw IllegalStateException("already_initialized: $name differs from the value recorded for this process")
        return value
    }

    private fun canonical(path: String): String = File(path).canonicalPath
    private fun parentOf(path: String): String = File(path).parent ?: path

    private fun aliases(path: String): List<String> {
        val f = File(path)
        return listOf(f.canonicalPath, f.absolutePath).distinct()
    }

    private fun allowList(): List<String> {
        val all = LinkedHashSet<String>()
        all += aliases(filesDir.path)
        downloadDirs.forEach { all += aliases(it) }
        return all.toList()
    }

    private fun addDownloadDir(path: String) {
        if (path.isBlank()) return
        lock.withLock {
            downloadDirs += File(path).absolutePath
            core?.takeIf { state == State.READY }?.setAllowedDownloadDirectories(allowList())
        }
    }

    /** Must be called with [lock] held. */
    private fun applyConfig(c: RustCore) {
        c.setAllowedDownloadDirectories(allowList())
        fallbackIdsJson?.let { c.setFallbackProviders(RustJson.idsOrNull(it)) }
        downloadPriorityJson?.let { c.setProviderPriority("download", RustJson.ids(it)) }
        metadataPriorityJson?.let { c.setProviderPriority("metadata", RustJson.ids(it)) }
        coverCacheDir?.let { openCoverLease(c, it) }
    }

    /** Must be called with [lock] held. */
    private fun openCoverLease(c: RustCore, dir: String) {
        val lease = c.grantDownloadDirectories(aliases(dir))
        try {
            c.setLibraryCoverCacheDirectory(dir)
        } catch (e: Exception) {
            lease.close(); throw e
        }
        coverLease?.let { runCatching { it.close() } }
        coverLease = lease
    }

    private fun <T> withGrant(c: RustCore, dir: String, block: () -> T): T {
        if (dir.isBlank()) return block()
        val lease = c.grantDownloadDirectories(aliases(dir))
        try {
            return block()
        } finally {
            runCatching { lease.close() }
        }
    }

    private fun indexIfSucceeded(c: RustCore, outputDir: String, request: JSONObject, result: String) {
        if (outputDir.isBlank()) return
        try {
            val r = JSONObject(result)
            if (!r.optBoolean("success", false)) return
            val filePath = r.optString("file_path", "")
            val isrc = r.optString("isrc", "").ifBlank { request.optString("isrc", "") }
            if (filePath.isNotBlank() && isrc.isNotBlank()) c.addToIsrcIndex(outputDir, isrc, filePath)
        } catch (e: Exception) {
            log("addToIsrcIndex: ${e.message}")
        }
    }

    private fun priority(kind: String, buffered: () -> String?): String {
        val c = coreOrNull() ?: return lock.withLock { buffered() } ?: "[]"
        return RustJson.priorities(c.providerPriorities(), kind)
    }

    private fun coreOrNull(): RustCore? = lock.withLock { core.takeIf { state == State.READY } }

    private fun requireCore(): RustCore = lock.withLock {
        var remaining = TimeUnit.MILLISECONDS.toNanos(readyTimeoutMs)
        while (state != State.READY) {
            if (state == State.FAILED) throw IllegalStateException("$NOT_READY: ${failure ?: "initialization failed"}")
            if (remaining <= 0) throw IllegalStateException("$NOT_READY: timed out waiting for initialization")
            remaining = stateChanged.awaitNanos(remaining)
        }
        core!!
    }

    private fun fail(e: Throwable) = lock.withLock { failLocked(e) }

    private fun failLocked(e: Throwable) {
        state = State.FAILED
        failure = e.message ?: e.javaClass.simpleName
        stateChanged.signalAll()
    }
}
```

- [ ] **Step 5: Run to verify tests pass** — `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.RustEngineTest'; cd ..` → all PASS. If an assertion depends on the fake's recording format (e.g. the `reenrich:` JSON escaping), fix the assertion, not the production semantics, and say so in the report.

- [ ] **Step 6: Wire `RustEngine` into `Engines`**

In `Engines.build`, replace the RUST branch:
```kotlin
        EngineKind.RUST -> RustEngine(UniffiRustCore.FACTORY, filesDir, log = { Log.i("RustEngine", it) })
```

- [ ] **Step 7: Full verification, then commit**

```bash
cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug; cd ..
flutter test
scripts/sync-upstream.sh --check-vendored
git branch --show-current
git add android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustEngine.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/Engines.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/FakeRustCore.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/RustEngineTest.kt
git commit -m "feat(engine): RustEngine adapter behind NativeEngine (selectable per process)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: A/B parity harness

**Files:**
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/ab/JsonShape.kt`, `ab/AbHarness.kt`, `scripts/ab-parity.sh`
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/MainActivity.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/ab/JsonShapeTest.kt`, `ab/AbHarnessTest.kt`

**Interfaces:**
- Consumes: `NativeEngine`, `EngineKind`, `Engines` (Tasks 1, 4).
- Produces:
  - `object JsonShape { fun of(value: Any?): Any; fun parse(raw: String): Any?; fun diff(a: Any, b: Any, path: String = "$"): List<String> }` — shapes: `"string" | "number" | "boolean" | "null"`, `Map<String, Any>` for objects (sorted keys), `List<Any>` = `[union]` for arrays (shape of each element merged: objects merge key sets, differing primitive types become `"mixed"`, empty array → `[]`).
  - `object AbHarness { const val CAPTURE_FLAG = "ab_capture"; const val RESTORE_FLAG = "ab_restore"; const val RECORD_FLAG = "ab_record"; const val COMPARE_FLAG = "ab_compare"; const val FIXTURE_DIR = "ab-fixture"; fun onProcessStart(filesDir: File, log: (String) -> Unit); fun recordIfRequested(filesDir: File, musicDir: File, engine: NativeEngine): Boolean; fun record(engine: NativeEngine, musicDir: File): JSONObject; fun compare(go: JSONObject, rust: JSONObject): JSONObject }`.
- Spec §8: A/B runs are two separate process runs over the same inputs, reset from one immutable snapshot, comparing JSON **shape** (key sets, types), not values.

Harness behaviour:
- `onProcessStart` (called in `MainActivity.onCreate` before `Engines.init`, debug builds only):
  - `ab_capture` present → replace `files/ab-fixture/{extensions,ext_data}` with copies of `files/extensions` and `files/ext_data`; delete the flag.
  - `ab_restore` present → delete `files/extensions`, `files/ext_data`, `files/engine-rust`; copy `files/ab-fixture/*` back to `files/extensions` and `files/ext_data` (the Rust engine re-derives `engine-rust/` from them on init); delete the flag. Missing fixture → log and do nothing.
  - `ab_compare` present and both `files/ab-go.json` and `files/ab-rust.json` exist → write `files/ab-diff.json` = `compare(go, rust)`; delete the flag.
- `recordIfRequested` (called right after `loadExtensionsFromDir` succeeds, on a background thread, debug only): if `ab_record` present → write `files/ab-<go|rust>.json` = `record(engine, musicDir)`; delete the flag; return true.
- `record` runs this fixed read-only script through `engine` and stores, per step, either `{"ok":true,"value":<parsed JSON or string>}` or `{"ok":false,"error":<message>}`:
  `getInstalledExtensions()`, `getDownloadPriority()`, `getMetadataPriority()`, `getExtensionSettings(<first installed id>)`, `getExtensionPendingAuth(<first installed id>)`, `findUrlHandler(SAMPLE_URL)`, `handleUrl(SAMPLE_URL)`, `searchTracks("daft punk one more time", 5, true)`, `getLyricsLRC("", "One More Time", "Daft Punk", "", 320000)`, `checkDuplicate(musicDir, "GBDUW0000059")`, `scanLibraryFolder(musicDir)`, `getAudioQuality(<first .flac under musicDir>)` (skipped with `{"ok":false,"error":"no flac in musicDir"}` if none), `getAllDownloadProgress()`; `SAMPLE_URL = "https://open.spotify.com/track/0DiWol3AO6WpXZgp0goxAV"`. Keys are the method names above.
- `compare` → `{ "<step>": {"status": "same"|"differs"|"go_error"|"rust_error"|"both_error", "diffs": [...paths] , "go_error"?:…, "rust_error"?:… } , "_summary": {"same":N,"differs":N,"errors":N} }`.

- [ ] **Step 1: Write the failing tests**

`android/app/src/test/kotlin/xyz/losslessmusic/app/engine/ab/JsonShapeTest.kt`:
```kotlin
package xyz.losslessmusic.app.engine.ab

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonShapeTest {
    private fun shape(raw: String) = JsonShape.of(JsonShape.parse(raw))

    @Test fun primitivesAndNesting() {
        val s = shape("{\"a\":1,\"b\":\"x\",\"c\":true,\"d\":null,\"e\":{\"f\":[1,2]}}")
        assertEquals(mapOf("a" to "number", "b" to "string", "c" to "boolean", "d" to "null", "e" to mapOf("f" to listOf("number"))), s)
    }

    @Test fun arrayElementShapesAreMerged() {
        assertEquals(listOf(mapOf("id" to "string", "n" to "number")), shape("[{\"id\":\"a\"},{\"id\":\"b\",\"n\":1}]"))
        assertEquals(listOf("mixed"), shape("[1,\"x\"]"))
        assertEquals(emptyList<Any>(), shape("[]"))
    }

    @Test fun sameShapeDifferentValuesHasNoDiff() {
        assertTrue(JsonShape.diff(shape("{\"a\":1,\"b\":[\"x\"]}"), shape("{\"a\":2,\"b\":[\"y\",\"z\"]}")).isEmpty())
    }

    @Test fun missingKeysAndTypeChangesAreReportedWithPaths() {
        val d = JsonShape.diff(shape("{\"a\":1,\"b\":{\"c\":\"x\"}}"), shape("{\"a\":\"1\",\"b\":{},\"z\":true}"))
        assertTrue(d.toString(), d.contains("$.a: number != string"))
        assertTrue(d.toString(), d.contains("$.b.c: missing in rust"))
        assertTrue(d.toString(), d.contains("$.z: missing in go"))
    }

    @Test fun emptyArrayMatchesAnyArray() {
        assertTrue(JsonShape.diff(shape("[]"), shape("[{\"a\":1}]")).isEmpty())
    }
}
```

`android/app/src/test/kotlin/xyz/losslessmusic/app/engine/ab/AbHarnessTest.kt`:
```kotlin
package xyz.losslessmusic.app.engine.ab

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import xyz.losslessmusic.app.engine.EngineKind
import xyz.losslessmusic.app.engine.NativeEngine
import java.io.File
import java.lang.reflect.Proxy

class AbHarnessTest {
    @get:Rule val tmp = TemporaryFolder()

    /** A NativeEngine whose every String method returns [answer(method)]; Unit methods do nothing. */
    private fun engine(kind: EngineKind, answer: (String) -> String): NativeEngine =
        Proxy.newProxyInstance(javaClass.classLoader, arrayOf(NativeEngine::class.java)) { _, m, _ ->
            when {
                m.name == "getKind" -> kind
                m.returnType == String::class.java -> answer(m.name)
                else -> null
            }
        } as NativeEngine

    @Test fun captureThenRestoreResetsGoDirsAndDropsEngineRust() {
        val files = tmp.newFolder("files")
        File(files, "extensions/qobuz/manifest.json").apply { parentFile.mkdirs(); writeText("v1") }
        File(files, "ext_data/x").apply { parentFile.mkdirs(); writeText("d1") }
        File(files, AbHarness.CAPTURE_FLAG).createNewFile()
        AbHarness.onProcessStart(files) {}
        assertFalse(File(files, AbHarness.CAPTURE_FLAG).exists())
        File(files, "extensions/qobuz/manifest.json").writeText("changed")
        File(files, "engine-rust/extensions").mkdirs()
        File(files, AbHarness.RESTORE_FLAG).createNewFile()
        AbHarness.onProcessStart(files) {}
        assertEquals("v1", File(files, "extensions/qobuz/manifest.json").readText())
        assertFalse(File(files, "engine-rust").exists())
        assertFalse(File(files, AbHarness.RESTORE_FLAG).exists())
    }

    @Test fun recordCapturesValuesAndErrors() {
        val music = tmp.newFolder("music")
        val e = engine(EngineKind.GO) { m ->
            if (m == "handleUrl") throw IllegalStateException("no handler") else when (m) {
                "getInstalledExtensions" -> "[{\"id\":\"qobuz-web\"}]"
                "getAllDownloadProgress" -> "{\"items\":{}}"
                else -> "[]"
            }
        }
        val r = AbHarness.record(e, music)
        assertTrue(r.getJSONObject("getInstalledExtensions").getBoolean("ok"))
        assertFalse(r.getJSONObject("handleUrl").getBoolean("ok"))
        assertFalse(r.getJSONObject("getAudioQuality").getBoolean("ok")) // no flac in music dir
    }

    @Test fun recordIfRequestedWritesPerEngineFileAndClearsFlag() {
        val files = tmp.newFolder("files")
        File(files, AbHarness.RECORD_FLAG).createNewFile()
        assertTrue(AbHarness.recordIfRequested(files, tmp.newFolder("m"), engine(EngineKind.RUST) { "[]" }))
        assertTrue(File(files, "ab-rust.json").exists())
        assertFalse(File(files, AbHarness.RECORD_FLAG).exists())
        assertFalse(AbHarness.recordIfRequested(files, tmp.root, engine(EngineKind.RUST) { "[]" }))
    }

    @Test fun compareClassifiesSteps() {
        val go = JSONObject("{\"a\":{\"ok\":true,\"value\":{\"x\":1}},\"b\":{\"ok\":true,\"value\":[1]},\"c\":{\"ok\":false,\"error\":\"e\"}}")
        val rust = JSONObject("{\"a\":{\"ok\":true,\"value\":{\"x\":2}},\"b\":{\"ok\":true,\"value\":[\"s\"]},\"c\":{\"ok\":true,\"value\":1}}")
        val d = AbHarness.compare(go, rust)
        assertEquals("same", d.getJSONObject("a").getString("status"))
        assertEquals("differs", d.getJSONObject("b").getString("status"))
        assertEquals("go_error", d.getJSONObject("c").getString("status"))
        assertEquals(1, d.getJSONObject("_summary").getInt("same"))
    }
}
```

- [ ] **Step 2: Run to verify they fail** — `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.ab.*'; cd ..` → FAIL (unresolved `JsonShape` / `AbHarness`).

- [ ] **Step 3: Implement `JsonShape.kt`**

```kotlin
package xyz.losslessmusic.app.engine.ab

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** JSON *shape* (key sets + types, values ignored) for A/B engine comparison (spec §8). */
object JsonShape {
    fun parse(raw: String): Any? {
        val t = raw.trim()
        if (t.isEmpty()) return ""
        return try { JSONTokener(t).nextValue() } catch (_: Exception) { raw }
    }

    fun of(value: Any?): Any = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().sorted().associateWith { of(value.opt(it)) }
        is JSONArray -> {
            val shapes = (0 until value.length()).map { of(value.opt(it)) }
            if (shapes.isEmpty()) emptyList() else listOf(shapes.reduce(::merge))
        }
        is String -> "string"
        is Boolean -> "boolean"
        is Number -> "number"
        else -> "string"
    }

    @Suppress("UNCHECKED_CAST")
    private fun merge(a: Any, b: Any): Any = when {
        a == b -> a
        a is Map<*, *> && b is Map<*, *> -> {
            val ma = a as Map<String, Any>; val mb = b as Map<String, Any>
            (ma.keys + mb.keys).sorted().associateWith { k ->
                val va = ma[k]; val vb = mb[k]
                if (va != null && vb != null) merge(va, vb) else (va ?: vb)!!
            }
        }
        a is List<*> && b is List<*> -> when {
            a.isEmpty() -> b
            b.isEmpty() -> a
            else -> listOf(merge(a[0]!!, b[0]!!))
        }
        else -> "mixed"
    }

    @Suppress("UNCHECKED_CAST")
    fun diff(a: Any, b: Any, path: String = "$"): List<String> = when {
        a is Map<*, *> && b is Map<*, *> -> {
            val ma = a as Map<String, Any>; val mb = b as Map<String, Any>
            (ma.keys + mb.keys).sorted().flatMap { k ->
                when {
                    k !in mb -> listOf("$path.$k: missing in rust")
                    k !in ma -> listOf("$path.$k: missing in go")
                    else -> diff(ma.getValue(k), mb.getValue(k), "$path.$k")
                }
            }
        }
        a is List<*> && b is List<*> ->
            if (a.isEmpty() || b.isEmpty()) emptyList() else diff(a[0]!!, b[0]!!, "$path[]")
        a == b -> emptyList()
        else -> listOf("$path: ${label(a)} != ${label(b)}")
    }

    private fun label(s: Any): String = when (s) { is Map<*, *> -> "object"; is List<*> -> "array"; else -> s.toString() }
}
```

- [ ] **Step 4: Implement `AbHarness.kt`**

```kotlin
package xyz.losslessmusic.app.engine.ab

import org.json.JSONArray
import org.json.JSONObject
import xyz.losslessmusic.app.engine.EngineKind
import xyz.losslessmusic.app.engine.NativeEngine
import java.io.File

/** Debug-only A/B parity harness driven by flag files in filesDir (see scripts/ab-parity.sh). */
object AbHarness {
    const val CAPTURE_FLAG = "ab_capture"
    const val RESTORE_FLAG = "ab_restore"
    const val RECORD_FLAG = "ab_record"
    const val COMPARE_FLAG = "ab_compare"
    const val FIXTURE_DIR = "ab-fixture"
    const val SAMPLE_URL = "https://open.spotify.com/track/0DiWol3AO6WpXZgp0goxAV"
    private val GO_DIRS = listOf("extensions", "ext_data")

    fun onProcessStart(filesDir: File, log: (String) -> Unit) {
        val fixture = File(filesDir, FIXTURE_DIR)
        consume(filesDir, CAPTURE_FLAG) {
            fixture.deleteRecursively()
            GO_DIRS.forEach { copyOrCreate(File(filesDir, it), File(fixture, it)) }
            log("ab: fixture captured")
        }
        consume(filesDir, RESTORE_FLAG) {
            if (!fixture.isDirectory) { log("ab: no fixture to restore"); return@consume }
            GO_DIRS.forEach { File(filesDir, it).deleteRecursively() }
            File(filesDir, "engine-rust").deleteRecursively()
            GO_DIRS.forEach { copyOrCreate(File(fixture, it), File(filesDir, it)) }
            log("ab: fixture restored")
        }
        consume(filesDir, COMPARE_FLAG) {
            val go = File(filesDir, "ab-go.json"); val rust = File(filesDir, "ab-rust.json")
            if (!go.exists() || !rust.exists()) { log("ab: compare needs ab-go.json and ab-rust.json"); return@consume }
            File(filesDir, "ab-diff.json").writeText(compare(JSONObject(go.readText()), JSONObject(rust.readText())).toString(2))
            log("ab: diff written")
        }
    }

    fun recordIfRequested(filesDir: File, musicDir: File, engine: NativeEngine): Boolean {
        val flag = File(filesDir, RECORD_FLAG)
        if (!flag.exists()) return false
        val name = if (engine.kind == EngineKind.RUST) "ab-rust.json" else "ab-go.json"
        File(filesDir, name).writeText(record(engine, musicDir).toString(2))
        flag.delete()
        return true
    }

    fun record(engine: NativeEngine, musicDir: File): JSONObject {
        val out = JSONObject()
        fun step(name: String, call: () -> String) {
            out.put(name, try {
                JSONObject().put("ok", true).put("value", JsonShape.parse(call()) ?: JSONObject.NULL)
            } catch (e: Throwable) {
                JSONObject().put("ok", false).put("error", "${e.javaClass.simpleName}: ${e.message}")
            })
        }
        step("getInstalledExtensions") { engine.getInstalledExtensions() }
        val firstId = runCatching { JSONArray(engine.getInstalledExtensions()).getJSONObject(0).getString("id") }.getOrDefault("")
        step("getDownloadPriority") { engine.getDownloadPriority() }
        step("getMetadataPriority") { engine.getMetadataPriority() }
        step("getExtensionSettings") { engine.getExtensionSettings(firstId) }
        step("getExtensionPendingAuth") { engine.getExtensionPendingAuth(firstId) }
        step("findUrlHandler") { engine.findUrlHandler(SAMPLE_URL) }
        step("handleUrl") { engine.handleUrl(SAMPLE_URL) }
        step("searchTracks") { engine.searchTracks("daft punk one more time", 5, true) }
        step("getLyricsLRC") { engine.getLyricsLRC("", "One More Time", "Daft Punk", "", 320000) }
        step("checkDuplicate") { engine.checkDuplicate(musicDir.path, "GBDUW0000059") }
        step("scanLibraryFolder") { engine.scanLibraryFolder(musicDir.path) }
        val flac = musicDir.walkTopDown().firstOrNull { it.isFile && it.extension.equals("flac", true) }
        step("getAudioQuality") { flac?.let { engine.getAudioQuality(it.path) } ?: throw IllegalStateException("no flac in musicDir") }
        step("getAllDownloadProgress") { engine.getAllDownloadProgress() }
        return out
    }

    fun compare(go: JSONObject, rust: JSONObject): JSONObject {
        val result = JSONObject()
        var same = 0; var differs = 0; var errors = 0
        (go.keys().asSequence() + rust.keys().asSequence()).toSortedSet().forEach { name ->
            val g = go.optJSONObject(name); val r = rust.optJSONObject(name)
            val gOk = g?.optBoolean("ok") == true; val rOk = r?.optBoolean("ok") == true
            val entry = JSONObject()
            when {
                gOk && rOk -> {
                    val d = JsonShape.diff(JsonShape.of(g!!.opt("value")), JsonShape.of(r!!.opt("value")))
                    entry.put("status", if (d.isEmpty()) "same" else "differs").put("diffs", JSONArray(d))
                    if (d.isEmpty()) same++ else differs++
                }
                !gOk && !rOk -> { entry.put("status", "both_error"); errors++ }
                !gOk -> { entry.put("status", "go_error"); errors++ }
                else -> { entry.put("status", "rust_error"); errors++ }
            }
            g?.optString("error")?.takeIf { it.isNotEmpty() }?.let { entry.put("go_error", it) }
            r?.optString("error")?.takeIf { it.isNotEmpty() }?.let { entry.put("rust_error", it) }
            result.put(name, entry)
        }
        result.put("_summary", JSONObject().put("same", same).put("differs", differs).put("errors", errors))
        return result
    }

    private inline fun consume(filesDir: File, flag: String, action: () -> Unit) {
        val f = File(filesDir, flag)
        if (!f.exists()) return
        try { action() } finally { f.delete() }
    }

    private fun copyOrCreate(source: File, target: File) {
        if (source.isDirectory) source.copyRecursively(target, overwrite = true) else target.mkdirs()
    }
}
```

- [ ] **Step 5: Hook into `MainActivity` (debug only)**

In `onCreate`, before `Engines.init(applicationContext)`:
```kotlin
        if (BuildConfig.DEBUG) AbHarness.onProcessStart(applicationContext.filesDir) { Log.i("AbHarness", it) }
```
In the `loadExtensionsFromDir` branch, after the engine call succeeded (and after the Go-only probe block):
```kotlin
            if (BuildConfig.DEBUG) {
                Thread {
                    runCatching {
                        val music = File(getExternalFilesDir(null) ?: filesDir, "LosslessMusic")
                        if (AbHarness.recordIfRequested(filesDir, music, Engines.current)) Log.i("AbHarness", "recorded ${Engines.kind}")
                    }.onFailure { Log.w("AbHarness", "record failed: ${it.message}") }
                }.apply { isDaemon = true }.start()
            }
```
(`LosslessMusic` under `getExternalFilesDir(null)` is the app's default download dir — `AppDirs.downloadDir()` in Dart.) Add `import xyz.losslessmusic.app.engine.ab.AbHarness`.

- [ ] **Step 6: Create `scripts/ab-parity.sh`**

```bash
#!/usr/bin/env bash
# A/B parity run (spec §8): same fixture, one process per engine, compare JSON shapes on device.
# Usage: scripts/ab-parity.sh [--capture]   (--capture snapshots the current Go data dirs first)
set -euo pipefail
PKG=xyz.losslessmusic.app
RUNAS=(adb shell run-as "$PKG")

launch() {
  adb shell am force-stop "$PKG"
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

wait_for() { # $1 = file under files/, $2 = timeout seconds
  for _ in $(seq 1 "$2"); do
    if "${RUNAS[@]}" test -f "files/$1" 2>/dev/null || "${RUNAS[@]}" ls "files/$1" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  echo "timeout waiting for files/$1" >&2; return 1
}

touch_flag() { "${RUNAS[@]}" touch "files/$1"; }
rm_file() { "${RUNAS[@]}" rm -f "files/$1"; }

if [[ "${1:-}" == "--capture" ]]; then
  touch_flag ab_capture; launch; sleep 8
  echo "fixture captured"
fi

for engine in go rust; do
  rm_file "ab-$engine.json"; rm_file engine_go; rm_file engine_rust
  touch_flag "engine_$engine"; touch_flag ab_restore; touch_flag ab_record
  launch
  wait_for "ab-$engine.json" 180
  echo "recorded $engine"
done

rm_file ab-diff.json; touch_flag ab_compare; launch; wait_for ab-diff.json 30
"${RUNAS[@]}" cat files/ab-diff.json
rm_file engine_go; rm_file engine_rust
```
`chmod +x scripts/ab-parity.sh`. (`test` is not always permitted under `run-as` on older Android; `wait_for` falls back to `ls`.)

- [ ] **Step 7: Run tests, build, vendored check, commit**

```bash
cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug; cd ..
flutter test
scripts/sync-upstream.sh --check-vendored
git branch --show-current
git add android/app/src/main/kotlin/xyz/losslessmusic/app/engine/ab/JsonShape.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/ab/AbHarness.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/ab/JsonShapeTest.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/ab/AbHarnessTest.kt android/app/src/main/kotlin/xyz/losslessmusic/app/MainActivity.kt scripts/ab-parity.sh
git commit -m "feat(engine): device A/B parity harness (fixture reset, record, shape diff)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Device A/B + Rust-mode E2E smoke, flip the debug default (controller + Hoàng's device)

**Files:**
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/Engines.kt` (`DEBUG_DEFAULT = EngineKind.RUST`) — only if the gates below pass
- Create: `docs/migration/phase2-findings.md`

**Interfaces:** consumes everything above; LG V30 with the populated profile (9 extensions, Qobuz/Amazon signed in).

- [ ] **Step 1: Build + install the debug APK over the existing app** (`flutter build apk --debug`, `adb install -r …`).
- [ ] **Step 2: A/B run** — `scripts/ab-parity.sh --capture` → paste `ab-diff.json` summary into the findings doc. Every step must be `same`, or `differs`/`*_error` with a written explanation (e.g. network-variable results, a Go-only field Dart does not read — cite the Dart keys read). A `differs` on a key Dart reads is a bug → fix loop before continuing.
- [ ] **Step 3: Rust-mode E2E smoke** (`adb shell run-as xyz.losslessmusic.app touch files/engine_rust`, restart): extensions list loads (9); search returns results; album/artist page opens; download 1 track each from Qobuz and Amazon (FLAC lands with tags + cover, `.lrc` sidecar if enabled, progress bar moves, notification progress in the foreground service); cancel a download mid-way; duplicate re-download is skipped; library scan lists the files; spectral opens; preview plays; lyrics screen shows lyrics; session expiry → verification browser reopens (if reproducible). DLNA still works (still Go in phase 2). Record pass/fail + evidence per item.
- [ ] **Step 4: Flip the debug default** only if Steps 2–3 pass: `val DEBUG_DEFAULT = EngineKind.RUST` in `Engines.kt`; run `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug; cd ..`, `flutter test`, `scripts/sync-upstream.sh --check-vendored`.
- [ ] **Step 5: Write `docs/migration/phase2-findings.md`** (A/B summary table, E2E checklist with evidence, any divergences + explanation, carry-over to phase 3: PostDownload fixes 1 & 4, signed-session LM-FORK), commit with the flip:
```bash
git add docs/migration/phase2-findings.md android/app/src/main/kotlin/xyz/losslessmusic/app/engine/Engines.kt
git commit -m "feat(engine): Rust is the debug-build default engine (phase 2 exit)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage (§7 phase 2):** Engine interface → Task 1 (`NativeEngine`) + Task 2 (`RustCore`, the fakeable thin interface spec §3.1 asks for); EngineBridge → Task 4 (`RustEngine`); EngineShims already exist (phase 1) and are exercised via `withCoreFFmpegExecution` in Task 2; flag → Tasks 1/4 (process-scoped, R-P6); all 41 `Bridge.*` methods → Task 1 mapping (35 engine methods + 4 bridge-local + session-grant trio folded into `completeSessionGrant`); FFmpeg pump + both download paths → Task 1 (FGService/MainActivity both call `Engines.current.downloadByStrategy`) + Task 2 (`downloadWithPump`); A/B parity with deterministic reset → Task 5; init state machine → Task 4; data isolation → Task 4 (`ensureRustCopy`) + Task 1 (probe only on Go).
- **Deliberately not in phase 2:** PostDownload fixes 1 & 4 and the Rust LM-FORK (phase 3); DLNA port (phase 4); Go removal (phase 5).
- **Known risk carried from research:** Rust `readAudioMetadata` / library scan use camelCase — `scanLibraryFolder` is passed through unchanged (Go's `LibraryScanResult` is already camelCase); the A/B run is the gate that proves it.

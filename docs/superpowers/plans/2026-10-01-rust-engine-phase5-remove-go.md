# Rust Engine Migration — Phase 5 (Remove Go & Retool) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship only the Rust engine. Delete the Go engine, gomobile bridge, Go DLNA server and Go-only tooling. Replace the bridge-contract snapshot with an engine-contract snapshot. Update docs, and keep a buildable Go rollback branch.

**Architecture:** `Engines` always builds `RustEngine` (release included). Go-era selection, probe and A/B code is deleted, and `MainActivity` loses every `Bridge.*` call. DLNA is always the Kotlin server. The `ping` channel method answers `"pong"` in Kotlin. Then the Go trees and AAR are removed, the build scripts and docs are retooled, and a new `scripts/snapshot-engine-contract.sh` guards the UniFFI surface our glue calls.

**Tech Stack:** Kotlin/JVM tests, Gradle, Flutter, bash, UniFFI bindings, adb (controller only).

**Spec:** `docs/superpowers/specs/2026-09-25-rust-engine-migration-design.md`: §6 (Go removal, contract snapshot, rollback, build prerequisites), §7 phase 5, §10 success criteria. Phase-4 gate evidence: `docs/migration/phase4-e2e.md` (gate MET).

## Rulings made while planning

- **R-P1 Keep `NativeEngine`; drop `EngineKind`.** `NativeEngine` is the type every caller holds (`Engines.current`, `MainActivity`, `DownloadForegroundService`, `RustEngine`), so keeping it keeps the diff small. `kind`, `EngineKind`, `EngineSelection` and the flag files go, because they only exist to choose Go.
- **R-P2 Keep `EngineDataIsolation`.** Release users upgrading from Go-era builds (v0.9.x/v0.10.0) still need the one-time copy of Go-era extension data into `filesDir/engine-rust/`. That is now the release upgrade path.
- **R-P3 Do not edit `.gitignore`.** Spec §6 asks to remove the `.gomobile` ignore, but `.gitignore` carries Hoàng's uncommitted edit. A stale ignore line is harmless, so it is recorded as a follow-up.
- **R-P4 `bridge_appversion_test.go` is already replaced.** Its guard ("engine sees the vendored SpotiFLAC version, not the fork's 0.x") is pinned by `RustEngineTest.setAppVersionIsIgnored` and `EngineDataIsolationTest.engineVersionIsTheVendoredBaseline`. Task 3 records this mapping and adds no new test.
- **R-P5 Release command builds arm64 only.** `.claude/commands/release.md` switches to `flutter build apk --release --target-platform android-arm64`. This is phase-4 follow-up (b): about 17 MB of dead non-arm64 libraries, and v7a installs that cannot load the engine.
- **R-P6 The rollback branch is created by the controller** (git) before any deletion lands: `release/0.9.x-go` from `bee1943e`.

## Global Constraints

- Branch `feat/rust-engine-phase5` from `main` 4b9e6d4f. Codex never runs mutating git: deleted files are removed with `rm`, and the controller stages them. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never touch: `.gitignore`, `docs/testing.md`, `android/.kotlin/`, `gemini_fix/` (Hoàng's).
- Layer 1 stays byte-identical except registered forks: `rust_backend/**`, `scripts/build_rust_backend.sh`, `android/app/src/main/kotlin/com/zarz/spotiflac/CoreBackend.kt`. `scripts/sync-upstream.sh --check-vendored` must pass.
- Never `grep -r`/`find` over `rust_backend/` (4.3 GB target dir). Use `git grep`.
- Channel method names and argument names are unchanged. Existing Dart unit tests (`test/`) pass unmodified (436). Kotlin tests for deleted Go-only code are deleted together with that code.
- After phase 5, the APK (debug and release) must contain no `libgojni.so` and no `xyz.losslessmusic.backend.bridge` classes (spec §10.1).
- Gradle: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`, run from `android/`.

## Review Focus

1. **Release build silently still Go:** a release (non-debug) process must log `engine=RUST`. Pinned in Task 1 (`releaseBuildUsesRust` test on the selection/init path).
2. **Upgrade from a Go-era install:** first launch must copy the Go-era extension data into `engine-rust/` exactly once. `EngineDataIsolationTest` must stay green and is not edited (Task 1 verification).
3. **Dangling references after deletion:** no `Bridge`, `GoEngine`, `gobackend` or `libgojni` symbol may remain in code or build files. Pinned in Task 3 by a scripted `git grep` gate.
4. **`ping`/integration contract:** the `ping` channel method still returns `"pong"` (integration_test/native_bridge_test.dart). Pinned in Task 1.
5. **Contract drift goes unnoticed on the next sync:** a changed UniFFI signature we call must fail `snapshot-engine-contract.sh --check`. Pinned in Task 4 (a negative test that mutates a copy of the snapshot).

---

### Task 1: Kotlin glue is Rust-only

**Files:**
- Delete: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/GoEngine.kt`, `RustEngineProbe.kt`, `RustProbeStartGate.kt`, `ab/AbHarness.kt`, `ab/JsonShape.kt`; tests `EngineSelectionTest.kt`, `RustEngineProbeTest.kt`, `RustProbeStartGateTest.kt`, `ab/AbHarnessTest.kt`, `ab/JsonShapeTest.kt`; `scripts/ab-parity.sh`
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/NativeEngine.kt` (remove `EngineKind` and `val kind`), `Engines.kt`, `RustEngine.kt` (remove `override val kind`), `android/app/src/main/kotlin/xyz/losslessmusic/app/MainActivity.kt`, `android/app/src/main/kotlin/xyz/losslessmusic/app/DownloadForegroundService.kt` (only if it references `kind`)
- Move: `go_backend/testdata/silence.flac` → `android/app/src/test/resources/silence.flac` (copy now; Task 3 deletes `go_backend/`). Update `UniffiRustCoreTest.kt` to the new path. This is a path-only test edit.
- Create: `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/EnginesTest.kt`

**Interfaces:** Produces `object Engines { fun init(context: Context); val current: NativeEngine }`, always a `RustEngine`. There is no `EngineKind` or `Engines.kind`.

- [ ] **Step 1: Write the failing test.** Extract the pure builder so it is testable without Android. Keep `init(context)` for callers:
```kotlin
// EnginesTest.kt
class EnginesTest {
    @get:Rule val tmp = org.junit.rules.TemporaryFolder()
    @Test fun releaseBuildUsesRust() {
        val engine = Engines.build(tmp.root, log = {})
        assertTrue(engine is RustEngine)
    }
    @Test fun goFlagFileIsIgnored() {
        File(tmp.root, "engine_go").writeText("")
        assertTrue(Engines.build(tmp.root, log = {}) is RustEngine)
    }
}
```
- [ ] **Step 2: Run it and confirm it fails.** `./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.EnginesTest'`. Expected: compile error (no `Engines.build`).
- [ ] **Step 3: Implement.**
  - `Engines.kt`: delete `EngineSelection` and `DEBUG_DEFAULT`, and add `internal fun build(filesDir: File, log: (String) -> Unit): NativeEngine = RustEngine(UniffiRustCore.FACTORY, filesDir, log = log)`. `init` calls `build(files) { Log.i("RustEngine", it) }` and logs `engine=RUST`.
  - Remove `kind` and `EngineKind` from `NativeEngine.kt` and `RustEngine.kt`.
  - `MainActivity.kt`:
    - Remove the imports of `Bridge`, `EngineKind`, `RustEngineProbe`, `RustProbeStartGate` and `AbHarness`.
    - Remove `probeStartGate`, the `AbHarness.onProcessStart`/`recordIfRequested` calls, and the `Engines.kind == EngineKind.GO` probe block.
    - `"ping" -> true to "pong"`.
    - In the media-server cases, keep only the Kotlin DLNA branch.
    - In `onDestroy`, drop the Go `releaseMulticastLock()` branch, and drop the Go-only `multicastLock`/`acquireMulticastLock`/`releaseMulticastLock`/`wifiLanIpv4` helpers if they become unused. The Kotlin DLNA path has its own lock helpers; keep whatever it calls.
  - Delete the files listed above. Copy the fixture and update `UniffiRustCoreTest.kt`, using the same relative-path style the test already uses (`src/test/resources/silence.flac` from the Gradle module dir).
- [ ] **Step 4: Run the tests and confirm they pass.** Run `EnginesTest`, then the full `./gradlew :app:testDebugUnitTest :app:assembleDebug`, then `flutter test` (436, unmodified). `EngineDataIsolationTest` must pass unedited (Review Focus 2). Run `git grep -n -E "EngineKind|GoEngine|AbHarness|RustEngineProbe|RustProbeStartGate|EngineSelection|Bridge\." -- android/app/src` and expect no hits.
- [ ] **Step 5 (controller): commit** `feat(engine): Kotlin glue is Rust-only (release included)`.

---

### Task 2: Rollback branch (controller only)

- [ ] `git branch release/0.9.x-go bee1943e` (verify `git log -1 bee1943e` is the v0.9.1 release commit first). Do not push.
- [ ] Record the branch and its purpose in `docs/UPSTREAM-SYNC.md` (Task 4 writes the section) and in the phase-5 findings.

---

### Task 3: Delete Go and retool the build

**Files:**
- Delete (with `rm -rf`): `go_backend/`, `native/` (bridge + server), `android/app/libs/gobackend.aar` and `android/app/libs/gobackend-sources.jar` (local build outputs), `android/app/src/test/resources/lyrics_usability_cases.tsv` (only docs reference it)
- Modify: `android/app/build.gradle.kts` (remove the `fileTree(... "*.aar")` dependency line ~113 and the gomobile comment ~56; keep `abiFilters`), `scripts/build_android.sh` (remove the gomobile/Go section ~32-48; keep everything else working), `.claude/commands/release.md` (R-P5), `integration_test/extension_engine_test.dart` (Go-behaviour comments/assertions → Rust engine semantics)
- Test: the gates below

- [ ] **Step 1:** Read `scripts/build_android.sh` fully and `integration_test/extension_engine_test.dart`. Note every Go-specific line. For the integration test, check each assertion against the Rust engine's behaviour: read the relevant code in `rust_backend/crates/extensions` via `git grep`. Keep the assertions that still hold. For any that changed, rewrite it to the Rust behaviour and cite the Rust file:line in a comment.
- [ ] **Step 2:** Make the deletions and edits. In `release.md`, change step 3 to `flutter build apk --release --target-platform android-arm64` and add one line explaining why (the engine is arm64-only).
- [ ] **Step 3 (gates):**
```bash
git grep -n -i -E "gobackend|libgojni|gomobile|xyz\.losslessmusic\.backend\.bridge|native/bridge|native/server" -- . ':!docs' ':!.gitignore'   # expect: no hits
(cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug)
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep -E "libgojni|backend/bridge" ; echo "gojni-check-exit=$?"   # expect exit 1 (no match)
flutter test
flutter build apk --release --target-platform android-arm64 && unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -c -E "libgojni" # expect 0
scripts/sync-upstream.sh --check-vendored
```
  Also confirm `bash scripts/build_android.sh` (or its documented debug invocation) still runs end to end without Go installed in PATH. If it needs device flags, run only its build portion and report.
- [ ] **Step 4:** In the report, record R-P4: `bridge_appversion_test.go` is superseded by `RustEngineTest.setAppVersionIsIgnored` + `EngineDataIsolationTest.engineVersionIsTheVendoredBaseline`.
- [ ] **Step 5 (controller): commit** `chore(engine): remove the Go engine, gomobile bridge and Go DLNA server` (the controller stages the deletions).

---

### Task 4: Engine-contract snapshot + sync tooling + UPSTREAM-SYNC.md

**Files:**
- Create: `scripts/snapshot-engine-contract.sh`, `docs/engine-contract.txt`
- Delete: `scripts/snapshot-bridge-contract.sh`, `docs/bridge-contract.txt`
- Modify: `scripts/sync-upstream.sh` (remove the frozen-Go comments; add the contract check to the "Next steps" verify list), `docs/UPSTREAM-SYNC.md`

**Contract script spec (spec §6):**
- Collect every UniFFI method our glue calls. These are calls on `manager.`/`environment.`/bindings objects inside `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/UniffiRustCore.kt`, plus any other file under `android/app/src/main/kotlin/xyz/losslessmusic/app/` that imports `com.spotiflac.backend`.
- For each called name, extract the matching Kotlin binding signature line from `rust_backend/target/bindings/kotlin/com/spotiflac/backend/spotiflac_mobile.kt`. Read only that single file, never grep the target tree. Normalize whitespace and backticks, and include the parameter list + return type.
- Then extract the matching `pub fn <snake_case_name>(` signature (through `)` and the return type) from `rust_backend/crates/mobile/src/*.rs` using `git grep -n -A6`. The camelCase → snake_case mapping is UniFFI's.
- Write sorted lines `<kotlinName> | <kotlin signature> | <rust signature>` to `docs/engine-contract.txt`. `--check` regenerates to a temp file and `diff -u` against the committed file (exit 1 on drift). Missing bindings file → clear error telling the user to run `./gradlew :app:buildRustBackend`.

- [ ] **Step 1: Write the negative test first** as `scripts/test-snapshot-engine-contract.sh`:
  1. Run `snapshot-engine-contract.sh --check` on a clean tree and expect exit 0.
  2. Copy `docs/engine-contract.txt` to a temp dir, alter one signature in the copy, and run the checker against the copy (support `CONTRACT_FILE=<path>` env override). Expect exit 1 and a diff that mentions the altered name.
- [ ] **Step 2:** Implement the script. Generate `docs/engine-contract.txt`. Run the test script (both cases pass).
- [ ] **Step 3: `docs/UPSTREAM-SYNC.md`:**
  - Move the "Go divergence registry (frozen)" and the "Bridge contract surface (historical Go era)" sections under one heading, "## Go engine (removed in phase 5, 2026-10)". Keep them short: one paragraph plus the rollback branch `release/0.9.x-go` (from `bee1943e`, kept buildable for one release cycle for hotfix APKs).
  - Add "## Engine contract check" (how to run the script, and that Kotlin compilation stays the authoritative net).
  - Add "## Required call order (RustEngine init)". Write the exact constructor-argument + init order as implemented in `RustEngine.kt`/`UniffiRustCore.kt`: read them and write it as a numbered checklist (e.g. master key → environment → manager creation with app version → load extensions → priorities re-applied).
  - In the sync protocol, add `scripts/snapshot-engine-contract.sh --check` after the verify step.
- [ ] **Step 4:** `scripts/sync-upstream.sh v5.0.6` (preview) must report no upstream changes in inherited paths (the baseline is already v5.0.6). Then `scripts/sync-upstream.sh --check-vendored` and `bash scripts/test-snapshot-engine-contract.sh`.
- [ ] **Step 5 (controller): commit** `chore(sync): engine-contract snapshot replaces the Go bridge contract`.

---

### Task 5: Docs and stale Go references

**Files:**
- Modify: `CLAUDE.md` ("Upstream Inheritance Protocol": the inherited engine is `rust_backend/` + `scripts/build_rust_backend.sh` + `CoreBackend.kt`; LM-FORK syntax `// LM-FORK(<id>): …`; drop the `go_backend/`/`native/bridge` rules and the `bridge.go`/`backend_bridge.dart` export-signature note, replacing it with "if a UniFFI signature we call changes, update `UniffiRustCore.kt` and re-run `scripts/snapshot-engine-contract.sh`"), `README.md`, `docs/SETUP.md`, `docs/build-prerequisites.md` (spec §6 build prerequisites: rustup + `rust-toolchain.toml`, target `aarch64-linux-android`, NDK 29.0.14206865, `--locked`; remove the Go/gomobile prerequisites)
- Modify comments only (no logic): `android/app/src/main/AndroidManifest.xml:101`, `DownloadForegroundService.kt` (~342, 360, 546), `MainActivity.kt` (~138, 149), `Mp4FlacUnwrapper.kt` (~16, 156), `NonFlacMetadataEmbedder.kt:17`, `engine/PostDownload.kt:7`, `lib/services/container_remux_service.dart:12`, `lib/utils/extension_auth_launcher.dart:12`, `lib/utils/extension_verification_coordinator.dart:17`, `lib/providers/download_dir_provider.dart:64`. Replace dead `go_backend/...` pointers with the equivalent `rust_backend/...` file (find it with `git grep`), or with engine-neutral wording when there is no equivalent.

- [ ] **Step 1:** Make the edits. Keep each comment's meaning, and fix it only where the old wording is now wrong (e.g. "go_backend already tagged it" → "the engine already tagged it").
- [ ] **Step 2 (gate):** `git grep -n -i -E "go_backend|gomobile|gobackend|native/bridge" -- . ':!docs/superpowers' ':!docs/migration' ':!.gitignore' ':!docs/UPSTREAM-SYNC.md'` → expect no hits. In UPSTREAM-SYNC.md, hits are allowed only inside the "removed in phase 5" section.
- [ ] **Step 3:** `./gradlew :app:testDebugUnitTest :app:assembleDebug`, `flutter test`, `flutter analyze` on the touched Dart files.
- [ ] **Step 4 (controller): commit** `docs: Rust-only engine — update protocol, setup and stale Go references`.

---

### Task 6: Device smoke + findings (controller)

- [ ] Build and install the debug APK on the V30 (no uninstall: the debug signature is unchanged). Smoke test:
  - logcat `engine=RUST`
  - extensions load (9)
  - search returns results
  - one Qobuz FLAC download: `flac -t`, tags, lyrics
  - Server tab start → Mac `dlna_probe.py` discovers it and Range returns 206
  - stop
- [ ] Record the release arm64 APK size and confirm no `libgojni` is present (from Task 3).
- [ ] Write `docs/migration/phase5-findings.md`: what was removed, the rollback branch, the contract snapshot, smoke evidence, follow-ups (stale `.gomobile` ignore in `.gitignore` per R-P3; phase-4 follow-ups a/c/d carried forward). Commit `docs(migration): phase 5 findings`.
- [ ] Update memory: extension-gate memory (the version now comes from `EngineVersion.SPOTIFLAC_ENGINE_VERSION`, bumped on sync), the obsolete Go `net.Interfaces` memory (mark it historical; the Kotlin DLNA binds via `NetworkInterface.getByInetAddress`), and the migration status.

## Self-review notes

- **Spec §6 coverage:**
  - Delete `go_backend/`, `native/bridge/`, `native/server/`, gomobile steps, `gobackend.aar`, the engine flag and Go-only fixtures → Tasks 1 and 3.
  - `.gomobile` ignore → deferred (R-P3).
  - `integration_test/extension_engine_test.dart` → Task 3.
  - `bridge_appversion_test.go` → R-P4.
  - UPSTREAM-SYNC.md and CLAUDE.md → Tasks 4 and 5.
  - Extension-gate memory → Task 6.
  - Contract snapshot → Task 4.
  - Rollback branch → Task 2.
  - Build prerequisites → Task 5.
- **§10:** criterion 1 (no Go) → Task 3 gates. Criterion 2 → every task. Criterion 4 (`sync-upstream.sh` reports no changes) → Task 4, at baseline v5.0.6. Criterion 5 → unchanged (both forks active, PRs #609/#610 sent).

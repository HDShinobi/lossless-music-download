# Upstream Inheritance & Sync — Mornye (formerly SpotiFLAC)

This fork **inherits** the Rust engine from
[Mornye](https://github.com/mornyeapp/Mornye), the renamed SpotiFLAC-Mobile
(renamed in v5.2.5–v5.2.6: crates `spotiflac-*` → `mornye-*`, UniFFI package
`com.mornye.backend`, Kotlin package `com.zarz.mornye`, callback scheme
`mornye://`). Since **v5.2.6 the engine is LGPL-3.0-only** (was MIT); see
[`LICENSE-LGPL-3.0`](../LICENSE-LGPL-3.0) and the README license section. The goal
is to absorb upstream updates with minimal effort. This doc is the single
source of truth for *what we inherit, what we changed, and how to sync*.

> There is **no shared git history** with upstream (this repo was created fresh
> and SpotiFLAC code was copied in). So we cannot `git merge upstream/main`.
> Instead we sync via a **baseline tag + 3-way diff** (`scripts/sync-upstream.sh`).

---

## Current baseline

| | |
| --- | --- |
| Baseline tag | `vendor/spotiflac-base` |
| Synced to | **v5.3.1** (commit `e7a8f754`) — Rust engine (`rust_backend/`) |
| Engine | Rust only since phase 5 (2026-10); Go rollback details below. |
| Upstream remote | `upstream` → `https://github.com/mornyeapp/Mornye.git` (old `spotiflacapp/SpotiFLAC-Mobile` URL redirects; tags can also be fetched from the local clone `../Mornye`) |
| Last sync | 2026-11-06 (v5.0.7 → v5.3.1, 931 files / +106.8k −7.7k in inherited paths; includes the Mornye rename and the MIT → LGPL-3.0 relicense). New crates `cast`, `desktop`, `link` are in the workspace but only `mornye-mobile` is built for Android. Forks: `signed-session-mint` **retired** — upstream merged it (`on_mint_failure`, PR #610). `publish-noreplace-fallback` **moved** from `files.rs` to `files/unix.rs`: upstream now falls back to `hard_link` when NOREPLACE is unsupported, but Android 9 sdcardfs also rejects `link()`, so our fork keeps a final stat-then-rename step. `isrc-index-bridge` kept (`spotiflac_core` → `mornye_core`). Glue: imports `com.mornye.backend` → `com.mornye.backend`, `com.zarz.spotiflac` → `com.zarz.mornye` (incl. `EngineShims.kt`), `libmornye_mobile`, `MORNYE_RUST_ANDROID_ABIS`, NDK 29 → 30.0.16248370, Rust 1.98.1 → 1.99.1; manifest + `MainActivity` accept `mornye://session-grant` as well as `spotiflac://`. `SPOTIFLAC_ENGINE_VERSION` 5.0.7 → 5.3.1. `cargo test -p mornye-mobile` needs upstream `test/fixtures` (not vendored): copied temporarily from `../Mornye` at v5.3.1 → 145/145 pass, then removed. Flutter: 436 pass + 1 pre-existing macOS golden diff (`search_screen`, 0.09%; same on pre-sync `ea86f8e6`). WATCHED (99 files, +12.4k −8.8k) reviewed: upstream `SelectedCoreBackend.kt` init is unchanged in what we mirror (`withLyricsSettings` args/order, app-private dir in the allow-list, `shutdown()` before `close()`); its media workspace moved to `noBackupFilesDir/native-media-work` (our glue keeps its own staging). `build.gradle.kts`: only the ABI env rename + NDK 30 pin apply to us; `libmornye_mobile.so` needs only libc/libm/libdl. Not ported (upstream app features we don't ship): player widget, USB bit-perfect, Cast, SAF scan rework, native history store, finalizer split, `platform_bridge.dart` changes. |
| Prior sync | 2026-10-08 (v5.0.6 → v5.0.7, 52 files in inherited paths). Engine: library scan pause/resume and perf, artist tag mode, library cover thumbnails, chunked-download optimizations, and `fe88048d` (retire native bridge entry points upstream Dart no longer calls). That commit removed UniFFI `checkIsrcExists`/`addToIsrcIndex` and `scanLibraryFolder`, which our glue used: the ISRC pair is restored by owned fork `isrc-index-bridge` over the `IndexCache` upstream still keeps (JS SDK + post-download indexing); `scanLibraryFolder` now calls `scanLibraryFolderIncremental(folder, "{}")` and returns its `scanned` array. `CoreBackend.kt`: `scanLibraryFolder` removed, `pauseLibraryScan`/`resumeLibraryScan` added; nothing of ours implements it. 3-way apply clean, no conflicts; PRs #609/#610 not yet in this release. `SPOTIFLAC_ENGINE_VERSION` 5.0.6 → 5.0.7. WATCHED, not ported: `BackgroundWorkService` (replaces upstream `DownloadService`), SAF scan rework, `NativeFinalizationPolicy`, `platform_bridge.dart` removals. Verified: cargo test 66/66, Gradle buildRustBackend + unit tests + assembleDebug, Flutter 436/436, engine contract refreshed. |
| Older sync | 2026-09-29 (v5.0.0 → v5.0.6, 369 files in inherited paths, mostly the newly vendored `rustix-1.1.4` crate). Engine: Hi-Res authenticity check (`core/media/hires`, `mobile/hires.rs`), USB audio transport (`mobile/usb_audio`), lyrics payload/eLRC fixes, tag-writer and ReplayGain-removal work, provider-metadata fixes, and `1d53609b` (avoid blocked `statx` probes on legacy ARM32 devices via vendored rustix). `CoreBackend.kt` gained one interface method (`checkHiResAuthenticity`); nothing of ours implements that interface. **3-way apply clean, no conflicts; both Rust forks (`publish-noreplace-fallback`, `signed-session-mint`) untouched upstream.** `SPOTIFLAC_ENGINE_VERSION` 5.0.0 → 5.0.6. WATCHED, not ported: upstream's own `NativeDownloadFinalizer` fixes (`4c2c3567` mislabeled-MP4 detection, `e61e54f9` metadata prep) — our finalizer path is our own; player features (USB bit-perfect, DSD, AAudio hi-res, home-screen widget), Discord removal, `platform_bridge.dart` additions. Verified: cargo test 68/68, Gradle buildRustBackend + unit tests + assembleDebug, Flutter 433/433. |

> Record **commit** SHAs here, not tag-object SHAs. Upstream re-tags releases —
> `v4.7.1` resolves to different tag objects in different clones (the old
> `a493200a` in this table was one), so always compare with `<tag>^{commit}`.

`vendor/spotiflac-base` always points at the exact upstream commit our
inherited code currently matches. **Advance it only after a sync builds and
tests green** (see protocol below).

---

## What we inherit vs. what is ours

| Path | Relationship | Sync policy |
| --- | --- | --- |
| `rust_backend/`, `scripts/build_rust_backend.sh`, `android/app/src/main/kotlin/com/zarz/mornye/CoreBackend.kt` | **Inherited (Layer 1)** — byte-identical to upstream except registered `LM-FORK(<id>)` blocks | 3-way sync via script; `--check-vendored` guard |
| `lib/` | **Ours** — fresh Flutter rebuild (0 files match upstream) | Follow upstream *patterns/contracts*, do NOT merge files |
| `android/app/src/main/kotlin/xyz/losslessmusic/app/` | **Ours** — Kotlin glue over UniFFI, engine lifecycle, and Android services | Port relevant WATCHED changes by hand; compile Kotlin and check the engine contract |
| `landing/`, `branding/`, `docs/` | **Ours** — not in upstream | n/a |

The `INHERIT_PATHS` array in
[`scripts/sync-upstream.sh`](../scripts/sync-upstream.sh) is the authoritative
list of synced files; `WATCH_PATHS` lists upstream glue to review and port by hand.
Keep this table and those arrays in agreement.

---

## Rust divergence registry

Active forks use a row beginning ``| `LM-FORK(<id>)` |``; retired ones ``| ~~`LM-FORK(<id>)`~~ |``.
`scripts/sync-upstream.sh --check-vendored` requires the set of ids found in Layer 1 to equal the
active rows here.

| Fork id | File(s) | What & why | Upstream PR |
| --- | --- | --- | --- |
| `LM-FORK(publish-noreplace-fallback)` | `rust_backend/crates/extensions/src/files/unix.rs` | Upstream (v5.3.x) handles NOREPLACE `EINVAL`/`NOSYS`/`OPNOTSUPP`/`NOTSUP` by `hard_link` + unlink. Android 9 sdcardfs rejects `link()` too, so when the link fails with anything but `EEXIST` we check the destination without following symlinks and plain-rename only when absent (caller holds the destination lock). | Upstream PR [#609](https://github.com/spotiflacapp/SpotiFLAC-Mobile/pull/609) superseded by upstream's hard-link fallback, which is not enough: verified 2026-11-07 on LG V30 (Android 9, `/storage/emulated` = sdcardfs) that `ln` fails with EPERM, and `mornye-extensions` `files::` tests cross-built for aarch64 pass on sdcardfs (incl. `unsupported_exclusive_rename_publishes_complete_audio_without_copying`, which only passes via this fork). Keep while Android 9 is supported |
| ~~`LM-FORK(signed-session-mint)`~~ | `rust_backend/crates/extensions/src/signed_session/fetch.rs` | Retired 2026-11-06: upstream merged it as `on_mint_failure` (v5.3.x). | [#610](https://github.com/spotiflacapp/SpotiFLAC-Mobile/pull/610) merged |
| `LM-FORK(isrc-index-bridge)` | `rust_backend/crates/extensions/src/environment.rs`, `rust_backend/crates/mobile/src/lib.rs` (one `mod` line each); owned `environment/lm_isrc_index.rs`, `mobile/src/lm_isrc_index.rs` | Upstream `fe88048d` (v5.0.7) retired UniFFI `checkIsrcExists`/`addToIsrcIndex`; our download duplicate preflight (Dart queue + `DownloadForegroundService`) still uses them. Re-exports both over the `IndexCache` upstream keeps. If upstream deletes `IndexCache`, move the check to Kotlin or a history DB. | Not upstreamable (upstream removed the API on purpose); retire when our duplicate check moves off it |

### Our shims for inherited files (not forks)

| File | Why |
| --- | --- |
| `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/EngineShims.kt` | Declares `com.zarz.mornye.NativeDownloadFinalizer.runFFmpegArguments` (our ffmpeg-kit) and `com.zarz.mornye.BuildConfig.APPLICATION_ID` so vendored `CoreBackend.kt` compiles unchanged. If upstream changes that contract, the build fails here. |

---

## Go engine (removed in phase 5, 2026-10)

The Go divergence registry and bridge-contract snapshot are historical: phase 5
removed `go_backend/`, `native/`, and the Go snapshot tooling. Their final source
and registry remain on rollback branch `release/0.9.x-go` (from `bee1943e`), kept
buildable for one release cycle for hotfix APKs. The branch can be recreated
from `bee1943e`, which is on `main`. A hotfix APK built from `release/0.9.x-go`
must use a build number higher than the installed Rust release; otherwise Android
blocks the install as a downgrade. Current upstream syncs cover the Rust engine.

---

## The golden rules (keep sync cheap)

1. **Prefer new files over editing upstream files.** New feature in the engine?
   Add an owned file alongside `rust_backend/` where possible; new files avoid
   in-place conflicts in inherited Layer 1.
2. **If you MUST edit an upstream file**, keep the change minimal, wrap it in
   `// LM-FORK(<id>): <why>` … `// END LM-FORK`, and add one active row per id
   to the Rust divergence registry above.
3. **Never reformat or reorder** upstream files — it turns a 1-line change into
   a whole-file conflict.
4. **Keep our Kotlin glue in step with Rust engine API changes.** Adapt our
   glue around `CoreBackend.kt` and generated bindings.
5. **`lib/` is ours** — there we follow SpotiFLAC's data models, API contracts,
   and queue/download semantics, but write our own widgets/screens.

---

## Sync protocol

> **Do not trust the preview's "Clean — applies without conflicts."**
> The dry run uses `git apply --3way --check`, which does not fully simulate the
> real apply: the v4.8.0 sync was reported clean and then conflicted on
> `extension_providers.go`. Treat the preview as a size estimate only, and always
> run step 3 after `--apply`.
>
> Also note the preview can be *pessimistic* in the other direction: a plain
> `git apply --check` (no `--3way`) rejects any file we edited in place, which
> looks alarming but only reflects our registry divergences.

```bash
# 1. Preview what an upstream release changes in Layer 1 and WATCHED paths
scripts/sync-upstream.sh v5.1.0            # or: scripts/sync-upstream.sh  (= upstream/main)

# 2. Apply the 3-way merge
scripts/sync-upstream.sh v5.1.0 --apply

# 3. Resolve conflicts, keeping registered LM-FORK(<id>) intent where needed
git grep -n '<<<<<<<' -- rust_backend/ scripts/build_rust_backend.sh android/app/src/main/kotlin/com/zarz/mornye/CoreBackend.kt

# 4. Bump SPOTIFLAC_ENGINE_VERSION in EngineVersion.kt to the target version

# 5. Verify
(cd rust_backend && cargo test --locked -p mornye-extensions)
# mornye-mobile tests need upstream fixtures; copy them in temporarily:
#   mkdir test/fixtures && for f in $(git -C ../Mornye ls-tree --name-only <tag> test/fixtures/); do git -C ../Mornye show <tag>:$f > $f; done
#   (cd rust_backend && cargo test --locked -p mornye-mobile); rm -rf test/fixtures
(cd android && ./gradlew :app:buildRustBackend :app:testDebugUnitTest :app:assembleDebug)
flutter test
scripts/snapshot-engine-contract.sh --check

# 6. Review the WATCHED diff-stat from the preview and port relevant glue changes

# 7. Advance the baseline, then check Layer 1
git tag -f vendor/spotiflac-base <target-sha>
scripts/sync-upstream.sh --check-vendored

# 8. Commit and update this file: baseline, last sync, and Rust registry rows
```

---

## Engine contract check

[`engine-contract.txt`](engine-contract.txt) snapshots the UniFFI calls made by
`UniffiRustCore.kt` and any other app-owned Kotlin file importing
`com.mornye.backend`. Each sorted row records the Kotlin name, parameter list
and return type from generated bindings, plus the corresponding Rust `pub fn`
signature. It includes the cancellation registry constructor and methods on
returned environment, download state, FFmpeg command, and lease objects.
Generated `close()`/`use()` lifecycle helpers and Kotlin data-record constructors
such as `LyricsRequest` have no corresponding Rust `pub fn` and are covered by
Kotlin compilation instead.

```bash
# Generate bindings first if missing or after an upstream binding change
(cd android && ./gradlew :app:buildRustBackend)
scripts/snapshot-engine-contract.sh --check  # exit 1 and diff on drift
scripts/snapshot-engine-contract.sh          # refresh after reviewed changes
bash scripts/test-snapshot-engine-contract.sh
```

The checker reads only the single generated Kotlin bindings file and obtains
Rust signatures with `git grep` over `rust_backend/crates/mobile/src/*.rs`.
`CONTRACT_FILE=<path>` overrides the snapshot path, allowing the negative test
to alter a temporary copy without changing the checked-in contract.
**Kotlin compilation stays the authoritative net**: the snapshot is a diffable
signature guard, not proof of behavioral compatibility or required call order.
Review changed glue and signatures before regenerating, and include the reviewed
snapshot with the sync.

## Required call order (RustEngine init)

1. Record the storage master key with `setExtensionStorageMasterKey(masterKey)`
   before `initExtensionSystem(extDir, dataDir)`. Missing key fails with
   `"extension storage master key is not configured"`. Canonical extension/data
   paths and the key are immutable once recorded for the process.
2. In `initExtensionSystem`, run `EngineDataIsolation.ensureRustCopy(File(ext),
   File(data))` for the one-time Go-era upgrade copy into `engine-rust/`. Pass the
   copied canonical extension and data paths to the factory, followed by the key
   and `EngineVersion.SPOTIFLAC_ENGINE_VERSION` (currently `"5.3.1"`).
   `setAppVersion(version)` is intentionally ignored; the fork's app version
   is not supplied to the engine.
3. `UniffiRustCore.FACTORY` calls
   `ExtensionManager.withLyricsSettings(source, data, masterKey, appVersion,
   TIMEOUT_MS, "[]", "{}")`, in exactly that argument order, with
   `TIMEOUT_MS = 30_000uL`. The manager owns its environment; Kotlin does not
   construct a separate `ExtensionEnvironment`. `manager.environment().use(block)`
   obtains a temporary environment handle for each environment operation.
   The core also constructs `CancellationRegistry(CancellationDomain.EXTENSION_REQUEST)`.
4. Before publishing READY, `RustEngine.applyConfig(created)` applies the download
   directory allow-list, buffered fallback IDs, download priority, metadata
   priority, and cover-cache directory (with a directory grant), in that order.
   Unavailable download directories are filtered using the existing recovery path.
   Only after this succeeds does the engine store the core, set READY, clear the
   failure, and signal waiters. A configuration failure closes the created core
   and leaves the engine FAILED.
5. Call `loadExtensionsFromDir(dirPath)` after init; its canonical path must match
   the recorded source directory. It invokes `manager.loadAll()`, then re-applies
   buffered download priority, metadata priority, and fallback IDs in that order.
   Re-application failures are logged individually. Init itself does not load
   extensions, so this step remains required.

# Rust engine migration — phase 5 findings (2026-10-01)

Branch `feat/rust-engine-phase5` (from `main` 4b9e6d4f). Plan: `docs/superpowers/plans/2026-10-01-rust-engine-phase5-remove-go.md`.

## Removed

- The Go engine (`go_backend/`), the gomobile bridge (`native/bridge/`), the Go DLNA server (`native/server/`) and the `gobackend.aar` dependency: 215 files, ≈66.5k lines.
- Engine selection: `GoEngine`, `EngineKind`, `EngineSelection`, and the `engine_go`/`engine_rust` flag files.
- Go-era tooling: the phase-1 probe, the A/B harness (`scripts/ab-parity.sh`), `scripts/build_android.sh`, `scripts/snapshot-bridge-contract.sh`, and `docs/bridge-contract.txt`.
- `MainActivity` makes no `Bridge.*` call. `ping` answers `"pong"` in Kotlin, and DLNA always uses the Kotlin server.

## Kept / added

- `Engines` always builds `RustEngine`, release builds included.
- `EngineDataIsolation` stays as the release upgrade path. On first launch after upgrading from a Go-era build (v0.9.x/v0.10.0), it makes a one-time copy of `extensions/` + `ext_data/` into `engine-rust/`.
  - The Go-era directories are left untouched for the rollback window. A later release deletes them (spec §3.4/§3.5 amended).
  - Go priorities and the ISRC index were in-memory only, and history/prefs belong to Dart, so nothing else needs migrating.
- Rollback branch `release/0.9.x-go` at `bee1943e` (v0.9.1), kept buildable for one release cycle.
  - A hotfix APK built from it needs a build number higher than the installed Rust release.
  - It can be recreated from `bee1943e`, which is on `main`.
- `scripts/snapshot-engine-contract.sh` + `docs/engine-contract.txt` snapshot the 48 UniFFI calls our glue makes, with their Kotlin binding and Rust `pub fn` signatures. `--check` fails on drift, and `scripts/test-snapshot-engine-contract.sh` is the negative test. It is wired into the sync protocol, and `docs/UPSTREAM-SYNC.md` adds the required RustEngine init-order checklist.
- The APK packages arm64-v8a libraries only: `packaging.jniLibs.excludes` covers v7a/x86/x86_64. Release APK 77.5 MB → **36.8 MB** (v0.9.1 universal: 93.3 MB). No `libgojni.so`, and no bridge classes in dex.

## Verification

- Kotlin unit tests 185/185. Flutter 436/436 (existing tests unmodified).
- `assembleDebug` and release arm64 builds pass.
- `scripts/sync-upstream.sh --check-vendored` is clean: LM-FORK ids `[publish-noreplace-fallback, signed-session-mint]`, engine 5.0.6.
- `sync-upstream.sh v5.0.6` reports "Already in sync". The contract check is clean.
- Device smoke (LG V30, debug APK from 5461dd4f, 2026-10-01 10:54–11:01): **PASS**.
  - Launch: logcat `engine=RUST`, with no crash, `UnsatisfiedLinkError` or `MissingPluginException`. Search uses 9 sources and returns results.
  - Qobuz only (fallback sources temporarily limited to Qobuz, then restored): "Fragments of Time (Drumless Edition)", snapshot `done`, `resolved_service=qobuz-web`, 24-bit/88.2 kHz, `flac -t` ok, LYRICS + UNSYNCEDLYRICS.
  - With normal fallback: "Fragments of Time" resolved to Deezer (not on Qobuz in that edition), 16/44.1, `flac -t` ok, lyrics, 1500 px cover.
  - DLNA from the Mac on the same office Wi-Fi (172.21.0.0/16, a different LAN from the earlier 192.168.1.x tests): SSDP found UDN `uuid:c82df54b-…` (unchanged), browse returned 17 root containers, art 200, Range 206, HEAD 200 with Accept-Ranges.

## Follow-ups

- `.gitignore` still ignores `go_backend/.gomobile/`. It is harmless and left alone because the file carries Hoàng's uncommitted edit.
- `CLAUDE.md` and `.claude/commands/release.md` are gitignored. The Rust-only protocol text and the arm64 release command exist only locally.
- `EngineDataIsolation` uses `copyRecursively`, which follows symlinks (phase-1 hardening item), and a failed copy gives no user-facing message. This is low risk because the source is app-private.
- The contract script skips unmatched lambda-receiver calls silently, and `git grep` ignores untracked Rust files. Kotlin compilation remains the primary net.
- Carried from phase 4:
  - (a) unfinished native-batch items are lost after process death;
  - (c) YouTube "Best Audio" bitrate check;
  - (d) Tidal DASH unwrap drops cover/track/lyrics.
- Phase 6 must run the E2E checks still owed by phase 4: Amazon FLAC-in-MP4 on HEAD, and an Opus file.

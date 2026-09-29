# Rust engine migration — phase 3 findings (2026-09-29)

Branch: `feat/rust-engine-phase3` (from `main` 50987a5c). Plan: `docs/superpowers/plans/2026-09-29-rust-engine-phase3-fixes.md`.

## Delivered

| Item | Where | Evidence |
| --- | --- | --- |
| Fix 1 — lyrics fallback embed on the Rust path | `engine/PostDownload.kt`, called inside the download's directory lease in `RustEngine.downloadByStrategy` | Unit tests (`PostDownloadTest`, `RustEngineTest.postDownloadRunsInsideGrantAndReclassifiesPreflightFailure`); device PASS (below) |
| Fix 4 — preflight verification failure reclassified | `PostDownload.reclassify` | Unit tests; source-pin test on the vendored Rust message |
| Fix 3 — `LM-FORK(signed-session-mint)` | `rust_backend/crates/extensions/src/signed_session/fetch.rs` (3 sites + helper + 2 tests), registry row in `docs/UPSTREAM-SYNC.md` | `cargo test -p spotiflac-extensions`; `--check-vendored` ids `[publish-noreplace-fallback, signed-session-mint]` |
| Upstream PR drafts (not sent) | `docs/migration/upstream-pr-publish-noreplace-fallback.md`, `docs/migration/upstream-pr-signed-session-mint.md` | Both patches `git apply --check` clean on `v5.0.0` |

### Fix 4 correction found in final review

The spec assumed the app reads `error_type`. It does not: `download_queue_provider.dart` takes `error ?? error_type`, and `isExtensionVerificationRequired` (`lib/utils/extension_auth_launcher.dart`) pattern-matches the **text**. Setting only `error_type` would never reopen the verification browser. `PostDownload` now rewrites the message to the Go fork's wording (`Verification required for <provider> but could not start it: <cause>`) and sets `error_type=verification_required`. Spec §5 fix 4 was amended.

### Fix 3 scope

Same three sites as the Go fork (`go_backend/extension_signed_session.go` ~853/879/895): bootstrap `Err` in the expired/unauthenticated branch, bootstrap `Err` in the blocked branch, and the text-only "generation is blocked" error. `Ok("")` keeps upstream behaviour; the refresh-branch and gateway-action bootstraps stay upstream. Cancellation is re-checked before tagging, so a cancel is never reported as `needsVerification`. Not reproducible on demand on a device (needs a failing challenge mint); covered by unit tests only.

## Device verification (LG V30, Android 9, debug build d17633d4, engine=Rust)

| Check | Result | Evidence / limit |
| --- | --- | --- |
| Fix 1, extension without lyrics (Amazon FLAC, "Doin' it Right") | PASS | 24-bit/88.2 kHz, `flac -t` OK, `LYRICS=` and `UNSYNCEDLYRICS=` present. The Amazon extension never returns `lyrics_lrc`, so these came from the fallback. |
| Extension that supplies lyrics (Qobuz FLAC, "Get Lucky") | PASS | 24-bit/88.2 kHz, `flac -t` OK, LRCLIB lyrics embedded by the engine itself (`qobuz-web` returns `lyrics_lrc`); `PostDownload` skips, so no second rewrite. |
| Qobuz / Amazon regression | PASS | Both providers downloaded on Rust. |
| Instrumental sentinel, `already_exists`, non-FLAC skip | unit tests only | `PostDownloadTest`. |
| Cancel / retry, duplicate skip | not re-run | Verified in phase 2; phase 3 does not touch those paths (`already_exists` skip is unit-tested). |
| Fix 3 / fix 4 end to end | not reproducible on demand | Unit tests. |

### Amazon "stream resolution timeout" on Rust — latency, not a regression

One Rust Amazon attempt ("Lose Yourself to Dance") failed with `All providers failed. Last error: stream resolution timeout`; the same track succeeded on Go a few minutes later (output file created ~66 s after tapping), and a later Rust Amazon download ("Doin' it Right") succeeded in 33 s. Code comparison: both engines charge the same 60 s resolution budget (`go_backend/extension_resolution_budget.go:13`, `rust_backend/crates/extensions/src/backend/downloads.rs:724`), pause it only for native transfer bytes and FFmpeg work, and use 30 s per-request HTTP timeouts. The Amazon extension's `fetchWithRetry` retries after a 30 s timeout without checking the remaining budget, so a slow Zarz `/dl` can exhaust 60 s on either engine. Upstream v5.0.0→v5.0.6 did not change these timeouts and no upstream issue reports it. No change made; the budget is not configurable from Kotlin (the orchestrated download path hardcodes 60 s). Decision (Hoàng): noted here only, not reported upstream.

Other Amazon failures seen were catalog misses (a compilation release and a 10th-anniversary release not offered by Amazon), which fall through to other providers.

### FFmpeg pump carry-over — closed

- 0/9 installed extensions call the FFmpeg host API (`ffmpeg.*`) from JavaScript; 0/9 manifests declare `rawFfmpeg` or post-processing.
- Amazon's `decryption.strategy = "ffmpeg.mov_key"` is a descriptor, normalised by `manager/downloads.rs` and executed by the app finalizers (`Mp4FlacUnwrapper.kt`, `container_remux_service.dart`) with ffmpeg-kit directly. `backend/downloads.rs:867` documents that decryption/conversion runs in the Android/Dart finalizers.
- So the `CoreBackend` pump is unreachable with the current extensions. It stays wired for future extensions that use the FFmpeg host.

## Known costs and minor findings

- **Second FLAC rewrite:** on the Rust path the fallback lyrics embed rewrites the finished FLAC once more (Go folded lyrics into its single embed pass). A single pass would need another Layer 1 fork. Only applies when the extension supplies no lyrics.
- **Post-download is not cancellable:** lyrics fetch/embed run with no cancel lease (same as Go).
- **Empty album folder after a failed Rust attempt:** a failed provider attempt left an empty `… (10th Anniversary Edition)` directory. Cosmetic.
- Deferred minors from the task reviews: tests cover the fork helper rather than the three wired sites; the bootstrap error is not logged (the crate has no logging facility); the blocked site holds the scope lock across the cancellation check (safe today).

## Carry-over to phase 4

- Hoàng reviews both PR drafts before anything is sent upstream. Open question in the drafts: whether to include macOS `Errno::NOTSUP` in the `publish-noreplace-fallback` patch itself.
- Upstream is at v5.0.6 (engine changes since v5.0.0: hi-res detection, tag writers, USB audio, provider metadata); the next sync can pick it up with `scripts/sync-upstream.sh`.
- Phase 4: DLNA → Kotlin/Ktor.

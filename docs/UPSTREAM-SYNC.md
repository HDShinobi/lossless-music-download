# Upstream Inheritance & Sync — SpotiFLAC

This fork **inherits** the Rust engine from
[SpotiFLAC-Mobile](https://github.com/spotiflacapp/SpotiFLAC-Mobile). The goal
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
| Synced to | **v5.0.0** (commit `1e3414b3`) — Rust engine (`rust_backend/`) |
| Go engine | Frozen at **v4.9.6** (`vendor/spotiflac-go-final` → `c0f6a607`); still active in the app until migration phase 5 removes it. No longer synced. |
| Upstream remote | `upstream` → `https://github.com/spotiflacapp/SpotiFLAC-Mobile.git` |
| Last sync | 2026-09-25 — vendored v5.0.0 Rust engine alongside Go (migration phase 1; spec `docs/superpowers/specs/2026-09-25-rust-engine-migration-design.md`). |

### History (Go engine)

| | |
| --- | --- |
| Last sync | 2026-09-08 (v4.9.5 → v4.9.6, 64 files in `go_backend/`, +3509/−651). **Verification/signed-session bug-fix release** — the trigger for this sync. Upstream shipped a whole cluster of auth fixes: `fdb4a0ea` (preserve shared signed-session challenge identity — **upstream's own fix for the exact `rememberChallenge` timestamp bug we had forked in v4.9.5**, so our LM-FORK there is now **retired**), `4fc837b9` (preserve `verification_required` when `checkAvailability` *throws* instead of returns — download no longer dies silently without reopening the browser), `1b0c28b9` (route verification notifications to the right pending challenge), `717e8967` (preserve verification provider across fallback), `7be959e7` (preserve verification callback retries), `90da359e` (prepare fallback sessions before availability checks), `448a3426` (shorten verification timeout). Also: metadata preservation across screens + Opus-in-MP4 quality, new album-folder finalize before publish (`c48406f5` — merged into our `extension_fallback.go` LM-FORK call-site), memory release, ReplayGain Opus, new `id3_reader.go`, `extension_resolution_budget.go`, perf work. **No Go-toolchain bump** (go.mod unchanged). **Bridge contract (signatures) unchanged** (`snapshot-bridge-contract.sh --check` clean → no Dart-side edits needed); the only `bridge.go` edit is the mandatory `spotiflacBaselineVersion` bump 4.9.5 → 4.9.6 (reported to the engine for extension `minAppVersion` gates + upstream User-Agent — a const, not part of the exported signature, so the snapshot doesn't flag it; AAR rebuilt to bake it in). **2 conflicts, both in LM-FORK files** — resolved: retired `rememberChallenge` fork (took upstream's `*PendingAuthRequest` signature), and merged upstream's `finalizeDownloadAlbumFolder` step ahead of our lyrics-embed helper. **New cross-tree test dependency:** upstream's new `lyrics_usability_test.go` reads a *shared* fixture at `android/app/src/test/resources/lyrics_usability_cases.tsv` (their fixture-decoupling in `0e71003e`); the sync script only covers `go_backend/`, so that fixture was copied in by hand from `v4.9.6` — re-copy on future syncs if it changes. All 430+ Dart tests unaffected (contract stable); `go build`+`go test` green.) |
| ~~Prior sync~~ | 2026-09-04 (v4.8.5 → v4.9.5, 113 files in `go_backend/`, ~11.7k+/2.4k−). **Large release.** Extension-runtime **security hardening** (network-sandbox bypass fixes, FFmpeg-exec sandbox, encrypted extension storage at rest, callback-state validation, secret redaction in logs), signed-session lifecycle coalescing, a new cross-platform resolver fallback chain (`platform_resolver_fallbacks.go`), direct Kugou/QQ/Genius lyrics, parallel/resumable SAF+CIFS library scan, player sleep timer + headset controls, streaming `.sflb` ZIP backups, resume+verify APK updater. **Go toolchain 1.26.5 → 1.26.6** (bumped `native/bridge/go.mod` to match; `go mod tidy` refreshed goja/x-crypto/x-image/etc). **3-way patch applied clean; all prior LM-FORK touch-points survived.** **Trigger for this sync:** upstream extensions now gate installs on `minAppVersion ≥ 4.9.1` (they rely on the new security contract), so with the old `4.8.5` baseline the engine rejected every extension (`requires app 4.9.1 or later`); `spotiflacBaselineVersion` bumped 4.8.5 → 4.9.5 to reopen the gate. **One new in-place divergence** (see registry): `rememberChallenge` timestamp fix for an *inherited* v4.9.5 bug that broke shared-gateway (amazon/ytmusic → Zarz qobuz-web) coalesced verification with an opaque "callback state is already registered" failure — reproduced on pristine upstream v4.9.5. Bridge contract gained 2 already-called entries (`ReadAudioMetadataJSON`, `ExtractCoverArt`); snapshot refreshed, `native/bridge` builds clean.) |

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
| `rust_backend/`, `scripts/build_rust_backend.sh`, `android/app/src/main/kotlin/com/zarz/spotiflac/CoreBackend.kt` | **Inherited (Layer 1)** — byte-identical to upstream except registered `LM-FORK(<id>)` blocks | 3-way sync via script; `--check-vendored` guard |
| `go_backend/` | **Frozen** at v4.9.6, removed in migration phase 5 | not synced |
| `lib/` | **Ours** — fresh Flutter rebuild (0 files match upstream) | Follow upstream *patterns/contracts*, do NOT merge files |
| `native/bridge`, `native/server` | **Ours** — Go↔Flutter bridge + UPnP server | Keep bridge signatures compatible with `go_backend` exports |
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
| `LM-FORK(publish-noreplace-fallback)` | `rust_backend/crates/extensions/src/files.rs` | Android 9 sdcardfs can reject `renameat2` `NOREPLACE` with `EINVAL`; on unsupported errors, check the destination without following symlinks and use plain rename only when absent under the caller's destination lock. | Upstream PR: to be sent after review |
| `LM-FORK(signed-session-mint)` | `rust_backend/crates/extensions/src/signed_session/fetch.rs` | 3 sites + helper, mirroring the Go fork: when challenge minting fails after the session needs re-auth, return `needsVerification` with no URL so the next attempt retries the challenge and extensions reopen verification; preserve cancellation. | Upstream PR: draft in docs/migration/upstream-pr-signed-session-mint.md (not sent) |

### Our shims for inherited files (not forks)

| File | Why |
| --- | --- |
| `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/EngineShims.kt` | Declares `com.zarz.spotiflac.NativeDownloadFinalizer.runFFmpegArguments` (our ffmpeg-kit) and `com.zarz.spotiflac.BuildConfig.APPLICATION_ID` so vendored `CoreBackend.kt` compiles unchanged. If upstream changes that contract, the build fails here. |

---

## Go divergence registry (frozen)

Every edit to an inherited (`go_backend/`) file lives here. These are the
**only** places a 3-way sync can conflict. Keep this list exhaustive.

| File | Kind | What & why | Marked? |
| --- | --- | --- | --- |
| `go_backend/embed_after_download.go` | **New file** | Post-download lyrics resolution (Feature 1). Since 2026-07-26 this is a **thin wrapper**: it resolves lyrics (extension-supplied first, our providers as fallback, `[instrumental:true]` sentinel dropped) and then delegates the actual tag/cover write to upstream's `embedExtensionDownloadMetadata`. It used to be a full copy of that function; the copy was retired because upstream's body and ours were identical apart from the lyrics block, so the copy could only rot. Upstream improvements to the embed body (e.g. v4.8.0's atomic-write `flac_save.go` path) now land with no action here. | n/a (own file) |
| `go_backend/embed_after_download_test.go` | **New file** | Tests for the above | n/a |
| `go_backend/testdata/silence.flac` | **New fixture** | Test asset | n/a |
| `go_backend/extension_fallback.go` | **In-place edit** (1 site, inside `DownloadWithExtensionFallback`) | The post-download embed call site calls our own `embedMetadataAfterDownload(built, req, alreadyExists)` instead of upstream's `embedExtensionDownloadMetadata(built, req, alreadyExists)`. Our helper **calls** upstream's function (see the row above), so upstream's function and its `firstPositiveInt` helper are live code, not dead weight — if upstream ever renames or deletes them we get a compile error instead of a silent divergence. Moved here from `extension_providers.go` in the v4.8.0 sync, when upstream split that file. | ✅ Wrapped in `// LM-FORK` (1 site) |
| ~~`go_backend/extension_providers.go` — `SetItemDownloading` hook~~ | **Retired 2026-07-26** | We used to call `SetItemDownloading(req.ItemID)` right after `StartItemProgress(req.ItemID)` at the two download start points, because `StartItemProgress` creates the item with `IsDownloading: false` and our queue UI needed the flag set. v4.8.0 added `SetItemPreparingStage(req.ItemID, "resolving_metadata")` at exactly that spot, and it already sets `IsDownloading = true` — plus a `Status`/`Stage` pair that is more accurate than ours. Re-applying our hook would have *wiped* `Stage` and downgraded `Status` from `preparing` to `downloading` while metadata was still resolving. Safe to drop on the Dart side: `_mapStatus` in `download_queue_provider.dart` falls back to the entry's existing status for unrecognized backend strings, and nothing in `lib/` reads the `is_downloading` flag. Same precedent as the `ac4_config.go` row below. | n/a (patch retired) |
| ~~`go_backend/ac4_config.go`~~ | **Removed 2026-07-02** | Upstream's v4.7.1 shipped an equivalent (and slightly more thorough) bounds-check fix for the same truncated-AC4-entry issue we reported (`audioSampleEntryHeaderLen` now returns `(hdrLen, ok)`; both call sites check `ok`). Our `// LM-FORK` guards at both sites were removed as redundant during the v4.7.0→v4.7.1 sync. Our own regression test (`ac4_config_truncated_entry_test.go`) is kept alongside upstream's new `ac4_config_test.go` for belt-and-suspenders coverage — no action needed unless it starts failing. | n/a (patch retired) |
| `go_backend/extension_signed_session.go` | **In-place edit** (3 sites in `signedSessionFetch`) | Bug found 2026-08-12 debugging a user report of downloads stuck failing after a signed session (Zarz qobuz-web gateway, shared by amazon/ytmusic) expired: when the session needs re-auth but *minting a fresh verification challenge itself also fails* (network blip/5xx on the bootstrap call — confirmed live on-device by pulling and reading the installed `amazon/index.js`, which only checks the `needsVerification` boolean, never error text), upstream returned a bare, unflagged error. Extensions that gate on `needsVerification` (not message text) swallow that as a generic transient failure, so the download dies with an opaque provider error (e.g. `"Download API failed for ASIN: ..."`) that never reopens the verification browser — the user is stuck on manual retry indefinitely. All 3 sites now call `signedSessionVerificationRequiredValue("")` instead, so the failure is tagged as verification-required (no URL yet) and the *next* attempt retries the challenge instead of looping silently. | ✅ Wrapped in `// LM-FORK` (3 sites) |
| `go_backend/exports_extensions.go` | **In-place edit** (1 site, `DownloadWithExtensionsJSON`'s preflight-error branch) | Same bug/date as the row above, one layer up: `preflightExtensionDownloadSession`'s error (also reachable when challenge-minting fails) was worded `"Could not start verification for %s: %v"` with `ErrorType: classifyDownloadErrorType(message)` — the raw Go error text (e.g. containing "network") gets misclassified as `error_type: "network"` instead of `verification_required`, and the app's Dart-side auto-reopen-browser detection (`lib/utils/extension_auth_launcher.dart`, pattern-matches error text) never fires. Reworded to `"Verification required for %s but could not start it: %v"` with `ErrorType: "verification_required"`, matching the sibling branch immediately below it in the same function. | ✅ Wrapped in `// LM-FORK` (1 site) |
| `go_backend/extension_signed_session_test.go` | **In-place edit** (1 assertion in `TestDownloadWithExtensionsStopsAfterFailedSignedSessionPreflight`) | Updated to assert the corrected behavior from the row above (`ErrorType == "verification_required"`, message contains "Verification required") instead of the old bug's `ErrorType == "network"` / "Could not start verification" text it had encoded as expected. | ✅ Wrapped in `// LM-FORK` (1 site) |
| ~~`go_backend/extension_signed_session.go` — `rememberChallenge`~~ | **Retired 2026-09-08** | Upstream's v4.9.6 `fdb4a0ea` "preserve shared signed-session challenge identity" is the same fix: `rememberChallenge` now takes the whole `*PendingAuthRequest` and stamps `c.challengeCreatedAt = request.CreatedAt`, so both coalesced registrations agree on the timestamp (and the callback nonce). Our LM-FORK (which passed the real `createdAt` as an extra param) was retired on the v4.9.6 sync — took upstream's version wholesale at all 3 sites. `TestParallelSignedSessionPreflightSharesOneBootstrap` + the new `TestRememberSignedSessionChallengePreservesOriginalLifetime` cover it. | n/a (patch retired) |
| ~~`go_backend/extension_signed_session.go` (prior v4.9.5 form)~~ | **Superseded** (`rememberChallenge` signature + body + 2 call sites) | Fix for an **inherited upstream v4.9.5 bug** found during the v4.9.5 sync (2026-09-04): `TestParallelSignedSessionPreflightSharesOneBootstrap` fails on *pristine* upstream v4.9.5. When two extensions share a signed-session gateway (our amazon/ytmusic → Zarz qobuz-web case) and a verification challenge coalesces onto one bootstrap, the winner registered its `PendingAuthRequest` with `CreatedAt: time.Now()` while `rememberChallenge` stamped `coordinator.challengeCreatedAt` from a *second* `time.Now()`. The second extension then registered with the coordinator's timestamp, which never equalled the winner's — and v4.9.5's new `registerPendingAuthRequest` callback-state validation rejected it as `"callback state is already registered"`, killing that download with an opaque error that never reopened verification (same failure class as the Zarz rows above). Fix: `rememberChallenge` now takes the challenge's real `createdAt` (`pending.CreatedAt` / `request.CreatedAt`) so both registrations agree. **Retire when upstream aligns the two timestamps.** | ✅ Wrapped in `// LM-FORK` (3 sites) |

The frozen Go edits were deliberately thin call-sites — the real feature code lives in the
own-file `embed_after_download.go`, which never conflicts on sync. To list every
divergence inside inherited files at a glance:

Historical Go-only lookup (the Go registry is frozen):

```bash
git grep -n 'LM-FORK' -- go_backend/
```

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
   glue around `CoreBackend.kt` and generated bindings; `native/bridge` is
   historical Go glue, not the Rust integration point.
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
git grep -n '<<<<<<<' -- rust_backend/ scripts/build_rust_backend.sh android/app/src/main/kotlin/com/zarz/spotiflac/CoreBackend.kt

# 4. Bump SPOTIFLAC_ENGINE_VERSION in EngineVersion.kt to the target version

# 5. Verify
(cd rust_backend && cargo test --locked -p spotiflac-extensions)
(cd android && ./gradlew :app:buildRustBackend :app:testDebugUnitTest :app:assembleDebug)
flutter test

# 6. Review the WATCHED diff-stat from the preview and port relevant glue changes

# 7. Advance the baseline, then check Layer 1
git tag -f vendor/spotiflac-base <target-sha>
scripts/sync-upstream.sh --check-vendored

# 8. Commit and update this file: baseline, last sync, and Rust registry rows
```

The `native/bridge` and `go_backend` signature checks below describe the frozen
Go-era bridge. Those Go-only instructions are historical and are not run for
Rust releases.

---

## Bridge contract surface (historical Go era; frozen)

`native/bridge/bridge.go` is our frozen Go glue layer. It links `go_backend` **by source**
(`replace github.com/zarz/spotiflac_android/go_backend => ../../go_backend` in
`native/bridge/go.mod`), then calls **31 exported functions** — all inherited
from upstream (none are our own Go). So every one of them is a potential break
point on a future sync.

> **v4.9.5 post-sync fix (2026-09-04):** the sync bumped the baseline + gates but
> missed a *new startup requirement*. v4.9.5's "encrypted extension storage at
> rest" makes `InitExtensionSystem` return early with
> `"extension storage master key is not configured"` unless
> `SetExtensionStorageMasterKey` (a new export) is called first — leaving the
> extension dirs unconfigured so **every extension install/upgrade failed with
> "extension directory is not configured" and no extensions loaded**. Fix wired
> `SetExtensionStorageMasterKey` through `bridge.go` → Kotlin
> (`setExtensionStorageMasterKey` channel method) → Dart
> (`ExtensionMasterKey.loadOrCreate()` via `flutter_secure_storage`, called
> before `initExtensionSystem` in `extensions_provider.dart`). **Lesson: a sync
> must also re-check for new *required-order* bridge calls, not just changed
> signatures.**

```
bridge.go  ──calls 31 funcs──▶  go_backend exports (exports.go, metadata.go,
                                 lyrics.go, library_scan.go)
```

Two safety nets, both wired into the sync protocol (step 3 of `sync-upstream.sh`):

1. **Compile check (authoritative):** because the link is by source, a changed
   signature fails the build —
   ```bash
   cd native/bridge && go build ./...
   ```
2. **Signature snapshot (diffable):** the full contract is frozen in
   [`bridge-contract.txt`](bridge-contract.txt). Regenerate and diff to catch
   even subtle changes —
   ```bash
   scripts/snapshot-bridge-contract.sh --check   # diff vs committed snapshot
   scripts/snapshot-bridge-contract.sh           # refresh after an intentional change
   ```

When a sync changes the contract: update `bridge.go` and
`lib/services/backend_bridge.dart` to match, then refresh the snapshot and
commit it alongside the sync.

# Upstream Inheritance & Sync — SpotiFLAC

This fork **inherits** the Go download/file-management engine from
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
| Synced to | **v4.8.5** (commit `d3f9388b`) |
| Upstream remote | `upstream` → `https://github.com/spotiflacapp/SpotiFLAC-Mobile.git` |
| Last sync | 2026-08-04 (v4.8.0 → v4.8.5, 77 files in `go_backend/`, ~9.3k+/6.3k−, mostly upstream's dedup/file-split refactor). **3-way patch applied with zero conflicts** — both LM-FORK touch-points survived automatically: the `embedMetadataAfterDownload` hook was re-homed by the merge into upstream's refactored `extension_fallback.go`, and `embed_after_download.go` still delegates to `embedExtensionDownloadMetadata` (relocated to `extension_fallback_output.go`). **Bridge contract: 3 upstream exports removed**, all absorbed in our own layers (no new `go_backend/` divergence): `GetDownloadProgress` was dead (Dart uses `getAllProgress`) → deleted; `GetSearchProvidersJSON` folded into `GetInstalledExtensions.search_behavior` → bridge export dropped and `getSearchProviders()` rederived client-side in `backend_bridge.dart` (mirrors upstream data flow); `CheckDuplicate` retired for batched `CheckDuplicatesBatch` → bridge adapts single→batch, preserving the `{exists,filepath}` shape. `native/bridge/go.mod` on `go 1.26.5`; `go mod tidy` refreshed x/mobile.) |

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
| `go_backend/` | **Inherited** — 87/88 Go files byte-identical to upstream | 3-way sync via script |
| `lib/` | **Ours** — fresh Flutter rebuild (0 files match upstream) | Follow upstream *patterns/contracts*, do NOT merge files |
| `native/bridge`, `native/server` | **Ours** — Go↔Flutter bridge + UPnP server | Keep bridge signatures compatible with `go_backend` exports |
| `landing/`, `branding/`, `docs/` | **Ours** — not in upstream | n/a |

Only `go_backend/` is driven by the sync script. The `INHERIT_PATHS` array in
[`scripts/sync-upstream.sh`](../scripts/sync-upstream.sh) is the authoritative
list — keep this table and that array in agreement.

---

## Divergence registry (our changes inside inherited paths)

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

The edits are deliberately thin call-sites — the real feature code lives in the
own-file `embed_after_download.go`, which never conflicts on sync. To list every
divergence inside inherited files at a glance:

```bash
grep -rn 'LM-FORK' go_backend/
```

---

## The golden rules (keep sync cheap)

1. **Prefer new files over editing upstream files.** New feature in the engine?
   Add `go_backend/<feature>.go` (like `embed_after_download.go`) — new files
   never conflict.
2. **If you MUST edit an upstream file**, keep the change minimal, wrap it in
   `// LM-FORK: <why>` … `// END LM-FORK`, and add a row to the registry above.
3. **Never reformat or reorder** upstream files — it turns a 1-line change into
   a whole-file conflict.
4. **Keep `native/bridge` in step with `go_backend` exports** (`exports.go`):
   when upstream changes a signature, the bridge is where it surfaces.
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
# 1. Preview what an upstream release changes in our inherited paths
scripts/sync-upstream.sh v4.7.0            # or: scripts/sync-upstream.sh  (= upstream/main)

# 2. Apply the 3-way merge
scripts/sync-upstream.sh v4.7.0 --apply

# 3. Resolve conflicts (only in registry files), keeping our intentional changes
grep -rn '<<<<<<<' go_backend

# 4. Verify
cd go_backend && go build ./... && go test ./...
#    then rebuild the AAR and smoke-test the app

# 5. Lock in the new baseline + commit
git tag -f vendor/spotiflac-base <target-sha>
git add -A && git commit -m "chore(upstream): sync go_backend to v4.7.0"

# 6. Update this file: bump "Synced to", "Last sync", and the registry
```

If a sync touches `exports.go` signatures, re-check `native/bridge/bridge.go`
and the Dart side (`lib/services/backend_bridge.dart`) before declaring done.

---

## Bridge contract surface

`native/bridge/bridge.go` is our glue layer. It links `go_backend` **by source**
(`replace github.com/zarz/spotiflac_android/go_backend => ../../go_backend` in
`native/bridge/go.mod`), then calls **30 exported functions**. As of the current
baseline, **all 30 are inherited from upstream and byte-identical to v4.6.0** —
none are ours. So every one of them is a potential break point on a future sync.

```
bridge.go  ──calls 30 funcs──▶  go_backend exports (exports.go, metadata.go,
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

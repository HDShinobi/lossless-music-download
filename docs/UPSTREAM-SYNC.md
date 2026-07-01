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
| Synced to | **v4.7.0** (`c9fc1c3c`, "Release v4.7.0") |
| Upstream remote | `upstream` → `https://github.com/spotiflacapp/SpotiFLAC-Mobile.git` |
| Last sync | 2026-07-01 (v4.6.0 → v4.7.0, clean 3-way apply, no conflicts) |

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
| `go_backend/embed_after_download.go` | **New file** | FLAC metadata embed after download (Feature 1) | n/a (own file) |
| `go_backend/embed_after_download_test.go` | **New file** | Tests for the above | n/a |
| `go_backend/testdata/silence.flac` | **New fixture** | Test asset | n/a |
| `go_backend/extension_providers.go` | **In-place edit** (~23 lines, all inside `DownloadWithExtensionFallback`) | (1) Added `SetItemDownloading(req.ItemID)` at the two download start points (UI progress state). (2) Replaced the inline genre/label embed block with a single call to `embedMetadataAfterDownload(req, path)` — the embed logic itself was moved out to our own `embed_after_download.go`. | ✅ Wrapped in `// LM-FORK` (4 sites) |
| `go_backend/ac4_config.go` | **In-place edit** (2 sites, added in v4.7.0) | Upstream's AC-4 MP4 box rewriting (`normalizeQuickTimeAudioToMP4`, `EnsureAC4ConfigBox`) assumed a truncated/malformed `ac-4` sample entry never happens and sliced past the entry/buffer bounds unconditionally — a crafted or corrupt AC-4 download panics (unrecoverable, crashes the app via the native bridge). Added bounds checks that bail out / return an error instead. Reported upstream; remove this patch + registry row once upstream ships a fix. | ✅ Wrapped in `// LM-FORK` (2 sites) — see `go_backend/ac4_config_truncated_entry_test.go` for regression coverage |

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

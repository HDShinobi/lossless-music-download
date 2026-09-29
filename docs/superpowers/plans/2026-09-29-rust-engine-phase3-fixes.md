# Rust Engine Migration — Phase 3 (Our Fixes on Rust) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Carry the fork's three behavioural fixes onto the Rust engine — lyrics fallback embed (fix 1), preflight verification error reclassification (fix 4), signed-session challenge-mint failure tagged as `needsVerification` (fix 3) — and prepare upstream PR drafts for both Rust forks, then verify on device.

**Architecture:** Fixes 1 and 4 live in our Kotlin layer: a post-download step inside `RustEngine.downloadByStrategy` (the single download path both the Dart queue and `DownloadForegroundService` use). Fix 3 is unreachable from Kotlin (the error goes from the Rust signed-session client straight to extension JS), so it is the Rust LM-FORK `signed-session-mint` in `signed_session/fetch.rs`, which fixes the same three sites the Go fork fixes. PR drafts are markdown files Hoàng reviews before anything is sent.

**Tech Stack:** Kotlin (JVM unit tests with `FakeRustCore`), Rust (`cargo test --locked`), UniFFI bindings, adb for the device task.

**Spec:** `docs/superpowers/specs/2026-09-25-rust-engine-migration-design.md` (§5 fixes 1/3/4, §6 registry/check-vendored, §7 phase 3, §10 criterion 5). Phase-2 results and carry-overs: `docs/migration/phase2-findings.md`.

## Rulings made while planning

- **R-P1 Fix 1 parity with the Go fork** (`go_backend/embed_after_download.go`): embed only when the request has `embed_lyrics` **and** `embed_metadata`, the result is `success:true` and not `already_exists`, and the file is FLAC (the Rust `embed_lyrics_to_file` writes FLAC Vorbis comments only). If the engine already embedded extension-supplied lyrics (result `lyrics_lrc` non-blank), do nothing (avoids a second full FLAC rewrite). Otherwise fetch with `getLyricsLrc(spotify_id, track_name, artist_name, "", duration_ms)`, drop the `[instrumental:true]` sentinel, skip blank. Any failure is logged and never fails the download. The fix runs **inside the same directory lease** as the download.
- **R-P2 Fix 4 detection string** is the literal prefix `Could not start verification for` of the in-band `error` field (from `rust_backend/crates/extensions/src/backend/downloads.rs`). A JVM test reads the vendored Rust source and asserts the prefix still exists, so an upstream rewording fails the sync's verify step (spec §5 fix 4).
- **R-P3 Fix 3 sites mirror the Go fork's three sites exactly** (`go_backend/extension_signed_session.go` ~853/879/895): in `SignedSessionClient::signed_fetch` (`fetch.rs`), (A) `self.bootstrap(&check)?` in the unauthenticated/expired branch (line 33), (B1) `self.bootstrap(&check)?` in the blocked branch (line 42), (B2) the text-only `Err("verification_required: signed-session generation is blocked")` (lines 49-51). Only a bootstrap **Err** is re-tagged; `Ok("")` (no URL, no error) keeps upstream behaviour, as in Go. The refresh-branch bootstrap (line 63) and the gateway-action bootstrap (line 124) stay upstream, because the Go fork left the equivalent paths alone. A cancellation error must never be masked: before returning `verification_required`, re-run `self.check(&check)` and propagate its error.
- **R-P4 Fix 3 test seam:** there are no existing Rust unit tests for `signed_session`, and constructing a `SignedSessionClient` needs a network/store harness. The fork therefore routes all four sites through one small pure helper inside the LM-FORK block, unit-tested with `#[cfg(test)]` in the same block; end-to-end behaviour is verified on device where possible.
- **R-P5 FFmpeg pump carry-over:** the pump is only exercised when extension JavaScript calls the FFmpeg host (`ffmpeg_host.rs`). Task 4 first checks whether any installed extension's JS uses it; if none does, the carry-over is closed as "not reachable with current extensions" in the findings, with evidence.
- **R-P6 PR drafts are files, not PRs.** Nothing is sent to `spotiflacapp/SpotiFLAC-Mobile` in this plan (outward action; Hoàng reviews content first).

## Global Constraints

- Branch `feat/rust-engine-phase3` from `main` (`50987a5c`). Never checkout/switch to `main`, never merge, never push. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Layer 1 stays byte-identical to upstream v5.0.0 except registered forks. Allowed active Rust forks after this phase: `publish-noreplace-fallback` (exists) and `signed-session-mint` (added here). Marker syntax: `// LM-FORK(<id>): <why>` … `// END LM-FORK`; one active registry row per id in `docs/UPSTREAM-SYNC.md` beginning ``| `LM-FORK(<id>)` |``; `scripts/sync-upstream.sh --check-vendored` must pass.
- Never `grep -r`/`find` over `rust_backend/` (4.3 GB `target/`); use `git grep`.
- MethodChannel contract and Dart are unchanged; 433 Dart tests pass unmodified.
- `RustEngine` and helpers stay free of `android.*` (JVM-tested).
- Go engine behaviour is untouched (its forks already contain fixes 1/3/4).
- Gradle: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`, run from `android/`. A Rust rebuild is expected only in Task 2.

## Review Focus

1. **Extension already supplied lyrics** → no second fetch/embed (the file is not rewritten twice). Pinned in Task 1 (`postDownloadSkipsWhenEngineAlreadyHasLyrics`).
2. **Lyrics fetch or embed throws** → download still reported as the engine's success JSON, unchanged. Pinned in Task 1 (`postDownloadFailureNeverFailsTheDownload`).
3. **Non-FLAC or `already_exists` result** → no embed attempted. Pinned in Task 1 (`postDownloadOnlyEmbedsNewFlacFiles`).
4. **User cancels while the signed session is bootstrapping** → the cancellation propagates, it is not turned into `needsVerification`. Pinned in Task 2 (`mint_failure_propagates_cancellation`).
5. **Upstream rewords the preflight message** → our test fails on sync instead of silently losing the reclassification. Pinned in Task 1 (`preflightPrefixStillExistsInVendoredRust`).

---

### Task 1: PostDownload on the Rust path (fix 1 lyrics, fix 4 reclassify)

**Files:**
- Modify: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustCore.kt`, `UniffiRustCore.kt`, `RustEngine.kt`
- Create: `android/app/src/main/kotlin/xyz/losslessmusic/app/engine/PostDownload.kt`
- Test: `android/app/src/test/kotlin/xyz/losslessmusic/app/engine/PostDownloadTest.kt`; modify `FakeRustCore.kt`

**Interfaces:**
- Produces: `RustCore.embedLyricsToFile(path: String, lyrics: String): String` (UniFFI `manager.embedLyricsToFile(path, lyrics, null)`); `object PostDownload { const val INSTRUMENTAL = "[instrumental:true]"; const val PREFLIGHT_PREFIX = "Could not start verification for"; fun apply(core: RustCore, request: JSONObject, result: String, log: (String) -> Unit): String }` — returns the (possibly reclassified) result JSON string.

- [ ] **Step 0: Branch**

```bash
cd /Users/dinhvanhoang/Projects/LosslessMusic-v2
git switch -c feat/rust-engine-phase3   # from main 50987a5c
```

- [ ] **Step 1: Extend the fake**

In `FakeRustCore.kt` add:
```kotlin
    var lyricsLrc = "[00:00.00]x"
    var lyricsThrows: Exception? = null
    var embedThrows: Exception? = null
    val embeds = mutableListOf<Pair<String, String>>()
    override fun embedLyricsToFile(path: String, lyrics: String): String {
        rec("embedLyrics:$path"); embedThrows?.let { throw it }; embeds += path to lyrics
        return "{\"success\":true}"
    }
```
and change the existing `getLyricsLrc` override to:
```kotlin
    override fun getLyricsLrc(spotifyId: String, track: String, artist: String, filePath: String, durationMs: Long): String {
        rec("lyrics:$track"); lyricsThrows?.let { throw it }; return lyricsLrc
    }
```

- [ ] **Step 2: Write the failing tests**

`android/app/src/test/kotlin/xyz/losslessmusic/app/engine/PostDownloadTest.kt`:
```kotlin
package xyz.losslessmusic.app.engine

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class PostDownloadTest {
    private val fake = FakeRustCore()
    private val logs = mutableListOf<String>()
    private fun req(embedLyrics: Boolean = true, embedMetadata: Boolean = true) = JSONObject()
        .put("track_name", "One More Time").put("artist_name", "Daft Punk")
        .put("spotify_id", "sp1").put("duration_ms", 320000)
        .put("embed_lyrics", embedLyrics).put("embed_metadata", embedMetadata)
    private fun ok(path: String = "/m/a.flac", extra: JSONObject.() -> Unit = {}) =
        JSONObject().put("success", true).put("file_path", path).apply(extra).toString()
    private fun apply(request: JSONObject, result: String) = PostDownload.apply(fake, request, result) { logs += it }

    @Test fun embedsFetchedLyricsIntoNewFlac() {
        val out = apply(req(), ok())
        assertEquals(listOf("/m/a.flac" to "[00:00.00]x"), fake.embeds)
        assertEquals(ok(), out)
        assertTrue(fake.calls.contains("lyrics:One More Time"))
    }

    @Test fun postDownloadSkipsWhenEngineAlreadyHasLyrics() {
        apply(req(), ok { put("lyrics_lrc", "[00:01.00]from extension") })
        assertTrue(fake.embeds.isEmpty())
        assertTrue(fake.calls.none { it.startsWith("lyrics:") })
    }

    @Test fun instrumentalSentinelAndBlankAreSkipped() {
        fake.lyricsLrc = "[instrumental:true]"; apply(req(), ok())
        fake.lyricsLrc = "   "; apply(req(), ok())
        assertTrue(fake.embeds.isEmpty())
    }

    @Test fun postDownloadOnlyEmbedsNewFlacFiles() {
        apply(req(), ok("/m/a.opus"))
        apply(req(), ok { put("already_exists", true) })
        apply(req(embedLyrics = false), ok())
        apply(req(embedMetadata = false), ok())
        apply(req(), JSONObject().put("success", false).put("error", "x").toString())
        assertTrue(fake.embeds.isEmpty())
    }

    @Test fun postDownloadFailureNeverFailsTheDownload() {
        fake.lyricsThrows = IllegalStateException("lyrics down")
        assertEquals(ok(), apply(req(), ok()))
        fake.lyricsThrows = null; fake.embedThrows = IllegalStateException("embed failed")
        assertEquals(ok(), apply(req(), ok()))
        assertTrue(logs.any { it.contains("lyrics") })
    }

    @Test fun preflightFailureIsReclassifiedAsVerificationRequired() {
        val failed = JSONObject().put("success", false)
            .put("error", "Could not start verification for amazon: network down").put("error_type", "network").toString()
        val out = JSONObject(apply(req(), failed))
        assertEquals("verification_required", out.getString("error_type"))
        assertEquals("Could not start verification for amazon: network down", out.getString("error"))
    }

    @Test fun otherFailuresKeepTheirType() {
        val failed = JSONObject().put("success", false).put("error", "rate limited").put("error_type", "rate_limit").toString()
        assertEquals(failed, apply(req(), failed))
    }

    @Test fun preflightPrefixStillExistsInVendoredRust() {
        val src = File("../../rust_backend/crates/extensions/src/backend/downloads.rs").readText()
        assertTrue("upstream reworded the preflight message; update PostDownload.PREFLIGHT_PREFIX", src.contains(PostDownload.PREFLIGHT_PREFIX))
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests 'xyz.losslessmusic.app.engine.PostDownloadTest'; cd ..`
Expected: FAIL — unresolved `PostDownload` / `embedLyricsToFile`.

- [ ] **Step 4: Implement**

`RustCore.kt` — add to the downloads/files section:
```kotlin
    fun embedLyricsToFile(path: String, lyrics: String): String
```
`UniffiRustCore.kt`:
```kotlin
    override fun embedLyricsToFile(path: String, lyrics: String): String = manager.embedLyricsToFile(path, lyrics, null)
```
`android/app/src/main/kotlin/xyz/losslessmusic/app/engine/PostDownload.kt`:
```kotlin
package xyz.losslessmusic.app.engine

import org.json.JSONObject

/**
 * Our post-download step on the Rust path (spec §5): fix 1 (lyrics fallback embed, parity with
 * go_backend/embed_after_download.go) and fix 4 (preflight verification failure reclassified).
 * Never fails a download: every error is logged and the engine's result is returned.
 */
object PostDownload {
    const val INSTRUMENTAL = "[instrumental:true]"
    const val PREFLIGHT_PREFIX = "Could not start verification for"

    fun apply(core: RustCore, request: JSONObject, result: String, log: (String) -> Unit): String {
        val r = try { JSONObject(result) } catch (e: Exception) { return result }
        if (!r.optBoolean("success", false)) return reclassify(r, result)
        embedLyricsIfNeeded(core, request, r, log)
        return result
    }

    private fun reclassify(r: JSONObject, original: String): String {
        val error = r.optString("error", "")
        if (!error.startsWith(PREFLIGHT_PREFIX)) return original
        return r.put("error_type", "verification_required").toString()
    }

    private fun embedLyricsIfNeeded(core: RustCore, request: JSONObject, r: JSONObject, log: (String) -> Unit) {
        if (!request.optBoolean("embed_lyrics", false) || !request.optBoolean("embed_metadata", false)) return
        if (r.optBoolean("already_exists", false)) return
        val path = r.optString("file_path", "")
        if (!path.lowercase().endsWith(".flac")) return
        if (r.optString("lyrics_lrc", "").isNotBlank()) return
        try {
            val lrc = core.getLyricsLrc(
                request.optString("spotify_id", ""),
                request.optString("track_name", ""),
                request.optString("artist_name", ""),
                "",
                request.optLong("duration_ms", 0L),
            ).trim()
            if (lrc.isEmpty() || lrc == INSTRUMENTAL) return
            core.embedLyricsToFile(path, lrc)
        } catch (e: Exception) {
            log("post-download lyrics: ${e.message}")
        }
    }
}
```
`RustEngine.downloadByStrategy` — run PostDownload inside the lease, replacing the `result` lines:
```kotlin
            val result = withGrant(c, outputDir) {
                PostDownload.apply(c, request, c.downloadWithPump(requestJson), log)
            }
```

- [ ] **Step 5: Run to verify they pass** — the focused test (8 PASS), then `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug; cd ..`, `flutter test`, `scripts/sync-upstream.sh --check-vendored`. Existing `RustEngineTest` must stay green (FakeRustCore `downloadResult` has no `embed_lyrics` request flag, so no embed happens there).

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustCore.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/UniffiRustCore.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/RustEngine.kt android/app/src/main/kotlin/xyz/losslessmusic/app/engine/PostDownload.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/PostDownloadTest.kt android/app/src/test/kotlin/xyz/losslessmusic/app/engine/FakeRustCore.kt
git commit -m "feat(engine): post-download lyrics fallback + preflight reclassify on Rust

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Rust LM-FORK `signed-session-mint` (fix 3)

**Files:**
- Modify: `rust_backend/crates/extensions/src/signed_session/fetch.rs` (inside LM-FORK markers only)
- Modify: `docs/UPSTREAM-SYNC.md` (Rust divergence registry)

**Interfaces:**
- Consumes: `SignedSessionClient::{bootstrap, check, verification_required}` (upstream, `exchange.rs` / `coordinator.rs`); `verification_required(String::new())` returns `{"ok":false,"needsVerification":true,"error":"VERIFY_REQUIRED","open_auth_url":"","auth_url":""}`.
- Produces: fork id `signed-session-mint` with one active registry row.

- [ ] **Step 1: Add the helper and its tests inside a new LM-FORK block at the end of `fetch.rs`**

```rust
// LM-FORK(signed-session-mint): minting a verification challenge can fail (network blip / 5xx on the
// bootstrap call) right after we detect the session needs re-auth. Upstream returns a bare Err (or a
// text-only "verification_required:" Err) which session_host serialises to {"ok":false,"error":…}
// without needsVerification, so extensions that gate on that flag never reopen the verification
// browser and the download dies with an opaque provider error. Tag it as verification-required
// (no URL yet) so the next attempt retries the challenge. Cancellation is never masked.
fn lm_on_mint_failure<T>(
    recheck: impl FnOnce() -> Result<(), String>,
    verification: impl FnOnce() -> T,
) -> Result<T, String> {
    recheck()?;
    Ok(verification())
}

#[cfg(test)]
mod lm_signed_session_mint_tests {
    use super::lm_on_mint_failure;

    #[test]
    fn mint_failure_becomes_verification_required() {
        let out = lm_on_mint_failure(|| Ok(()), || serde_json::json!({"needsVerification": true}));
        assert_eq!(out.unwrap()["needsVerification"], true);
    }

    #[test]
    fn mint_failure_propagates_cancellation() {
        let out = lm_on_mint_failure(|| Err("download cancelled".to_string()), || 1);
        assert_eq!(out.unwrap_err(), "download cancelled");
    }
}
// END LM-FORK
```

- [ ] **Step 2: Run to verify the tests pass**

Run: `(cd rust_backend && cargo test --locked -p spotiflac-extensions lm_signed_session_mint_tests --lib)`
Expected: 2 passed.

- [ ] **Step 3: Route the four sites through the helper (each wrapped in its own LM-FORK markers, no reformatting)**

In `SignedSessionClient::signed_fetch`, before the request loop:
- **Site A (unauthenticated / expired branch)** — replace `let url = self.bootstrap(&check)?;` with:
```rust
                // LM-FORK(signed-session-mint): bootstrap failure → needsVerification (see helper at EOF)
                let url = match self.bootstrap(&check) {
                    Ok(url) => url,
                    Err(_) => return lm_on_mint_failure(|| self.check(&check), || self.verification_required(String::new())),
                };
                // END LM-FORK
```
- **Site B1 (blocked branch)** — same replacement for its `let url = self.bootstrap(&check)?;`.
- **Site B2 (blocked branch, still blocked after reload)** — replace
```rust
                    return Err(
                        "verification_required: signed-session generation is blocked".into(),
                    );
```
with:
```rust
                    // LM-FORK(signed-session-mint): text-only error → needsVerification (see helper at EOF)
                    return lm_on_mint_failure(|| self.check(&check), || self.verification_required(String::new()));
                    // END LM-FORK
```
`self.check(&check)` has the signature `fn check(&self, check: Check<'_>) -> Result<(), String>`, where `Check<'a> = &'a dyn Fn() -> Result<(), String>` (`coordinator.rs:13,192`). It is used exactly as upstream already calls it at line 15. Leave the refresh-branch bootstrap (line 63) and the gateway-action bootstrap (line 124) unchanged (ruling R-P3).

- [ ] **Step 4: Registry row** — in `docs/UPSTREAM-SYNC.md` "Rust divergence registry", add an active row beginning exactly ``| `LM-FORK(signed-session-mint)` |`` with file `rust_backend/crates/extensions/src/signed_session/fetch.rs` (3 sites + helper, mirroring the Go fork), what & why (as the helper comment), and "Upstream PR: draft in docs/migration/upstream-pr-signed-session-mint.md (not sent)". Keep the `publish-noreplace-fallback` row.

- [ ] **Step 5: Verify**

```bash
(cd rust_backend && cargo test --locked -p spotiflac-extensions)
(cd android && ./gradlew :app:buildRustBackend :app:testDebugUnitTest :app:assembleDebug)   # Rust rebuild expected
flutter test
scripts/sync-upstream.sh --check-vendored     # ids [publish-noreplace-fallback, signed-session-mint]
git diff 'v5.0.0^{commit}' -- rust_backend/crates/extensions/src/signed_session/fetch.rs | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)'   # every changed line sits between LM-FORK markers
```

- [ ] **Step 6: Commit**

```bash
git add rust_backend/crates/extensions/src/signed_session/fetch.rs docs/UPSTREAM-SYNC.md
git commit -m "fix(engine): LM-FORK signed-session-mint — tag challenge-mint failures as needsVerification

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Upstream PR drafts (not sent)

**Files:**
- Create: `docs/migration/upstream-pr-publish-noreplace-fallback.md`, `docs/migration/upstream-pr-signed-session-mint.md`

**Interfaces:** consumes the two forks as committed (`publish-noreplace-fallback` from phase 2 `a118996a`, `signed-session-mint` from Task 2).

- [ ] **Step 1: Write each draft** with these sections, in English, addressed to upstream maintainers (upstream's names are fine here — this is for their repo): Title; Problem (symptom, affected platform, how it surfaces to users); Root cause (file:line in upstream v5.0.0); Fix (what changes, why it is safe, what it deliberately does not change); Patch (the exact unified diff of the fork vs `v5.0.0^{commit}`, produced with `git diff 'v5.0.0^{commit}' -- <file>`, with the `LM-FORK` marker comments **removed** so it reads as a clean upstream change); Tests (the tests included and how to run them); Notes (e.g. macOS `ENOTSUP` for publish-noreplace-fallback — ruling R11 of phase 2 — include `Errno::NOTSUP` in the upstream version). No tokens, grants, states, or personal data.
- [ ] **Step 2: Sanity-check each patch applies to a clean upstream tree**

```bash
tmp=$(mktemp -d); git archive 'v5.0.0^{commit}' rust_backend | tar -x -C "$tmp"
(cd "$tmp" && git init -q && git apply --check /path/to/extracted.patch && echo applies)
rm -rf "$tmp"
```
(Extract each draft's diff block to a temp `.patch` file first; `/path/to/extracted.patch` is that temp file.)
- [ ] **Step 3: Commit**

```bash
git add docs/migration/upstream-pr-publish-noreplace-fallback.md docs/migration/upstream-pr-signed-session-mint.md
git commit -m "docs(migration): upstream PR drafts for the two Rust forks (not sent)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Device verification + findings (controller, LG V30)

**Files:**
- Create: `docs/migration/phase3-findings.md`

- [ ] **Step 1:** `flutter build apk --debug`, `adb install -r` (debug default engine is Rust).
- [ ] **Step 2 — fix 1:** with "embed lyrics" enabled, download a Qobuz FLAC whose provider supplies no lyrics; pull the file and confirm `metaflac --export-tags-to=-` shows `LYRICS=`/`UNSYNCEDLYRICS=`; download an instrumental track and confirm no LYRICS tag; confirm no double rewrite when the extension supplies lyrics (logcat shows no `post-download lyrics` fetch).
- [ ] **Step 3 — regression:** Qobuz FLAC, Amazon FLAC, cancel+retry, duplicate skip on Rust (same checks as phase 2).
- [ ] **Step 4 — fix 3/4:** not deterministically reproducible on device (needs a failing challenge mint / preflight); record "covered by unit tests" unless a natural occurrence is observed; if the verification browser reopens after an expired session, record it.
- [ ] **Step 5 — pump carry-over (ruling R-P5):** `adb shell run-as xyz.losslessmusic.app sh -c 'grep -o -h -E "ffmpeg\.[A-Za-z]+" files/extensions/*/*.js | sort | uniq -c'`; if no extension calls the FFmpeg host, close the carry-over with this evidence; otherwise download with that extension and capture logcat evidence of a pumped command.
- [ ] **Step 6:** write `docs/migration/phase3-findings.md` (results + evidence, carry-over to phase 4: DLNA port), run `cd android && ./gradlew :app:testDebugUnitTest; cd ..`, `flutter test`, `scripts/sync-upstream.sh --check-vendored`, commit:
```bash
git add docs/migration/phase3-findings.md
git commit -m "docs(migration): phase 3 device findings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** fix 1 → Task 1 (PostDownload lyrics); fix 4 → Task 1 (reclassify + source-pin test); fix 3 → Task 2 (LM-FORK, 3 sites = Go parity, test, registry); criterion 5 (fork active + PR drafted; sending needs Hoàng) → Tasks 2–3; §6 check-vendored → Task 2 verify; device gate → Task 4; phase-2 carry-over (pump) → Task 4 Step 5.
- **Not in phase 3:** DLNA port (phase 4), Go removal (phase 5), sending PRs (needs Hoàng's review of the drafts).

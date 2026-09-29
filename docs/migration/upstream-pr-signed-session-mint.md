# PR draft: Preserve verification signaling when signed-session challenge minting fails

> Sent upstream as https://github.com/spotiflacapp/SpotiFLAC-Mobile/pull/610 on 2026-09-29.

## Title

Return verification-required after signed-session challenge mint failure

## Problem

When a signed session needs re-authentication and challenge minting fails, e.g. a network error or 5xx from the bootstrap request, a download can end with an opaque provider error. The extension needs the `needsVerification` result to reopen verification and retry on the next attempt.

## Root cause

In upstream `v5.0.0`, `rust_backend/crates/extensions/src/signed_session/fetch.rs:33-51`, two `bootstrap(&check)?` calls propagate mint failure as a plain error, and the blocked-generation path returns a text-only error. Neither gives the extension a structured `needsVerification` result.

## Fix

At those three sites, return `verification_required` with an empty URL when challenge minting fails or the generation remains blocked. Recheck cancellation first, so cancellation continues to propagate as an error. Successful challenge URLs and the remaining signed-fetch paths retain their existing behavior. An empty URL asks the next attempt to mint a fresh challenge; this change does not synthesize a URL or bypass session checks.

## Patch

```diff
diff --git a/rust_backend/crates/extensions/src/signed_session/fetch.rs b/rust_backend/crates/extensions/src/signed_session/fetch.rs
--- a/rust_backend/crates/extensions/src/signed_session/fetch.rs
+++ b/rust_backend/crates/extensions/src/signed_session/fetch.rs
@@ -30,7 +30,15 @@
             };
             if let Some(error) = error {
                 drop(state);
-                let url = self.bootstrap(&check)?;
+                let url = match self.bootstrap(&check) {
+                    Ok(url) => url,
+                    Err(_) => {
+                        return on_mint_failure(
+                            || self.check(&check),
+                            || self.verification_required(String::new()),
+                        );
+                    }
+                };
                 return if url.is_empty() {
                     Err(error.into())
                 } else {
@@ -39,15 +47,24 @@
             }
             if state.blocked(&record) {
                 drop(state);
-                let url = self.bootstrap(&check)?;
+                let url = match self.bootstrap(&check) {
+                    Ok(url) => url,
+                    Err(_) => {
+                        return on_mint_failure(
+                            || self.check(&check),
+                            || self.verification_required(String::new()),
+                        );
+                    }
+                };
                 if !url.is_empty() {
                     return Ok(self.verification_required(url));
                 }
                 let state = self.scope.lock().expect("signed session coordinator lock");
                 record = self.load()?;
                 if !record.usable(self.registry.auth.now()) || state.blocked(&record) {
-                    return Err(
-                        "verification_required: signed-session generation is blocked".into(),
+                    return on_mint_failure(
+                        || self.check(&check),
+                        || self.verification_required(String::new()),
                     );
                 }
             }
@@ -139,3 +156,28 @@
         }
     }
 }
+
+fn on_mint_failure<T>(
+    recheck: impl FnOnce() -> Result<(), String>,
+    verification: impl FnOnce() -> T,
+) -> Result<T, String> {
+    recheck()?;
+    Ok(verification())
+}
+
+#[cfg(test)]
+mod signed_session_mint_tests {
+    use super::on_mint_failure;
+
+    #[test]
+    fn mint_failure_becomes_verification_required() {
+        let out = on_mint_failure(|| Ok(()), || serde_json::json!({"needsVerification": true}));
+        assert_eq!(out.unwrap()["needsVerification"], true);
+    }
+
+    #[test]
+    fn mint_failure_propagates_cancellation() {
+        let out = on_mint_failure(|| Err("download cancelled".to_string()), || 1);
+        assert_eq!(out.unwrap_err(), "download cancelled");
+    }
+}
```

## Tests

The patch includes unit tests for a mint failure becoming a structured `needsVerification` result and for cancellation remaining an error. Run from `rust_backend/`:

```bash
cargo test --locked -p spotiflac-extensions signed_session_mint_tests
```

## Notes

A downstream fork has carried the equivalent fix on the previous Go engine. This patch covers the two initial bootstrap-failure branches and the blocked-generation text-error branch. Other bootstrap calls in `signed_fetch` remain unchanged; upstream may review them separately for the same response contract. No live provider or Android device result is claimed by these unit tests.

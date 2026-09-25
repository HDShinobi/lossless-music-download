# Rust engine migration — phase 1 findings (2026-09-25)

Branch `feat/rust-engine-migration`, commits `9aa6f8b1`..`245cb716`. Spec:
`docs/superpowers/specs/2026-09-25-rust-engine-migration-design.md`.

## Toolchain
- Rust 1.98.1 via `rust_backend/rust-toolchain.toml`: works (`cargo test --locked -p spotiflac-extensions`: 61 passed, 0 failed, 2 ignored).
- NDK 29.0.14206865 used for the Rust build even with `ANDROID_NDK_HOME` = NDK 27: the `rustc` link step used
  `…/ndk/29.0.14206865/…/aarch64-linux-android24-clang`; the `.so` ident reads `Android (13989888 …) clang version 21.0.0`.
- AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14 / JDK 17 target compiled the UniFFI bindings unchanged — **no bump needed**.
- ffmpeg-kit-full 2.1.0 is sufficient for the `runFFmpegArguments` shim (async API, `session.output`, `FFmpegKit.cancel`) — no bump.
- ProGuard: not needed while release `isMinifyEnabled = false`; if minify is ever enabled, keep `com.spotiflac.backend.**` and `com.sun.jna.**`.
- First Gradle build including the Rust engine: ~6 min 17 s (`lto = "thin"`, `codegen-units = 1`); afterwards `:app:buildRustBackend` is `UP-TO-DATE` (debug rebuild ~8 s).
- Both new arm64 `.so` files are 16 KB page-aligned.

## APK size (debug, arm64)
- Before (Go only): 158,389,068 bytes
- After (Go + Rust): 184,917,686 bytes (+26.5 MB, +16.7%) — informational; the release gate applies in phase 6 after Go removal.

## Populated Go-era profile probe
- Device: LG US998 (V30), Android 9.
- Profile: app **v0.9.0** (Go engine v4.9.5, encrypted extension storage), last used 2026-09-08 — not v0.9.1, but the same Go-era on-disk format family.
- Upgrade: `adb install -r` of the debug build over it succeeded (same debug keystore), data kept.
- Go-side data before probe: 9 extensions (amazon, apple-music, deezer, pandora, qobuz-web, soundcloud, spotify-web, tidal-web, ytmusic-spotiflac), 43 files under `extensions/` + `ext_data/`.
- `rust_probe.json` (secrets omitted):
  - `ok: true`, `engine_version: "5.0.0"`
  - `load_all`: `errors: []`, 9 loaded
  - `installed`: all 9 extensions, each `enabled: true`, `status: loaded` (amazon 2.2.0, apple-music 1.3.5, deezer 1.2.0, pandora 1.0.8, qobuz-web 1.1.0, soundcloud 1.0.5, spotify-web 1.9.12, tidal-web 1.1.2, ytmusic-spotiflac 2.3.8)
  - `provider_priorities`: `{"download":[],"fallback":null,"metadata":[]}` — expected: Go-era priorities are pushed by Dart at runtime, not persisted in engine storage.
- Rust `.so` loads through JNA on the device (no `UnsatisfiedLinkError`).
- Go dirs unchanged across the probe: md5 of all 43 files identical before/after.
- `engine-rust/` copy is complete: identical to the Go dirs file-for-file, plus two empty `.backend-manager.lock` files the Rust engine creates in its own copy.
- Flag off (`files/debug_rust_probe` removed): no probe thread, no `rust_probe.json`, no `RustProbe` log lines.
- **Verdict: PASS** — extensions load and encrypted storage decrypts under the Rust engine; no one-time migration is needed for this profile.

## Go path after the upgrade + probe
- Qobuz download on Go: succeeded (`resolved_service: qobuz-web`, 27.7 MB, `status: done`).
- Amazon download on Go: first attempt returned `verification_required` ("extension 'amazon' needs signed-session verification"); the app reopened the verification browser automatically, and after verifying the download succeeded.
  Meets spec §3.5 ("sessions still work or cleanly request re-verification"). Cause not attributable from this run: the profile's last use was 17 days earlier, so the signed session may simply have expired; whether the Rust `loadAll` touched server-side session state is not proven either way.

## Carry-over to phase 2
- Re-check the Amazon/Zarz signed-session behaviour in the phase-2 A/B runs (deterministic reset from a fresh, recently verified snapshot) to rule out server-side token rotation by the Rust engine.
- Rust starts with empty provider priorities: `EngineBridge` must receive Dart's priority push after init, as Go does today.
- APK ships `libjnidispatch.so` for armeabi-v7a/x86_64 (from the JNA aar) — pre-existing multi-ABI packaging (Flutter/ffmpeg libs already ship 32-bit); separate ticket (`--target-platform android-arm64`).
- `runCancellable` waits for `shouldCancel()` if ffmpeg-kit never fires its completion callback; `copyRecursively` follows symlinks — harden when `EngineBridge` does the real copy.
- The debug probe logs the full probe JSON to logcat (debug builds only); never paste it into docs or issues.

# Build prerequisites

The Android build compiles upstream's Rust-only engine (`rust_backend/`) and generates
UniFFI bindings automatically via Gradle's `buildRustBackend` task before `preBuild`.
Manual Rust build: `bash scripts/build_rust_backend.sh android`.

| Tool | Version | Install |
|---|---|---|
| Flutter / Dart | 3.41.x / 3.11.x | Install Flutter and run `flutter pub get` |
| Android SDK | via Android Studio | Install SDK command-line tools (including `sdkmanager`) |
| rustup | any recent | https://rustup.rs |
| Rust toolchain | 1.98.1 (read from `rust_backend/rust-toolchain.toml`) | `rustup toolchain install 1.98.1 --profile minimal -c rustfmt -c clippy` |
| Android Rust target | aarch64-linux-android | `rustup target add aarch64-linux-android --toolchain 1.98.1` |
| Android NDK (Rust only) | 29.0.14206865 | `sdkmanager "ndk;29.0.14206865"` |
| JDK for Gradle | Android Studio JBR | `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"` |

The Rust build uses NDK 29 from the Android SDK directory at `ndk/29.0.14206865`, or `RUST_ANDROID_NDK_HOME` if set.
It deliberately ignores `ANDROID_NDK_HOME` (which may point at the NDK Flutter uses for the app).
All cargo invocations use `--locked`; never run `cargo update` inside `rust_backend/` (it is vendored).
Debug and release APKs support only arm64-v8a devices (Android 8.0+).

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
flutter pub get
flutter build apk --release --target-platform android-arm64
```

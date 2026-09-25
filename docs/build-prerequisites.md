# Build prerequisites

The Android build compiles upstream's Rust engine (`rust_backend/`) before `preBuild`.

| Tool | Version | Install |
|---|---|---|
| rustup | any recent | https://rustup.rs |
| Rust toolchain | 1.98.1 (read from `rust_backend/rust-toolchain.toml`) | `rustup toolchain install 1.98.1 --profile minimal -c rustfmt -c clippy` |
| Android Rust target | aarch64-linux-android | `rustup target add aarch64-linux-android --toolchain 1.98.1` |
| Android NDK (Rust only) | 29.0.14206865 | `sdkmanager "ndk;29.0.14206865"` |
| JDK for Gradle | Android Studio JBR | `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"` |

The Rust build uses NDK 29 from `$ANDROID_SDK/ndk/29.0.14206865`, or `RUST_ANDROID_NDK_HOME` if set.
It deliberately ignores `ANDROID_NDK_HOME` (which may point at the NDK Flutter uses for the app).
All cargo invocations use `--locked`; never run `cargo update` inside `rust_backend/` (it is vendored).
Only arm64-v8a is built.

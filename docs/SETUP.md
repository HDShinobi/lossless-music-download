# Toolchain setup (chỉ máy dev — người dùng cuối KHÔNG cần)

- Flutter 3.41.x, Dart 3.11.x.
- rustup + Rust theo `rust_backend/rust-toolchain.toml` (hiện tại `1.98.1`).
- Rust target `aarch64-linux-android`.
- Android SDK + NDK `29.0.14206865` (qua Android Studio / sdkmanager).
- JDK cho Gradle: Android Studio JBR.
- Lệnh cài đặt và cấu hình NDK: [build-prerequisites.md](build-prerequisites.md).

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Gradle tự build Rust backend và UniFFI bindings qua `buildRustBackend` trước
`preBuild`; Cargo dùng `--locked`. Không cần build archive riêng.
APK debug và release chỉ hỗ trợ thiết bị **arm64-v8a**, Android 8.0+.

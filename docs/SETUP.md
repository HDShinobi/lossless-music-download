# Toolchain setup (chỉ máy dev — người dùng cuối KHÔNG cần)

- Flutter 3.41.x, Dart 3.11.x
- Go 1.25+            (`brew install go`)
- gomobile + gobind  (`go install golang.org/x/mobile/cmd/gomobile@latest && go install golang.org/x/mobile/cmd/gobind@latest && gomobile init`)
- Android SDK + NDK  (qua Android Studio / sdkmanager), set `ANDROID_NDK_HOME`
- Build .aar: `bash scripts/build_android.sh`

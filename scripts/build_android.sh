#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS="$ROOT/android/app/libs"
mkdir -p "$LIBS"

# Ensure ANDROID_NDK_HOME is set
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/Users/dinhvanhoang/Library/Android/sdk/ndk/27.0.12077973}"

# Ensure Java is available (use Android Studio JBR if system java is missing)
if ! java -version &>/dev/null 2>&1; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

# 1) hello (smoke test) — arm64 only for emulator; add ,arm for release
( cd "$ROOT/native/hello" && go mod tidy && \
  ~/go/bin/gomobile bind -target=android/arm64 -androidapi 26 \
    -javapkg=xyz.losslessmusic.nativebridge \
    -o "$LIBS/hello.aar" . )

echo "Built: $LIBS/hello.aar"

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS="$ROOT/android/app/libs"
mkdir -p "$LIBS"

# Ensure ANDROID_NDK_HOME is set: use env var if present, else auto-detect newest NDK.
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  _NDK_BASE="${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk"
  if [ -d "$_NDK_BASE" ]; then
    _NDK_DIR="$(ls -1 "$_NDK_BASE" | sort -V | tail -1)"
    if [ -n "$_NDK_DIR" ]; then
      export ANDROID_NDK_HOME="$_NDK_BASE/$_NDK_DIR"
    fi
  fi
  if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    echo "ERROR: ANDROID_NDK_HOME is not set and no NDK found under ${_NDK_BASE}." >&2
    echo "Set ANDROID_NDK_HOME to your NDK directory and re-run." >&2
    exit 1
  fi
fi

# Ensure Java is available (use Android Studio JBR if system java is missing).
if ! java -version >/dev/null 2>&1; then
  _AS_JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [ -d "$_AS_JBR" ]; then
    export JAVA_HOME="$_AS_JBR"
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
fi

# Ensure GOPATH/bin is in PATH so gomobile can locate gobind (its internal tool).
export PATH="$(go env GOPATH)/bin:$PATH"

# Unified bridge: native/bridge wraps ping + SpotiFLAC go_backend into
# a single AAR so only one libgojni.so / go.Seq runtime is linked.
#
# CGO_LDFLAGS forces the NDK linker to emit 16KB-aligned ELF LOAD segments.
# gomobile (an unofficial x/ package) doesn't inherit NDK r28's 16KB-by-default
# behavior on its own -- without this, libgojni.so links at the old 4KB
# alignment even though every other .so in the APK (ffmpeg-kit) is 16KB-ready.
( cd "$ROOT/native/bridge" && go mod tidy && \
  CGO_LDFLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384" \
  "$(go env GOPATH)/bin/gomobile" bind -target=android/arm64 -androidapi 26 \
    -javapkg=xyz.losslessmusic.backend \
    -o "$LIBS/gobackend.aar" . )

echo "Built: $LIBS/gobackend.aar (unified bridge: ping + gobackend)"

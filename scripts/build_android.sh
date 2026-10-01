#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure ANDROID_NDK_HOME is set: use env var if present, else use the Rust NDK pin.
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  _NDK_BASE="${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk"
  if [ -d "$_NDK_BASE" ]; then
    _NDK_DIR="29.0.14206865"
    if [ -d "$_NDK_BASE/$_NDK_DIR" ]; then
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

# The app ships only the arm64 Rust engine and its UniFFI bindings.
export SPOTIFLAC_RUST_ANDROID_ABIS="arm64-v8a"
bash "$ROOT/scripts/build_rust_backend.sh" android

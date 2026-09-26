#!/usr/bin/env bash
# A/B parity run (spec §8): same fixture, one process per engine, compare JSON shapes on device.
# Usage: scripts/ab-parity.sh [--capture]   (--capture snapshots the current Go data dirs first)
set -euo pipefail
PKG=xyz.losslessmusic.app
RUNAS=(adb shell run-as "$PKG")

launch() {
  adb shell am force-stop "$PKG"
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

wait_for() { # $1 = file under files/, $2 = timeout seconds
  for _ in $(seq 1 "$2"); do
    if "${RUNAS[@]}" test -f "files/$1" 2>/dev/null || "${RUNAS[@]}" ls "files/$1" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  echo "timeout waiting for files/$1" >&2
  adb logcat -d -s RustEngine:* Engines:* AbHarness:* AndroidRuntime:E | tail -80 >&2 || true
  return 1
}

touch_flag() { "${RUNAS[@]}" touch "files/$1"; }
rm_file() { "${RUNAS[@]}" rm -f "files/$1"; }

if [[ "${1:-}" == "--capture" ]]; then
  touch_flag ab_capture; launch; sleep 8
  echo "fixture captured"
fi

for engine in go rust; do
  rm_file "ab-$engine.json"; rm_file engine_go; rm_file engine_rust
  touch_flag "engine_$engine"; touch_flag ab_restore; touch_flag ab_record
  launch
  wait_for "ab-$engine.json" 180
  echo "recorded $engine"
done

rm_file ab-diff.json; touch_flag ab_compare; launch; wait_for ab-diff.json 30
"${RUNAS[@]}" cat files/ab-diff.json
rm_file engine_go; rm_file engine_rust

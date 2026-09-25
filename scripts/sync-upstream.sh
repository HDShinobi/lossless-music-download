#!/usr/bin/env bash
#
# sync-upstream.sh — Pull SpotiFLAC upstream updates into this fork.
#
# Strategy: 3-way diff sync (no shared git history with upstream).
#   We keep a baseline tag `vendor/spotiflac-base` pointing at the exact
#   upstream commit our code is currently synced to. To absorb an upstream
#   release we compute the diff base..<target> for the INHERITED paths and
#   apply it 3-way onto our tree. Conflicts only appear where WE edited the
#   same lines upstream did (see docs/UPSTREAM-SYNC.md "Divergence registry").
#
# Usage:
#   scripts/sync-upstream.sh                 # preview against upstream/main
#   scripts/sync-upstream.sh v4.7.0          # preview against a release tag
#   scripts/sync-upstream.sh v4.7.0 --apply  # actually apply the 3-way patch
#
# After --apply succeeds and the verify steps pass (see "Next steps" output),
# run `scripts/sync-upstream.sh --check-vendored`, then advance the baseline:
#   git tag -f vendor/spotiflac-base <target-sha>
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BASE_TAG="vendor/spotiflac-base"
TARGET="${1:-upstream/main}"
APPLY=false
[[ "${2:-}" == "--apply" || "${1:-}" == "--apply" ]] && APPLY=true
[[ "${1:-}" == "--apply" ]] && TARGET="upstream/main"

# Paths we INHERIT from upstream (Layer 1, byte-identical except registered
# LM-FORK(<id>) blocks). lib/ and our Kotlin glue are ours — never synced.
# go_backend/ is frozen at vendor/spotiflac-go-final until it is removed.
INHERIT_PATHS=(
  rust_backend
  scripts/build_rust_backend.sh
  android/app/src/main/kotlin/com/zarz/spotiflac/CoreBackend.kt
)
# Upstream files we do NOT vendor but port from by hand; their diff-stat is
# reported on every sync so glue changes are not missed.
WATCH_PATHS=(
  android/app/src/rust/kotlin
  android/app/src/main/kotlin/com/zarz/spotiflac
  android/app/build.gradle.kts
  lib/services/platform_bridge.dart
)
ENGINE_VERSION_FILE="android/app/src/main/kotlin/xyz/losslessmusic/app/engine/EngineVersion.kt"
REGISTRY="docs/UPSTREAM-SYNC.md"

check_vendored() {
  local fail=0 f
  echo "==> Layer 1 vs baseline ($BASE_TAG):"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$f" == */tests/lm_* ]] || grep -q 'LM-FORK(' "$f" 2>/dev/null; then
      echo "    ok (registered fork file): $f"
    else
      echo "    !! $f differs from baseline without an LM-FORK(<id>) marker"; fail=1
    fi
  done < <( { git diff --name-only "$BASE_TAG" -- "${INHERIT_PATHS[@]}";
              git ls-files --others --exclude-standard -- "${INHERIT_PATHS[@]}"; } | sort -u )

  local code_ids reg_ids
  code_ids="$(git grep --untracked -hoE 'LM-FORK\([a-z0-9-]+\)' -- "${INHERIT_PATHS[@]}" 2>/dev/null \
              | sed -E 's/LM-FORK\((.*)\)/\1/' | sort -u | tr '\n' ' ' || true)"
  reg_ids="$(grep -oE '^\| `LM-FORK\([a-z0-9-]+\)`' "$REGISTRY" \
              | sed -E 's/.*LM-FORK\((.*)\).*/\1/' | sort -u | tr '\n' ' ' || true)"
  if [[ "$code_ids" != "$reg_ids" ]]; then
    echo "    !! LM-FORK ids in code [${code_ids}] != active registry rows [${reg_ids}]"; fail=1
  else
    echo "    LM-FORK ids match registry: [${code_ids}]"
  fi

  local tag_ver const_ver
  tag_ver="$(git tag --points-at "$BASE_TAG^{commit}" | grep -E '^v[0-9]' | head -1 | sed 's/^v//')"
  const_ver="$(sed -nE 's/.*SPOTIFLAC_ENGINE_VERSION *= *"([^"]+)".*/\1/p' "$ENGINE_VERSION_FILE")"
  if [[ -z "$tag_ver" ]]; then
    echo "    (baseline is not a release tag — engine version check skipped)"
  elif [[ "$tag_ver" != "$const_ver" ]]; then
    echo "    !! SPOTIFLAC_ENGINE_VERSION=$const_ver but baseline is v$tag_ver — bump EngineVersion.kt"; fail=1
  else
    echo "    SPOTIFLAC_ENGINE_VERSION=$const_ver matches baseline"
  fi
  return $fail
}

if [[ "${1:-}" == "--check-vendored" ]]; then
  check_vendored && echo "✓ Layer 1 vendored cleanly." && exit 0
  echo "✗ Layer 1 check failed."; exit 1
fi

# A locally available target at the baseline needs no fetch. This also keeps
# an in-sync preview read-only; other targets still refresh upstream tags.
if git rev-parse --verify --quiet "$BASE_TAG^{commit}" >/dev/null &&
   git rev-parse --verify --quiet "$TARGET^{commit}" >/dev/null &&
   [[ "$(git rev-parse "$BASE_TAG^{commit}")" == "$(git rev-parse "$TARGET^{commit}")" ]]; then
  BASE_SHA="$(git rev-parse --short "$BASE_TAG^{commit}")"
  TARGET_SHA="$(git rev-parse --short "$TARGET^{commit}")"
  echo "==> Baseline : $BASE_SHA  ($(git show -s --format=%s "$BASE_TAG^{commit}"))"
  echo "==> Target   : $TARGET_SHA  ($(git show -s --format=%s "$TARGET^{commit}"))"
  echo "==> Paths    : ${INHERIT_PATHS[*]}"
  echo
  echo "Already in sync — baseline == target. Nothing to do."
  exit 0
fi

echo "==> Fetching upstream tags…"
# Non-fatal: a sync can legitimately run offline against tags already in this
# repo (or against a local clone). If the target ref is genuinely missing the
# resolve check below fails with a clear message anyway.
if ! git fetch upstream --tags --quiet 2>/dev/null; then
  echo "    Fetch failed (offline?) — using the tags already present locally."
fi

if ! git rev-parse --verify --quiet "$BASE_TAG" >/dev/null; then
  echo "ERROR: baseline tag '$BASE_TAG' not found. Create it first:" >&2
  echo "  git tag vendor/spotiflac-base <upstream-sha-we-are-synced-to>" >&2
  exit 1
fi
if ! git rev-parse --verify --quiet "$TARGET^{commit}" >/dev/null; then
  echo "ERROR: target '$TARGET' is not a valid commit/tag." >&2
  exit 1
fi

BASE_SHA="$(git rev-parse --short "$BASE_TAG^{commit}")"
TARGET_SHA="$(git rev-parse --short "$TARGET^{commit}")"

echo "==> Baseline : $BASE_SHA  ($(git show -s --format=%s "$BASE_TAG^{commit}"))"
echo "==> Target   : $TARGET_SHA  ($(git show -s --format=%s "$TARGET^{commit}"))"
echo "==> Paths    : ${INHERIT_PATHS[*]}"
echo

if [[ "$BASE_SHA" == "$TARGET_SHA" ]]; then
  echo "Already in sync — baseline == target. Nothing to do."
  exit 0
fi

echo "==> Upstream changes in inherited paths ($BASE_SHA..$TARGET_SHA):"
git diff --stat "$BASE_TAG" "$TARGET" -- "${INHERIT_PATHS[@]}" || true
echo
echo "==> Upstream changes in WATCHED (not vendored) paths — port by hand if relevant:"
git diff --stat "$BASE_TAG" "$TARGET" -- "${WATCH_PATHS[@]}" || true
echo

PATCH="$(mktemp -t spotiflac-sync.XXXXXX.patch)"
git diff "$BASE_TAG" "$TARGET" -- "${INHERIT_PATHS[@]}" >"$PATCH"

if [[ ! -s "$PATCH" ]]; then
  echo "No changes to inherited paths. Safe to just advance the baseline tag:"
  echo "  git tag -f $BASE_TAG $TARGET_SHA"
  rm -f "$PATCH"
  exit 0
fi

echo "==> Checking how the patch applies (3-way dry run)…"
if git apply --3way --check "$PATCH" 2>/tmp/sync-apply.err; then
  echo "    Clean — applies without conflicts."
else
  echo "    Will produce conflicts in files we modified in place:"
  sed 's/^/      /' /tmp/sync-apply.err || true
  echo "    (expected for files in docs/UPSTREAM-SYNC.md divergence registry)"
fi
echo

if [[ "$APPLY" != true ]]; then
  echo "Preview only. Re-run with --apply to perform the 3-way merge:"
  echo "  scripts/sync-upstream.sh $TARGET --apply"
  echo "Patch saved at: $PATCH"
  exit 0
fi

echo "==> Applying 3-way…"
if git apply --3way --whitespace=nowarn "$PATCH"; then
  echo "    Applied cleanly."
else
  echo
  echo "!! Conflicts left in the working tree (look for <<<<<<< markers)."
  echo "   Resolve them, keeping OUR intentional changes (see UPSTREAM-SYNC.md),"
  echo "   then continue with the verification steps below."
fi

cat <<EOF

==> Next steps:
  1. Resolve conflict markers: git grep -n '<<<<<<<' -- ${INHERIT_PATHS[*]}
     Keep our LM-FORK(<id>) intent, or take upstream's hunk if it now contains the fix.
  2. Bump SPOTIFLAC_ENGINE_VERSION in $ENGINE_VERSION_FILE to the target version.
  3. Verify:
       (cd rust_backend && cargo test --locked -p spotiflac-extensions)
       (cd android && ./gradlew :app:buildRustBackend :app:testDebugUnitTest :app:assembleDebug)
       flutter test
  4. Review the WATCHED diff-stat above and port relevant glue changes by hand.
  5. Advance the baseline, then prove Layer 1 is clean:
       git tag -f $BASE_TAG $TARGET_SHA
       scripts/sync-upstream.sh --check-vendored
  6. Commit, and update $REGISTRY (baseline, registry rows).

Patch file: $PATCH
EOF

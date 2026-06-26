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
# After --apply succeeds AND `cd go_backend && go build ./... && go test ./...`
# pass, advance the baseline:
#   git tag -f vendor/spotiflac-base <target-sha>
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BASE_TAG="vendor/spotiflac-base"
TARGET="${1:-upstream/main}"
APPLY=false
[[ "${2:-}" == "--apply" || "${1:-}" == "--apply" ]] && APPLY=true
[[ "${1:-}" == "--apply" ]] && TARGET="upstream/main"

# Paths we INHERIT from upstream. lib/ (Flutter) is a fresh rebuild and is
# intentionally excluded — we follow upstream patterns there, not files.
INHERIT_PATHS=(go_backend)

echo "==> Fetching upstream tags…"
git fetch upstream --tags --quiet

if ! git rev-parse --verify --quiet "$BASE_TAG" >/dev/null; then
  echo "ERROR: baseline tag '$BASE_TAG' not found. Create it first:" >&2
  echo "  git tag vendor/spotiflac-base <upstream-sha-we-are-synced-to>" >&2
  exit 1
fi
if ! git rev-parse --verify --quiet "$TARGET^{commit}" >/dev/null; then
  echo "ERROR: target '$TARGET' is not a valid commit/tag." >&2
  exit 1
fi

BASE_SHA="$(git rev-parse --short "$BASE_TAG")"
TARGET_SHA="$(git rev-parse --short "$TARGET")"

echo "==> Baseline : $BASE_SHA  ($(git show -s --format=%s "$BASE_TAG"))"
echo "==> Target   : $TARGET_SHA  ($(git show -s --format=%s "$TARGET"))"
echo "==> Paths    : ${INHERIT_PATHS[*]}"
echo

if [[ "$BASE_SHA" == "$TARGET_SHA" ]]; then
  echo "Already in sync — baseline == target. Nothing to do."
  exit 0
fi

echo "==> Upstream changes in inherited paths ($BASE_SHA..$TARGET_SHA):"
git diff --stat "$BASE_TAG" "$TARGET" -- "${INHERIT_PATHS[@]}" || true
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
  1. Resolve any conflict markers (grep -rn '<<<<<<<' go_backend).
  2. cd go_backend && go build ./... && go test ./...
  3. Audit the bridge contract (catches changed export signatures):
       cd native/bridge && go build ./...          # authoritative check
       scripts/snapshot-bridge-contract.sh --check  # diffable signatures
     If it drifts, update native/bridge/bridge.go + lib/services/backend_bridge.dart.
  4. Rebuild the AAR / run app smoke test.
  5. When green, refresh the contract snapshot + advance the baseline + commit:
       scripts/snapshot-bridge-contract.sh
       git tag -f $BASE_TAG $TARGET_SHA
       git add -A && git commit -m "chore(upstream): sync go_backend to $TARGET"
  6. Update docs/UPSTREAM-SYNC.md (base version + any new divergences).

Patch file: $PATCH
EOF

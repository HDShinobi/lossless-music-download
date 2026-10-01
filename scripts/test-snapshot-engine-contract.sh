#!/usr/bin/env bash
# Catch a checker that accepts signature drift or ignores CONTRACT_FILE.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! bash scripts/snapshot-engine-contract.sh --check >"$TMP_DIR/clean.log" 2>&1; then
  cat "$TMP_DIR/clean.log"
  echo 'FAIL: unchanged engine contract must pass' >&2
  exit 1
fi
echo 'PASS: unchanged engine contract'

cp docs/engine-contract.txt "$TMP_DIR/contract.txt"
python3 - "$TMP_DIR/contract.txt" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
lines = path.read_text().splitlines()
for i, line in enumerate(lines):
    if line.startswith('loadAll | '):
        lines[i] = line.replace('kotlin.String', 'kotlin.Int', 1)
        assert lines[i] != line, 'loadAll return signature not found'
        break
else:
    raise SystemExit('loadAll contract not found')
path.write_text('\n'.join(lines) + '\n')
PY
set +e
CONTRACT_FILE="$TMP_DIR/contract.txt" bash scripts/snapshot-engine-contract.sh --check >"$TMP_DIR/drift.log" 2>&1
result=$?
set -e
if [[ "$result" != 1 ]] || ! grep -q '^[-+]loadAll | ' "$TMP_DIR/drift.log"; then
  cat "$TMP_DIR/drift.log"
  echo "FAIL: altered loadAll signature must produce exit 1 and a named diff (got $result)" >&2
  exit 1
fi
echo 'PASS: altered loadAll signature rejected (exit 1, named diff)'

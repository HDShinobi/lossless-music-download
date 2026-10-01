#!/usr/bin/env bash
# Snapshot UniFFI methods called by app-owned Kotlin glue. Kotlin compilation
# remains authoritative; this makes Kotlin/Rust signature drift reviewable.
# Usage: scripts/snapshot-engine-contract.sh [--check]
# CONTRACT_FILE overrides docs/engine-contract.txt (also used by the drift test).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT="${CONTRACT_FILE:-docs/engine-contract.txt}"
case "${1:-}" in
  ''|--check) ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac
BINDINGS="rust_backend/target/bindings/kotlin/com/spotiflac/backend/spotiflac_mobile.kt"
if [[ ! -f "$BINDINGS" ]]; then
  echo 'ERROR: Kotlin bindings missing. Run (cd android && ./gradlew :app:buildRustBackend).' >&2
  exit 2
fi
TEMP_CONTRACT="$(mktemp)"
trap 'rm -f "$TEMP_CONTRACT"' EXIT
python3 - "$BINDINGS" >"$TEMP_CONTRACT" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

bindings = Path(sys.argv[1]).read_text()
app = Path('android/app/src/main/kotlin/xyz/losslessmusic/app')
sources = [p.read_text() for p in sorted(app.rglob('*.kt'))]
sources = [s for s in sources if re.search(r'^import com\.spotiflac\.backend\.', s, re.M)]
# Only declaration signatures, never generated FFI/lowering functions. Keep the
# owner internally to disambiguate names shared by several UniFFI objects.
methods = {}
for match in re.finditer(r'^public interface (\w+)Interface\s*\{(.*?)^\}', bindings, re.M | re.S):
    owner, body = match.groups()
    for fn in re.finditer(r'fun `?(\w+)`?\(([^\n]*)\)(?:: ([^\n]+))?', body):
        name, args, result = fn.groups()
        methods.setdefault(name, []).append((owner, f'fun {name}({args}): {result or "kotlin.Unit"}'))
# Named constructors live in the companion rather than the object interface.
for match in re.finditer(r'^open class (\w+):(.*?)(?=^open class |^data class |\Z)', bindings, re.M | re.S):
    owner, body = match.groups()
    for fn in re.finditer(r'(?<!override )fun `(\w+)`\(([^\n]*)\): (\w+) \{', body):
        name, args, result = fn.groups()
        if result == owner:
            methods.setdefault(name, []).append((owner, f'fun {name}({args}): {result}'))

# Infer named binding receivers from types, constructors and binding return
# values. Lambda receivers are conservative: consider returned binding types,
# but never treat a call on an unrelated named object as an engine call.
calls = set()
owners = set()
constructors = set()
lambda_owners = set()
receivers = {}
assignments = []
for source in sources:
    source = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"', '', source, flags=re.S)
    imported = set(re.findall(r'^import com\.spotiflac\.backend\.(\w+)', source, re.M))
    owners.update(imported)
    calls.update(re.findall(r'(\w+)\s*\.\s*`?(\w+)`?\s*\(', source))
    constructors.update(name for name in imported if re.search(r'\b' + name + r'\s*\(', source))
    for variable, typ in re.findall(r'\b(\w+)\s*:\s*(\w+)', source):
        if typ in imported:
            receivers.setdefault(variable, set()).add(typ)
    for variable, typ in re.findall(r'\b(?:val|var)\s+(\w+)\s*=\s*(\w+)\s*\(', source):
        if typ in imported:
            receivers.setdefault(variable, set()).add(typ)
    assignments += re.findall(r'\b(?:val|var)\s+(\w+)\s*=([^\n]+)', source)
# Kotlin lambda parameters may be implicit `it` or explicit `e`/`lease`.
lambda_names = {'it'}
for source in sources:
    lambda_names.update(re.findall(r'\{\s*(\w+)\s*->', source))
while True:
    previous = repr((sorted(owners), sorted((k, sorted(v)) for k, v in receivers.items())))
    for receiver, name in calls:
        candidates = receivers.get(receiver, set()) | ({receiver} if receiver in owners else set())
        if receiver in lambda_names:
            candidates |= lambda_owners
        for owner, signature in methods.get(name, []):
            if owner in candidates:
                lambda_owners.update(typ for typ in re.findall(r'\b[A-Z]\w*\b', signature.split('): ', 1)[-1]) if typ != owner)
    owners.update(lambda_owners)
    for variable, expression in assignments:
        for receiver, name in re.findall(r'(\w+)\.(\w+)\s*\(', expression):
            candidates = lambda_owners if receiver in lambda_names else receivers.get(receiver, set())
            for owner, signature in methods.get(name, []):
                if owner in candidates:
                    receivers.setdefault(variable, set()).update(re.findall(r'\b[A-Z]\w*\b', signature.split('): ', 1)[-1]))
    if repr((sorted(owners), sorted((k, sorted(v)) for k, v in receivers.items()))) == previous:
        break
selected = set()
for receiver, name in calls:
    candidates = receivers.get(receiver, set()) | ({receiver} if receiver in owners else set())
    if receiver in lambda_names:
        candidates |= lambda_owners
    for owner, signature in methods.get(name, []):
        if owner in candidates:
            selected.add((owner, name, signature))
    if receiver not in lambda_names and candidates and name not in {'close', 'use'}:
        if not any(owner in candidates for owner, _ in methods.get(name, [])):
            raise SystemExit(f'ERROR: missing Kotlin binding signature for {receiver}.{name}')
# Object constructors are real UniFFI calls; record constructors such as
# CancellationRegistry(domain), but not Kotlin data records (LyricsRequest).
for owner in constructors:
    match = re.search(r'^open class ' + owner + r':(.*?)(?=^open class |\Z)', bindings, re.M | re.S)
    if match:
        for args in re.findall(r'^    constructor\(([^\n]*)\) :', match.group(1), re.M):
            selected.add((owner, owner, f'constructor({args}): {owner}'))
if not selected:
    raise SystemExit('ERROR: no called UniFFI signatures found')

pathspec = ':(top,glob)rust_backend/crates/mobile/src/*.rs'
def grep(pattern, context=None):
    args = ['git', 'grep', '-n']
    if context is not None:
        args += [f'-A{context}']
    proc = subprocess.run(args + ['-E', pattern, '--', pathspec], text=True, capture_output=True)
    if proc.returncode not in (0, 1):
        raise SystemExit(proc.stderr)
    rows = {}
    for line in proc.stdout.splitlines():
        match = re.match(r'^(.*\.rs)[:-](\d+)[:-](.*)$', line)
        if match:
            path, number, text = match.groups()
            rows.setdefault(path, {})[int(number)] = text
    return rows

impls = grep(r'^impl [A-Za-z_][A-Za-z0-9_]*')
def normalize(value):
    return ' '.join(value.replace('`', '').split())

lines = set()
for owner, name, kotlin in sorted(selected):
    snake = 'new' if name == owner else re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()
    pattern = r'pub fn ' + snake + r'\('
    signatures = set()
    # Start at the mandated -A6; extend only for signatures spanning more lines.
    for context in (6, 12, 24, 48):
        rows = grep(pattern, context)
        incomplete = False
        for path, content in rows.items():
            for number, text in content.items():
                if not re.search(pattern, text):
                    continue
                preceding = [(n, t) for n, t in impls.get(path, {}).items() if n < number]
                if not preceding:
                    continue
                impl = max(preceding)[1]
                if not re.match(r'^impl ' + owner + r'\b', impl):
                    continue
                chunk = '\n'.join(content.get(n, '') for n in range(number, number + context + 1))
                signature = re.search(pattern + r'.*?\)\s*(?:->\s*[^{}]+)?\s*\{', chunk, re.S)
                if signature:
                    signatures.add(normalize(signature.group().rsplit('{', 1)[0]))
                else:
                    incomplete = True
        if not incomplete:
            break
    if len(signatures) != 1 or incomplete:
        raise SystemExit(f'ERROR: expected one complete Rust signature for {owner}.{name}, got {sorted(signatures)}')
    lines.add(f'{name} | {normalize(kotlin)} | {signatures.pop()}')
print('\n'.join(sorted(lines)))
PY
if [[ "${1:-}" == --check ]]; then
  if diff -u "$OUT" "$TEMP_CONTRACT"; then
    echo '✓ Engine contract unchanged vs snapshot.'
  else
    echo 'Engine contract drift detected. Review Kotlin glue and Rust signatures, then regenerate the snapshot.' >&2
    exit 1
  fi
else
  cp "$TEMP_CONTRACT" "$OUT"
  echo "Wrote $OUT"
fi

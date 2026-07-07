#!/bin/bash
# M8 / AC4-025: kill-mid-batch and relaunch hardening check for sidecar-only
# mode. Requires a running Ollama with a vision model.
#
#   Scripts/m8-kill-relaunch-check.sh [count] [model]
#
# What it proves:
#  1. SIGKILL mid-analyze leaves no ambiguous file state: no atomic-writer
#     temp files, every existing .ai.json parses.
#  2. Relaunch + re-run completes the set via existing-skip semantics.
#  3. The CLI normalize/apply-session follow-through produces well-formed
#     XMP with no temp files (analyze -> normalize -> apply parity).
#  4. No database file exists anywhere under the app state directory.
set -euo pipefail

COUNT="${1:-6}"
MODEL="${2:-qwen2.5vl:7b}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /tmp/m8-check-XXXXXX)"
FIXTURE="$WORK/photos"
STATE_DIR="$HOME/Library/Application Support/CupricAspect"
APP="$REPO/.build/debug/CupricAspect"

cleanup() { pkill -x CupricAspect 2>/dev/null || true; }
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

count_sidecars() { find "$FIXTURE" -name "*.ai.json" 2>/dev/null | wc -l | tr -d ' '; }

assert_no_temp_files() {
  local strays
  strays=$(find "$1" -name ".*.tmp*" 2>/dev/null | wc -l | tr -d ' ')
  [ "$strays" = "0" ] || fail "atomic-writer temp files left behind in $1"
}

assert_sidecars_parse() {
  find "$FIXTURE" -name "*.ai.json" -print0 | while IFS= read -r -d '' f; do
    /usr/bin/python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" \
      || fail "unparseable sidecar after kill: $f"
  done
}

wait_for_sidecars() { # $1 = minimum count, $2 = timeout seconds
  local deadline=$((SECONDS + $2))
  while [ "$(count_sidecars)" -lt "$1" ]; do
    [ $SECONDS -lt $deadline ] || fail "timed out waiting for $1 sidecars (have $(count_sidecars))"
    sleep 2
  done
}

echo "== building =="
(cd "$REPO" && swift build --product CupricAspect >/dev/null && swift build --product aisidecar >/dev/null)

echo "== fixture: $COUNT images at $FIXTURE =="
(cd "$REPO" && swift Scripts/generate-synthetic-fixture.swift "$FIXTURE" "$COUNT" >/dev/null)
rm -f "$FIXTURE"/*.ai.json   # all assets start un-analyzed

echo "== phase 1: launch, kill mid-batch =="
CUPRIC_IMPORT_PATH="$FIXTURE" CUPRIC_DEBUG_AUTORUN=1 AISIDECAR_MODEL="$MODEL" "$APP" &
APP_PID=$!
wait_for_sidecars 1 600
kill -9 "$APP_PID" 2>/dev/null || true
sleep 1
PARTIAL=$(count_sidecars)
echo "   killed with $PARTIAL/$COUNT sidecars written"
[ "$PARTIAL" -lt "$COUNT" ] || echo "   (note: run finished before the kill — resume phase still verifies idempotence)"
assert_no_temp_files "$FIXTURE"
assert_sidecars_parse

echo "== phase 2: relaunch, resume to completion =="
CUPRIC_IMPORT_PATH="$FIXTURE" CUPRIC_DEBUG_AUTORUN=1 AISIDECAR_MODEL="$MODEL" "$APP" &
wait_for_sidecars "$COUNT" 900
pkill -x CupricAspect || true
sleep 1
assert_no_temp_files "$FIXTURE"
assert_sidecars_parse
echo "   resumed to $(count_sidecars)/$COUNT"

echo "== phase 3: CLI normalize + apply-session follow-through =="
(cd "$REPO" && swift run -q aisidecar normalize --from-json "$FIXTURE" --source-root "$FIXTURE" \
  --session-only --output-dir "$WORK/norm" >/dev/null 2>&1) || fail "normalize failed"
SESSION=$(ls "$WORK/norm"/normalization-session-*.json | head -1)
(cd "$REPO" && swift run -q aisidecar apply-session "$SESSION" --source-root "$FIXTURE" \
  --output-dir "$WORK/xmp" >/dev/null 2>&1) || fail "apply-session failed"
XMP_COUNT=$(find "$WORK/xmp" -name "*.xmp" | wc -l | tr -d ' ')
[ "$XMP_COUNT" -ge 1 ] || fail "no XMP written by apply-session"
find "$WORK/xmp" -name "*.xmp" -print0 | while IFS= read -r -d '' f; do
  /usr/bin/python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$f" \
    || fail "malformed XMP: $f"
done
assert_no_temp_files "$WORK/xmp"
echo "   $XMP_COUNT well-formed XMP sidecars"

echo "== phase 4: AC4-025 — no database anywhere =="
if [ -d "$STATE_DIR" ]; then
  DB_FILES=$(find "$STATE_DIR" \( -name "*.sqlite*" -o -name "*.db" \) | wc -l | tr -d ' ')
  [ "$DB_FILES" = "0" ] || fail "database file found under $STATE_DIR"
fi

rm -rf "$WORK"
echo "PASS: kill/relaunch, resume, CLI parity, and no-database checks all green"

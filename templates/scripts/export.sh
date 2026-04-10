#!/bin/bash
# Copies the current session transcript to .chat-sync/
# Triggered by: Copilot Stop hook, Cursor sessionEnd hook

INPUT=$(cat)

# Extract transcript_path from stdin JSON
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('transcript_path') or '')
" 2>/dev/null || true)

# Fallback to Cursor env var (set when transcripts are enabled)
if [ -z "$TRANSCRIPT_PATH" ]; then
  TRANSCRIPT_PATH="${CURSOR_TRANSCRIPT_PATH:-}"
fi

[ -z "$TRANSCRIPT_PATH" ] && exit 0
[ ! -f "$TRANSCRIPT_PATH" ] && exit 0

# Determine workspace root
if [ -n "${CURSOR_PROJECT_DIR:-}" ]; then
  WORKSPACE="$CURSOR_PROJECT_DIR"
else
  WORKSPACE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('cwd') or '')
" 2>/dev/null || true)
fi

[ -z "$WORKSPACE" ] && WORKSPACE="$PWD"

SYNC_DIR="$WORKSPACE/.chat-sync"
mkdir -p "$SYNC_DIR"

DEST="$SYNC_DIR/$(basename "$TRANSCRIPT_PATH")"

# Only copy if content has changed (avoid redundant writes)
if [ ! -f "$DEST" ] || ! cmp -s "$TRANSCRIPT_PATH" "$DEST"; then
  cp "$TRANSCRIPT_PATH" "$DEST"
fi

exit 0

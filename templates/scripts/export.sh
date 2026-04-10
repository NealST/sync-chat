#!/bin/bash
# Copies the current session transcript to .chat-sync/
# Triggered by: Copilot Stop hook, Cursor sessionEnd hook

INPUT=$(cat)

# Parse --agent <name> argument (passed explicitly by each hook config)
AGENT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --agent) AGENT="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -z "$AGENT" ] && AGENT="unknown"

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
WORKSPACE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('cwd') or (d.get('workspace_roots') or [''])[0] or '')
" 2>/dev/null || true)
# Cursor provides this env var; use it as a fallback
[ -z "$WORKSPACE" ] && WORKSPACE="${CURSOR_PROJECT_DIR:-}"
[ -z "$WORKSPACE" ] && WORKSPACE="$PWD"

# Write to agent-specific subdirectory to avoid cross-agent pollution
SYNC_DIR="$WORKSPACE/.chat-sync/$AGENT"
mkdir -p "$SYNC_DIR"

DEST="$SYNC_DIR/$(basename "$TRANSCRIPT_PATH")"

# Only copy if content has changed (avoid redundant writes)
if [ ! -f "$DEST" ] || ! cmp -s "$TRANSCRIPT_PATH" "$DEST"; then
  cp "$TRANSCRIPT_PATH" "$DEST"
fi

exit 0

#!/bin/bash
# Restores session transcripts from .chat-sync/ into the agent's local storage
# Triggered by: Copilot SessionStart hook, Cursor sessionStart hook

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

# Determine workspace root
WORKSPACE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('cwd') or (d.get('workspace_roots') or [''])[0] or '')
" 2>/dev/null || true)
# Cursor provides this env var; use it as a fallback
[ -z "$WORKSPACE" ] && WORKSPACE="${CURSOR_PROJECT_DIR:-}"
[ -z "$WORKSPACE" ] && WORKSPACE="$PWD"

AGENT_SYNC_DIR="$WORKSPACE/.chat-sync/$AGENT"

# Nothing to restore if no .jsonl files present
if [ ! -d "$AGENT_SYNC_DIR" ] || ! ls "$AGENT_SYNC_DIR"/*.jsonl &>/dev/null; then
  echo '{}'
  exit 0
fi

RESTORED=0

if [ "$AGENT" = "cursor" ]; then
  # Cursor stores transcripts at:
  # ~/.cursor/projects/<encoded-path>/agent-transcripts/<session-id>/<session-id>.jsonl
  # Encoding: strip leading /, replace / with -
  ENCODED_PATH=$(printf '%s' "$WORKSPACE" | sed 's|^/||; s|/|-|g')
  TRANSCRIPTS_BASE="$HOME/.cursor/projects/$ENCODED_PATH/agent-transcripts"

  for f in "$AGENT_SYNC_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    SESSION_ID=$(basename "$f" .jsonl)
    TARGET="$TRANSCRIPTS_BASE/$SESSION_ID/$SESSION_ID.jsonl"
    if [ ! -f "$TARGET" ] || ! cmp -s "$f" "$TARGET"; then
      mkdir -p "$(dirname "$TARGET")"
      cp "$f" "$TARGET"
      RESTORED=$((RESTORED + 1))
    fi
  done

elif [ "$AGENT" = "copilot" ]; then
  # Copilot (VS Code) stores transcripts at:
  # ~/Library/Application Support/Code/User/workspaceStorage/<hash>/chatSessions/<session-id>.jsonl
  # The <hash> is derived from the workspace URI — find it by scanning workspace.json files

  if [[ "$OSTYPE" == "darwin"* ]]; then
    WS_STORAGE="$HOME/Library/Application Support/Code/User/workspaceStorage"
  else
    WS_STORAGE="$HOME/.config/Code/User/workspaceStorage"
  fi

  WS_DIR=$(python3 - "$WS_STORAGE" "$WORKSPACE" <<'PYEOF'
import sys, json, os
ws_storage, workspace = sys.argv[1], sys.argv[2]
workspace_uri = "file://" + workspace

if not os.path.isdir(ws_storage):
    sys.exit(0)

for entry in os.listdir(ws_storage):
    ws_json = os.path.join(ws_storage, entry, "workspace.json")
    if not os.path.isfile(ws_json):
        continue
    try:
        with open(ws_json) as f:
            d = json.load(f)
        folder = d.get("folder", "") or d.get("workspaceUri", "")
        if folder.rstrip("/") == workspace_uri.rstrip("/"):
            print(os.path.join(ws_storage, entry))
            break
    except Exception:
        pass
PYEOF
)

  if [ -n "$WS_DIR" ]; then
    CHAT_SESSIONS="$WS_DIR/chatSessions"
    mkdir -p "$CHAT_SESSIONS"

    for f in "$AGENT_SYNC_DIR"/*.jsonl; do
      [ -f "$f" ] || continue
      TARGET="$CHAT_SESSIONS/$(basename "$f")"
      if [ ! -f "$TARGET" ] || ! cmp -s "$f" "$TARGET"; then
        cp "$f" "$TARGET"
        RESTORED=$((RESTORED + 1))
      fi
    done
  fi
fi

# Return result — inform the agent how many sessions were restored
if [ "$RESTORED" -gt 0 ]; then
  MSG="${RESTORED} past chat session(s) restored from .chat-sync/ and are now available in your chat history."
  MSG_JSON=$(python3 -c "import json, sys; print(json.dumps(sys.argv[1]))" "$MSG")
  if [ "$AGENT" = "cursor" ]; then
    printf '{"additional_context": %s}\n' "$MSG_JSON"
  else
    printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": %s}}\n' "$MSG_JSON"
  fi
else
  echo '{}'
fi

exit 0

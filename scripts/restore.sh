#!/bin/bash
# Restores session transcripts from .chat-sync/ into the agent's local storage
# Triggered by: Copilot SessionStart hook, Cursor sessionStart hook

INPUT=$(cat)

# Determine workspace root and agent type
if [ -n "${CURSOR_PROJECT_DIR:-}" ]; then
  WORKSPACE="$CURSOR_PROJECT_DIR"
  IS_CURSOR=1
else
  WORKSPACE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('cwd') or '')
" 2>/dev/null || true)
  IS_CURSOR=0
fi

[ -z "$WORKSPACE" ] && WORKSPACE="$PWD"

SYNC_DIR="$WORKSPACE/.chat-sync"

# Nothing to restore if no .jsonl files present
if [ ! -d "$SYNC_DIR" ] || ! ls "$SYNC_DIR"/*.jsonl &>/dev/null; then
  echo '{}'
  exit 0
fi

RESTORED=0

if [ "$IS_CURSOR" = "1" ]; then
  # Cursor stores transcripts at:
  # ~/.cursor/projects/<encoded-path>/agent-transcripts/<session-id>/<session-id>.jsonl
  # Encoding: strip leading /, replace / with -
  ENCODED_PATH=$(printf '%s' "$WORKSPACE" | sed 's|^/||; s|/|-|g')
  TRANSCRIPTS_BASE="$HOME/.cursor/projects/$ENCODED_PATH/agent-transcripts"

  for f in "$SYNC_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    SESSION_ID=$(basename "$f" .jsonl)
    TARGET="$TRANSCRIPTS_BASE/$SESSION_ID/$SESSION_ID.jsonl"
    if [ ! -f "$TARGET" ]; then
      mkdir -p "$(dirname "$TARGET")"
      cp "$f" "$TARGET"
      RESTORED=$((RESTORED + 1))
    fi
  done

else
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

    for f in "$SYNC_DIR"/*.jsonl; do
      [ -f "$f" ] || continue
      TARGET="$CHAT_SESSIONS/$(basename "$f")"
      if [ ! -f "$TARGET" ]; then
        cp "$f" "$TARGET"
        RESTORED=$((RESTORED + 1))
      fi
    done
  fi
fi

# Return result — inform the agent how many sessions were restored
if [ "$RESTORED" -gt 0 ]; then
  MSG="${RESTORED} past chat session(s) restored from .chat-sync/ and are now available in your chat history."
  if [ "$IS_CURSOR" = "1" ]; then
    printf '{"additional_context": "%s"}\n' "$MSG"
  else
    printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s"}}\n' "$MSG"
  fi
else
  echo '{}'
fi

exit 0

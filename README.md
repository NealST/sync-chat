# sync-chat

Keep your AI agent chat history in sync across devices via git.

When you work on the same repository from multiple machines, conversation history with agents like **GitHub Copilot** and **Cursor** stays local and gets lost when you switch devices. `sync-chat` hooks into the agent lifecycle to automatically copy session transcripts into your repository's `.chat-sync/` directory — so a simple `git pull` on another machine restores your full chat history.

## How it works

`sync-chat` installs two shell scripts and two hook configuration files into your project:

```
your-project/
  .github/hooks/sync-chat.json   ← GitHub Copilot hook config
  .cursor/hooks.json             ← Cursor hook config
  scripts/
    export.sh                    ← runs when a session ends
    restore.sh                   ← runs when a new session starts
```

| Event | Agent | Script | What happens |
|-------|-------|--------|-------------|
| Session ends | Copilot `Stop` / Cursor `sessionEnd` | `export.sh` | Reads `transcript_path` from stdin, copies the `.jsonl` file to `.chat-sync/` |
| Session starts | Copilot `SessionStart` / Cursor `sessionStart` | `restore.sh` | Copies any `.jsonl` files from `.chat-sync/` that are missing from the agent's local storage |

Commits and pushes are intentionally **left to you** — sync-chat never runs `git` commands automatically.

## Requirements

- Node.js ≥ 16 (for the installer CLI)
- Python 3 (used inside the shell scripts — available by default on macOS/Linux)
- `bash`

## Installation

In the root of your project, run:

```bash
npx sync-chat
```

This copies the hook configs and scripts into the current directory. To install into a different path:

```bash
npx sync-chat ./path/to/project
```

To overwrite files that already exist:

```bash
npx sync-chat --force
```

After installation, commit the generated files:

```bash
git add .github/hooks/ .cursor/hooks.json scripts/
git commit -m "chore: add sync-chat hooks"
git push
```

## Usage

Once committed, the sync is fully automatic:

**On the current machine:**
1. Work with Copilot or Cursor as usual.
2. When the agent session ends, `export.sh` copies the transcript to `.chat-sync/`.
3. Commit and push `.chat-sync/*.jsonl` along with your code changes.

**On another machine:**
1. `git pull` to get the latest code including `.chat-sync/`.
2. Open VS Code or Cursor. When a new agent session starts, `restore.sh` copies the transcripts back into the agent's local storage.
3. Your previous chat sessions are now available in the chat history panel.

## File structure after install

```
your-project/
  .chat-sync/              ← transcript files land here (commit these)
    <session-id>.jsonl
    <session-id>.jsonl
  .github/
    hooks/
      sync-chat.json       ← Copilot hook config (Stop + SessionStart)
  .cursor/
    hooks.json             ← Cursor hook config (sessionEnd + sessionStart)
  scripts/
    export.sh              ← copies transcript → .chat-sync/
    restore.sh             ← copies .chat-sync/ → agent local storage
```

Add `.chat-sync/*.jsonl` to git tracking (do **not** `.gitignore` it — that's the whole point).

## Supported agents

| Agent | Transcript storage | Hook config |
|-------|--------------------|-------------|
| GitHub Copilot (VS Code) | `~/Library/Application Support/Code/User/workspaceStorage/<hash>/chatSessions/` | `.github/hooks/sync-chat.json` |
| Cursor | `~/.cursor/projects/<encoded-path>/agent-transcripts/` | `.cursor/hooks.json` |

> **Claude Code** stores conversation history in the cloud (tied to your Anthropic account), so it doesn't need syncing — switching devices and logging in is enough.

## CLI reference

```
Usage: npx sync-chat [target-dir] [options]

  target-dir   Path to the project directory (default: current directory)

Options:
  --force, -f  Overwrite existing files
  --help,  -h  Show this help message
```

## License

MIT

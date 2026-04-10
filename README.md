# sync-chat

Sync AI agent chat history via git — across devices and across your team.

Chat history with agents like **GitHub Copilot** and **Cursor** is stored locally by default: it disappears when you switch machines, and teammates can't see it at all. `sync-chat` hooks into the agent lifecycle to automatically copy session transcripts into your repository's `.chat-sync/` directory, versioned alongside your code. Typical use cases:

- **Multiple devices**: seamlessly continue conversations between your work and home machines
- **Team collaboration**: decisions, dead ends, and context built up with an agent get pushed to git and pulled down by teammates — no need to re-explain the background

## How it works

### The idea

Agent chat transcripts are just files (`.jsonl`). `sync-chat` copies them into a `.chat-sync/` directory inside your repository. Once there, they follow the same git workflow as your code — commit, push, pull — and any machine or teammate that has the repo also has the full conversation history. On the receiving end, the transcripts are copied back into the agent's local storage so they show up in the chat history panel as if they had always been there.

Transcripts are stored in **agent-specific subdirectories** (`.chat-sync/copilot/`, `.chat-sync/cursor/`) to keep things clean. Commits and pushes are intentionally **left to you** — sync-chat never runs any git command automatically.

### Two ways to sync

`sync-chat` provides two approaches to move transcripts in and out of `.chat-sync/`. You can use either or both:

| | Agent hooks (automatic) | CLI commands (manual) |
|---|---|---|
| **How it works** | Hook config files tell the agent to run `export.sh` / `restore.sh` at session end / session start. Completely transparent — no plugin needed. | Run `npx sync-chat export` or `npx sync-chat restore` yourself whenever you want. |
| **User experience** | Zero friction. Transcripts appear in `.chat-sync/` after every session without you doing anything. | On-demand. Useful when hooks aren't available, or if you prefer explicit control. |
| **Requires** | Agent must support hooks (Copilot and Cursor both do). | Node.js ≥ 16. |

### Hooks in detail

Both Copilot and Cursor expose a **hook system** that lets you run shell commands at specific lifecycle events. `sync-chat` installs two hook config files and two scripts into your project:

```
your-project/
  .github/hooks/sync-chat.json   ← GitHub Copilot hook config
  .cursor/hooks.json             ← Cursor hook config
  scripts/
    export.sh                    ← runs when a session ends
    restore.sh                   ← runs when a new session starts
```

Each hook config passes `--agent <name>` explicitly to the scripts, so agent detection is unambiguous and extending to a new agent only requires adding a new hook config entry.

| Event | Agent | Script | What happens |
|-------|-------|--------|--------------|
| Session ends | Copilot `Stop` / Cursor `sessionEnd` | `export.sh` | Reads `transcript_path` from stdin, copies the `.jsonl` to `.chat-sync/<agent>/` |
| Session starts | Copilot `SessionStart` / Cursor `sessionStart` | `restore.sh` | Copies `.chat-sync/<agent>/*.jsonl` back into the agent's local storage; skips unchanged files |

## Requirements

- Node.js ≥ 16 (for the CLI)
- Python 3 (used inside the shell scripts — available by default on macOS/Linux)
- `bash`

## Installation

**Option A — via npm (requires Node.js ≥ 16):**

```bash
npx sync-chat
```

To install into a different path or overwrite existing files:

```bash
npx sync-chat install ./path/to/project
npx sync-chat install --force
```

**Option B — via curl (no Node.js required):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/sync-chat/main/install.sh)
```

Same options are supported:

```bash
# install into a specific directory
bash <(curl -fsSL ...) ./path/to/project

# overwrite existing files
bash <(curl -fsSL ...) --force
```

After installation, commit the generated files:

```bash
git add .github/hooks/ .cursor/hooks.json scripts/
git commit -m "chore: add sync-chat hooks"
git push
```

## Automatic sync (via hooks)

Once the hook files are committed, the sync runs automatically:

**On the current machine:**
1. Work with Copilot or Cursor as usual.
2. When the session ends, `export.sh` copies the transcript to `.chat-sync/<agent>/`.
3. Commit and push `.chat-sync/` along with your code changes.

**On another machine:**
1. `git pull` to get the latest transcripts.
2. Open the project in VS Code or Cursor. When a new session starts, `restore.sh` copies the transcripts back into the agent's local storage.
3. Your previous chat sessions appear in the chat history panel.

## Manual sync (CLI)

For environments where hooks aren't available, or to trigger a sync on demand:

```bash
# Copy agent transcripts from local storage → .chat-sync/
npx sync-chat export

# Copy .chat-sync/ transcripts → agent local storage
npx sync-chat restore
```

Both commands compare file contents and skip files that haven't changed.

## File structure

```
your-project/
  .chat-sync/
    copilot/               ← Copilot transcripts (commit these)
      <session-id>.jsonl
    cursor/                ← Cursor transcripts (commit these)
      <session-id>.jsonl
  .github/
    hooks/
      sync-chat.json       ← Copilot hook config (Stop + SessionStart)
  .cursor/
    hooks.json             ← Cursor hook config (sessionEnd + sessionStart)
  scripts/
    export.sh              ← copies transcript → .chat-sync/<agent>/
    restore.sh             ← copies .chat-sync/<agent>/ → agent local storage
```

Do **not** add `.chat-sync/` to `.gitignore` — committing those files is the whole point.

## Supported agents

| Agent | Local transcript storage | Hook config |
|-------|--------------------------|-------------|
| GitHub Copilot (VS Code) | `~/Library/Application Support/Code/User/workspaceStorage/<hash>/chatSessions/` (macOS) | `.github/hooks/sync-chat.json` |
| Cursor | `~/.cursor/projects/<encoded-path>/agent-transcripts/` | `.cursor/hooks.json` |

> **Claude Code** stores conversation history in the cloud (tied to your Anthropic account), so it doesn't need syncing — switching devices and logging in is enough.

## Adding a new agent

1. Add a hook config for the new agent that calls `export.sh --agent <name>` on session end and `restore.sh --agent <name>` on session start.
2. Add an `elif [ "$AGENT" = "<name>" ]` branch in `restore.sh` with the path logic for that agent's local storage.
3. The CLI `export`/`restore` subcommands may also need updating in `bin/cli.js`.

## CLI reference

```
Usage: npx sync-chat [subcommand] [options]

Subcommands:
  install [target-dir]  Copy hook configs and scripts into a project (default)
  export                Copy agent transcripts from local storage → .chat-sync/
  restore               Copy .chat-sync/ transcripts → agent local storage

Options:
  --force, -f  (install only) Overwrite existing files
  --help,  -h  Show this help message

Examples:
  npx sync-chat                      Install into current directory
  npx sync-chat ./my-project         Install into ./my-project
  npx sync-chat install --force      Force overwrite existing files
  npx sync-chat export               Manually export current transcripts
  npx sync-chat restore              Manually restore transcripts after git pull
```

## License

MIT

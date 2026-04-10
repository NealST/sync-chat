#!/usr/bin/env node

'use strict';

const fs   = require('fs');
const path = require('path');
const os   = require('os');

// ── Helpers ───────────────────────────────────────────────────────────────────

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function filesEqual(a, b) {
  if (!fs.existsSync(a) || !fs.existsSync(b)) return false;
  try {
    const sa = fs.statSync(a), sb = fs.statSync(b);
    if (sa.size !== sb.size) return false;
    return fs.readFileSync(a).equals(fs.readFileSync(b));
  } catch { return false; }
}

function green(s)  { return `\x1b[32m${s}\x1b[0m`; }
function yellow(s) { return `\x1b[33m${s}\x1b[0m`; }
function bold(s)   { return `\x1b[1m${s}\x1b[0m`; }

// ── Copilot helpers ───────────────────────────────────────────────────────────

function copilotWorkspaceStorage() {
  if (process.platform === 'win32')
    return path.join(process.env.APPDATA || '', 'Code', 'User', 'workspaceStorage');
  if (process.platform === 'darwin')
    return path.join(os.homedir(), 'Library', 'Application Support', 'Code', 'User', 'workspaceStorage');
  return path.join(os.homedir(), '.config', 'Code', 'User', 'workspaceStorage');
}

function findCopilotChatDir(projectPath) {
  const wsStorage = copilotWorkspaceStorage();
  if (!fs.existsSync(wsStorage)) return null;

  // Normalise to a file:// URI the same way VS Code stores it
  const uri = process.platform === 'win32'
    ? 'file:///' + projectPath.replace(/\\/g, '/')
    : 'file://' + projectPath;

  for (const entry of fs.readdirSync(wsStorage)) {
    const wsJson = path.join(wsStorage, entry, 'workspace.json');
    if (!fs.existsSync(wsJson)) continue;
    try {
      const d = JSON.parse(fs.readFileSync(wsJson, 'utf8'));
      const folder = (d.folder || d.workspaceUri || '').replace(/\/$/, '');
      if (folder === uri.replace(/\/$/, ''))
        return path.join(wsStorage, entry, 'chatSessions');
    } catch { /* skip malformed entries */ }
  }
  return null;
}

// ── Cursor helpers ────────────────────────────────────────────────────────────

function encodeCursorPath(projectPath) {
  // Strip leading slash (or drive letter + slash on Windows), replace separators with -
  return projectPath.replace(/^[A-Za-z]:[/\\]/, '').replace(/^[/\\]/, '').replace(/[/\\]/g, '-');
}

function findCursorTranscriptFiles(projectPath) {
  const base = path.join(
    os.homedir(), '.cursor', 'projects',
    encodeCursorPath(projectPath), 'agent-transcripts'
  );
  if (!fs.existsSync(base)) return [];

  const result = [];
  for (const sessionDir of fs.readdirSync(base)) {
    const sessionPath = path.join(base, sessionDir);
    if (!fs.statSync(sessionPath).isDirectory()) continue;
    for (const f of fs.readdirSync(sessionPath)) {
      if (f.endsWith('.jsonl'))
        result.push({ sessionId: path.basename(f, '.jsonl'), file: path.join(sessionPath, f) });
    }
  }
  return result;
}

// ── Subcommand: install ───────────────────────────────────────────────────────

function runInstall(args) {
  const force     = args.includes('--force') || args.includes('-f');
  const targetArg = args.find((a) => !a.startsWith('-'));
  const target    = targetArg ? path.resolve(process.cwd(), targetArg) : process.cwd();

  const TEMPLATES_DIR = path.join(__dirname, '..', 'templates');
  if (!fs.existsSync(TEMPLATES_DIR)) {
    console.error('Error: templates directory not found. The package may be corrupted.');
    process.exit(1);
  }

  console.log(`\nInstalling sync-chat hooks into ${bold(target)}\n`);

  if (!fs.existsSync(target)) {
    console.error(`Error: target directory does not exist: ${target}`);
    process.exit(1);
  }

  const FILES = [
    '.github/hooks/sync-chat.json',
    '.cursor/hooks.json',
    'scripts/export.sh',
    'scripts/restore.sh',
  ];

  let installed = 0, skipped = 0;

  for (const rel of FILES) {
    const src  = path.join(TEMPLATES_DIR, rel);
    const dest = path.join(target, rel);

    ensureDir(path.dirname(dest));

    if (fs.existsSync(dest) && !force) {
      console.log(`  ${yellow('skip')}  ${rel}  (already exists, use --force to overwrite)`);
      skipped++;
      continue;
    }

    fs.copyFileSync(src, dest);
    if (rel.endsWith('.sh')) fs.chmodSync(dest, fs.statSync(dest).mode | 0o111);
    console.log(`  ${green('write')} ${rel}`);
    installed++;
  }

  console.log('');
  if (installed === 0 && skipped > 0) {
    console.log(`All files already exist. Run with ${bold('--force')} to overwrite.\n`);
  } else {
    console.log(`Done! ${installed} file(s) installed.`);
    console.log(`\nNext steps:`);
    console.log(`  1. git add .github/hooks/ .cursor/hooks.json scripts/`);
    console.log(`  2. git commit -m "chore: add sync-chat hooks"`);
    console.log(`  3. git push\n`);
  }
}

// ── Subcommand: export ────────────────────────────────────────────────────────

function runExport() {
  const projectPath = process.cwd();
  const syncDir     = path.join(projectPath, '.chat-sync');
  ensureDir(syncDir);

  console.log(`\nExporting chat transcripts → ${bold(syncDir)}\n`);

  let total = 0;

  // Copilot
  const chatSessionsDir = findCopilotChatDir(projectPath);
  if (chatSessionsDir && fs.existsSync(chatSessionsDir)) {
    for (const f of fs.readdirSync(chatSessionsDir)) {
      if (!f.endsWith('.jsonl')) continue;
      const src  = path.join(chatSessionsDir, f);
      const dest = path.join(syncDir, f);
      if (!filesEqual(src, dest)) {
        fs.copyFileSync(src, dest);
        console.log(`  ${green('export')} [copilot] ${f}`);
        total++;
      } else {
        console.log(`  ${yellow('skip')}  [copilot] ${f}  (unchanged)`);
      }
    }
  } else {
    console.log(`  ${yellow('skip')}  [copilot] no workspace storage found for this project`);
  }

  // Cursor
  const cursorFiles = findCursorTranscriptFiles(projectPath);
  if (cursorFiles.length === 0) {
    console.log(`  ${yellow('skip')}  [cursor]  no agent transcripts found for this project`);
  }
  for (const { sessionId, file } of cursorFiles) {
    const dest = path.join(syncDir, `${sessionId}.jsonl`);
    if (!filesEqual(file, dest)) {
      fs.copyFileSync(file, dest);
      console.log(`  ${green('export')} [cursor]  ${sessionId}.jsonl`);
      total++;
    } else {
      console.log(`  ${yellow('skip')}  [cursor]  ${sessionId}.jsonl  (unchanged)`);
    }
  }

  console.log('');
  if (total === 0) {
    console.log('Nothing new to export.\n');
  } else {
    console.log(`Done! ${total} file(s) exported to .chat-sync/`);
    console.log(`\nRemember to commit and push:`);
    console.log(`  git add .chat-sync/ && git commit -m "chore: sync chat history"\n`);
  }
}

// ── Subcommand: restore ───────────────────────────────────────────────────────

function runRestore() {
  const projectPath = process.cwd();
  const syncDir     = path.join(projectPath, '.chat-sync');

  const syncFiles = fs.existsSync(syncDir)
    ? fs.readdirSync(syncDir).filter((f) => f.endsWith('.jsonl'))
    : [];

  if (syncFiles.length === 0) {
    console.log('\nNothing to restore — .chat-sync/ has no .jsonl files.\n');
    return;
  }

  console.log(`\nRestoring ${syncFiles.length} transcript(s) from ${bold(syncDir)}\n`);

  let total = 0;

  // Copilot
  const chatSessionsDir = findCopilotChatDir(projectPath);
  if (chatSessionsDir) {
    ensureDir(chatSessionsDir);
    for (const f of syncFiles) {
      const src  = path.join(syncDir, f);
      const dest = path.join(chatSessionsDir, f);
      if (!filesEqual(src, dest)) {
        fs.copyFileSync(src, dest);
        console.log(`  ${green('restore')} [copilot] ${f}`);
        total++;
      }
    }
  } else {
    console.log(`  ${yellow('skip')}  [copilot] no workspace storage found for this project`);
  }

  // Cursor
  const transcriptsBase = path.join(
    os.homedir(), '.cursor', 'projects',
    encodeCursorPath(projectPath), 'agent-transcripts'
  );
  for (const f of syncFiles) {
    const sessionId = path.basename(f, '.jsonl');
    const src       = path.join(syncDir, f);
    const dest      = path.join(transcriptsBase, sessionId, f);
    if (!filesEqual(src, dest)) {
      ensureDir(path.dirname(dest));
      fs.copyFileSync(src, dest);
      console.log(`  ${green('restore')} [cursor]  ${f}`);
      total++;
    }
  }

  console.log('');
  if (total === 0) {
    console.log('All transcripts already up to date.\n');
  } else {
    console.log(`Done! ${total} file(s) restored.`);
    console.log('\nReopen VS Code / Cursor to see the restored sessions in your chat history.\n');
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────

const SUBCOMMANDS = ['install', 'export', 'restore'];
const rawArgs     = process.argv.slice(2);
const isSubcmd    = SUBCOMMANDS.includes(rawArgs[0]);
const subcommand  = isSubcmd ? rawArgs[0] : 'install';
const subArgs     = isSubcmd ? rawArgs.slice(1) : rawArgs;

if (subArgs.includes('--help') || subArgs.includes('-h')) {
  console.log(`
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
`);
  process.exit(0);
}

switch (subcommand) {
  case 'install': runInstall(subArgs); break;
  case 'export':  runExport();         break;
  case 'restore': runRestore();        break;
}

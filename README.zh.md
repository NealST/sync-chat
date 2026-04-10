# sync-chat

通过 git 同步 AI Agent 的对话历史，在多设备使用和团队协作中共享上下文。

GitHub Copilot、Cursor 等 Agent 的对话记录默认只保存在本地：换台机器就丢了，团队成员之间也无法共享。`sync-chat` 通过 hook 机制，在 Agent 会话结束时自动把对话记录复制到仓库的 `.chat-sync/` 目录，随代码一起纳入版本控制。典型使用场景：

- **多设备**：在公司和家里使用同一个仓库，对话历史无缝延续
- **团队协作**：成员 A 和 AI 讨论的方案、踩过的坑，push 之后团队其他人 pull 下来就能直接看到，不用重复解释背景

## 工作原理

### 核心思路

Agent 的对话记录本质上就是文件（`.jsonl`）。`sync-chat` 将它们复制到仓库内的 `.chat-sync/` 目录，之后就和代码一样走 git 工作流——commit、push、pull——任何拥有这个仓库的机器或团队成员都能获得完整的对话历史。在接收端，对话记录会被写回 Agent 的本地存储目录，在对话面板里显示出来，就像本来就在那里一样。

对话记录按 **Agent 分目录存储**（`.chat-sync/copilot/`、`.chat-sync/cursor/`），保持清晰不混淆。`git commit` 和 `git push` **由你自己决定何时执行**——sync-chat 不会自动运行任何 git 命令。

### 两种同步方式

`sync-chat` 提供两种方式将对话记录导入导出 `.chat-sync/`，可以单独使用或搭配使用：

| | Agent Hook（自动） | CLI 命令（手动） |
|---|---|---|
| **原理** | hook 配置文件告诉 Agent 在会话结束/开始时运行 `export.sh` / `restore.sh`，完全透明，不需要安装任何插件。 | 需要时手动执行 `npx sync-chat export` 或 `npx sync-chat restore`。 |
| **使用体感** | 零摩擦。每次会话结束后对话记录自动出现在 `.chat-sync/`，你什么都不用做。 | 按需触发。适合 hook 不可用的环境，或者你更倾向于显式控制。 |
| **前置条件** | Agent 需要支持 hook（Copilot 和 Cursor 均已支持）。 | Node.js ≥ 16。 |

### Hook 细节

Copilot 和 Cursor 都提供了 **hook 机制**，允许在生命周期事件上执行 shell 命令。`sync-chat` 会向项目中安装两个 hook 配置文件和两个脚本：

```
your-project/
  .github/hooks/sync-chat.json   ← GitHub Copilot hook 配置
  .cursor/hooks.json             ← Cursor hook 配置
  scripts/
    export.sh                    ← 会话结束时执行
    restore.sh                   ← 会话开始时执行
```

每个 hook 配置都会通过 `--agent <name>` 参数显式告知脚本当前是哪个 Agent，识别逻辑清晰，扩展新 Agent 时只需新增一条 hook 配置。

| 事件 | Agent | 脚本 | 行为 |
|------|-------|------|------|
| 会话结束 | Copilot `Stop` / Cursor `sessionEnd` | `export.sh` | 从 stdin 读取 `transcript_path`，将 `.jsonl` 文件复制到 `.chat-sync/<agent>/` |
| 会话开始 | Copilot `SessionStart` / Cursor `sessionStart` | `restore.sh` | 将 `.chat-sync/<agent>/*.jsonl` 复制回 Agent 本地存储；内容未变化的文件会自动跳过 |

## 环境要求

- Node.js ≥ 16（使用 CLI 工具时需要）
- Python 3（shell 脚本内部使用，macOS/Linux 默认已安装）
- `bash`

## 安装

**方式 A — npm（需要 Node.js ≥ 16）：**

```bash
npx sync-chat
```

安装到指定目录，或强制覆盖已有文件：

```bash
npx sync-chat install ./path/to/project
npx sync-chat install --force
```

**方式 B — curl（无需 Node.js）：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/sync-chat/main/install.sh)
```

同样支持以下参数：

```bash
# 安装到指定目录
bash <(curl -fsSL ...) ./path/to/project

# 覆盖已有文件
bash <(curl -fsSL ...) --force
```

安装完成后，提交生成的文件：

```bash
git add .github/hooks/ .cursor/hooks.json scripts/
git commit -m "chore: add sync-chat hooks"
git push
```

## 自动同步（通过 hook）

hook 文件提交后，同步会自动运行：

**在当前机器上：**
1. 正常使用 Copilot 或 Cursor。
2. 会话结束时，`export.sh` 会将对话记录复制到 `.chat-sync/<agent>/`。
3. 将 `.chat-sync/` 连同代码改动一起 commit 并 push。

**在另一台机器上：**
1. `git pull` 拉取最新代码（含对话记录）。
2. 用 VS Code 或 Cursor 打开项目，新会话启动时 `restore.sh` 会自动将对话记录写回 Agent 本地存储。
3. 历史对话出现在对话面板中。

## 手动同步（CLI）

适用于 hook 不可用的场景，或需要手动触发同步时：

```bash
# 将 Agent 本地对话记录导出到 .chat-sync/
npx sync-chat export

# 将 .chat-sync/ 中的记录恢复到 Agent 本地存储
npx sync-chat restore
```

两个命令都会比对文件内容，内容未变化的文件会跳过。

## 目录结构

```
your-project/
  .chat-sync/
    copilot/               ← Copilot 对话记录（需要提交）
      <session-id>.jsonl
    cursor/                ← Cursor 对话记录（需要提交）
      <session-id>.jsonl
  .github/
    hooks/
      sync-chat.json       ← Copilot hook 配置（Stop + SessionStart）
  .cursor/
    hooks.json             ← Cursor hook 配置（sessionEnd + sessionStart）
  scripts/
    export.sh              ← 复制记录到 .chat-sync/<agent>/
    restore.sh             ← 从 .chat-sync/<agent>/ 恢复记录
```

**不要**把 `.chat-sync/` 加入 `.gitignore`——把这些文件提交到 git 才是这个工具的核心意义。

## 支持的 Agent

| Agent | 本地对话记录路径 | Hook 配置文件 |
|-------|-----------------|--------------|
| GitHub Copilot（VS Code） | `~/Library/Application Support/Code/User/workspaceStorage/<hash>/chatSessions/`（macOS） | `.github/hooks/sync-chat.json` |
| Cursor | `~/.cursor/projects/<encoded-path>/agent-transcripts/` | `.cursor/hooks.json` |

> **Claude Code** 的对话历史存储在云端（关联 Anthropic 账号），换设备登录即可恢复，无需同步。

## 扩展支持新 Agent

1. 为新 Agent 添加 hook 配置，在会话结束时调用 `export.sh --agent <name>`，在会话开始时调用 `restore.sh --agent <name>`。
2. 在 `restore.sh` 中添加 `elif [ "$AGENT" = "<name>" ]` 分支，实现该 Agent 本地存储路径的解析逻辑。
3. 视情况更新 `bin/cli.js` 中的 `export`/`restore` 子命令。

## CLI 参考

```
用法: npx sync-chat [子命令] [选项]

子命令:
  install [目标目录]  将 hook 配置和脚本复制到项目中（默认行为）
  export             将 Agent 本地对话记录导出到 .chat-sync/
  restore            将 .chat-sync/ 中的记录恢复到 Agent 本地存储

选项:
  --force, -f  （仅 install）覆盖已有文件
  --help,  -h  显示帮助信息

示例:
  npx sync-chat                      安装到当前目录
  npx sync-chat ./my-project         安装到 ./my-project
  npx sync-chat install --force      强制覆盖已有文件
  npx sync-chat export               手动导出当前对话记录
  npx sync-chat restore              git pull 后手动恢复对话记录
```

## License

MIT

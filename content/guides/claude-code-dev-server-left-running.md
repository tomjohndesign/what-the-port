---
title: Claude Code left a dev server running? Find and clean up agent-started servers
description: Coding agents like Claude Code, Codex and Cursor start dev servers in the background and leave them running. How to find which agent session started each server, stop the leftovers, and stop agents starting duplicates.
published: 2026-09-25
order: 4
keywords: claude code dev server still running, claude code background process, claude code port already in use, codex dev server, cursor agent starts new dev server, zombie node processes, orphaned dev servers
---

Coding agents are good at starting dev servers. They’re less good at stopping them. Ask Claude Code, Codex or Cursor to “check it in the browser” and it will run `npm run dev` in a background shell. The session ends, you close the window, and the server keeps running. Do that across a few projects and a few days and you have a handful of `node` processes holding ports and gigabytes of memory, none of them attached to a terminal you can find.

The other symptom is the reverse: the agent doesn’t notice a server is already running, starts another, and gets `localhost:3001`. Then `3002`. You keep typing new port numbers into the browser.

## Find servers an agent started

Start with every listening dev server:

```bash
lsof -nP -iTCP -sTCP:LISTEN | grep -iE '^(node|bun|deno|python)'
```

To tell which ones came from an agent, look at their environment. Agents pass variables to the commands they run, and child processes inherit them. On macOS, `ps -E` shows a process’s environment (for processes you own):

```bash
ps -E -ww -o command= -p <PID> | tr ' ' '\n' | grep -E '^(CLAUDE|CONDUCTOR|CODEX)'
```

Some servers rename themselves once they start (Next.js shows up as `next-server`), which hides their environment from `ps`. If nothing prints, try the parent process instead: `ps -o ppid= -p <PID>` gives you its PID.

What to look for:

| Started by | Variables in the server’s environment |
| --- | --- |
| Claude Code | `CLAUDECODE=1`, `CLAUDE_CODE_SESSION_ID` |
| Conductor | `CONDUCTOR_WORKSPACE_NAME`, `CONDUCTOR_PORT` |
| Codex | Match the server’s folder to a session in `~/.codex/sessions` |

With the session ID you can go back to the conversation that started the server:

```bash
claude --resume <session-id>
codex resume <session-id>
```

That’s often the fastest way to decide whether a server still matters: open the session, see what the agent was doing, and either carry on or stop it.

## Stop the leftovers

Agent-started servers are usually a chain: a shell, `npm`, the framework CLI, then the server itself. Stopping the process on the port can leave the rest. Stop the whole process group:

```bash
kill -- -$(ps -o pgid= -p <PID> | tr -d ' ')
```

If you use git worktrees for parallel agents, check for servers whose worktree no longer exists. `lsof` still reports their old working directory, but the folder is gone, and they’re always safe to stop:

```bash
dir=$(lsof -a -p <PID> -d cwd -Fn | grep '^n' | cut -c2-)
[ -d "$dir" ] || echo "Worktree deleted: $dir"
```

## Stop agents starting duplicates

Tell the agent how to check first. Add something like this to your project’s `CLAUDE.md` or `AGENTS.md`:

```markdown
## Dev server

Before starting a dev server, check whether one is already running for this folder:
`lsof -nP -iTCP -sTCP:LISTEN` (or `wtp list --json` if WhatThePort is installed).
Reuse it if it is. Use the port in `$CONDUCTOR_PORT` if set, otherwise 3000.
Never start a second copy on another port.
```

Two more things help:

- **Fail loudly on a busy port.** If the dev server exits on `EADDRINUSE` instead of moving to the next port, the agent sees the error and looks for the existing server. For Vite, set `server.strictPort: true`.
- **Give each workspace its own port.** See [Running parallel coding agents without port chaos](/guides/parallel-coding-agents-git-worktrees-ports).

## With WhatThePort

[WhatThePort](/) is a free menu bar app built for this. It links every server to the Claude Code, Codex or Conductor session that started it, using the same environment variables and session files described above. Click a server to see its session, branch, folder and command, then resume the conversation or stop the server and its whole process tree.

**Clean up** preselects servers from deleted worktrees and servers that have been idle for hours, so the leftovers from last week’s agent sessions go in one click. You can set it to ask first or to run automatically; servers that are leaking memory are never stopped automatically, and Postgres and Redis are protected by default.

Agents can read the same list. `wtp list --json` prints every server with its port, folder, branch, status and the session that started it:

```json
[
  {
    "port": 3000,
    "url": "http://localhost:3000",
    "name": "marketing-site",
    "branch": "feat/pricing",
    "folder": "/Users/you/code/marketing-site",
    "status": "running",
    "session": { "kind": "Claude Code", "id": "3f2a…", "title": "Pricing page" }
  }
]
```

[Download WhatThePort](/WhatThePort.dmg) for Apple Silicon Macs on macOS 14 or later.

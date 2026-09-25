---
title: Running parallel coding agents in git worktrees without port chaos
description: When several Claude Code, Codex or Conductor agents each run a dev server from their own git worktree, ports collide and old servers pile up. How to give every worktree its own port and clean up after deleted ones.
published: 2026-09-25
order: 5
keywords: git worktrees parallel agents ports, parallel claude code agents port conflict, conductor CONDUCTOR_PORT, codex concurrent sessions ports, git worktree dev server, deleted worktree process still running
---

Running several coding agents at once usually means git worktrees: one checkout per branch, so agents don’t trample each other’s files. Tools like [Conductor](https://www.conductor.build) set this up for you. It works well until every worktree wants to run `npm run dev` on port 3000.

Three things go wrong:

1. **Ports collide.** The second worktree’s server fails with `EADDRINUSE`, or quietly moves to 3001, and now you don’t know which branch you’re looking at in the browser.
2. **You test the wrong branch.** `localhost:3000` is serving `feat/pricing` while the agent you’re talking to changed `fix/nav`.
3. **Servers outlive their worktrees.** You merge a branch and delete its worktree, but its dev server is still running from a folder that no longer exists.

## Give every worktree its own port

Pick the port from the environment instead of hard-coding 3000.

**In Conductor,** each workspace gets ten ports, from `CONDUCTOR_PORT` to `CONDUCTOR_PORT + 9`. Use it in your run script:

```bash
npm run dev -- --port $CONDUCTOR_PORT
```

**Elsewhere,** derive a port from the worktree. This picks a stable port between 3100 and 3999 from the folder path:

```bash
port=$((3100 + $(pwd | cksum | cut -d' ' -f1) % 900))
npm run dev -- --port $port
```

Then make the dev server refuse to fall back to another port, so a collision shows up as an error the agent can see. For Vite, set `server.strictPort: true`. For other tools, prefer an explicit `--port` over automatic fallback.

**Or skip port numbers entirely.** [Portless](https://github.com/vercel-labs/portless) gives each app a stable named URL such as `https://myapp.localhost`, which is easier to tell apart than 3000 and 3007.

## Tell agents which server is theirs

Agents can’t see your browser tabs. Say where the server is in `CLAUDE.md` or `AGENTS.md`:

```markdown
## Dev server

Run the dev server on $CONDUCTOR_PORT. Before starting one, check whether it's already
running (`lsof -nP -iTCP:$CONDUCTOR_PORT -sTCP:LISTEN` or `wtp list --json`) and reuse it.
```

## Clean up after deleted worktrees

When you delete a worktree with `git worktree remove`, or its folder disappears when a workspace is archived, any server started there keeps running. Its working directory no longer exists, which makes it easy to spot. `lsof` still reports the old path, so check whether the folder is there:

```bash
for pid in $(lsof -t -a -iTCP -sTCP:LISTEN -c node -c bun -c '/^python/i'); do
  dir=$(lsof -a -p "$pid" -d cwd -Fn | grep '^n' | cut -c2-)
  [ -d "$dir" ] || echo "$pid  $dir"
done
```

Anything that prints is serving a branch you’ve already thrown away. Stop it, along with its process group:

```bash
kill -- -$(ps -o pgid= -p <PID> | tr -d ' ')
```

`git worktree prune` tidies git’s own records of removed worktrees, but it doesn’t touch running processes.

## Keep an eye on memory

Five worktrees means five copies of your framework’s dev server, each with its own module graph and caches. A Next.js dev server commonly uses 500 MB to 2 GB. Multiply by five and a 16 GB Mac starts swapping. See [Dev servers eating your RAM](/guides/dev-server-memory-leak-mac).

## With WhatThePort

[WhatThePort](/) was built for exactly this setup. Its menu bar list shows every server with its port, project and **branch**, so `:55390 feat/pricing` and `:55400 fix/nav` are easy to tell apart. Each server links back to the Conductor workspace or the Claude Code or Codex session that started it, and a server whose worktree has been deleted is labelled “Worktree deleted”.

**Clean up** preselects those servers, plus any that have been idle for hours, and stops their whole process trees together. Set it to Ask and WhatThePort notifies you when there’s something to clean up; set it to Automatic and it just happens.

For agents, `wtp list --json` returns every server with its `folder`, `branch`, `url` and `session`, so an agent can find the server for its own worktree instead of starting another.

[Download WhatThePort](/WhatThePort.dmg) for Apple Silicon Macs on macOS 14 or later.

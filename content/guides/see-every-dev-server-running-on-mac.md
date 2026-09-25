---
title: How to see every dev server running on your Mac
description: List every localhost server and listening port on macOS from the terminal, work out which project each one belongs to, and keep them in view from the menu bar.
published: 2026-09-25
order: 3
keywords: what is running on localhost mac, list listening ports mac, see all localhost servers mac, lsof listening ports, which process is using which port macos, localhost manager mac
---

Open `localhost:3000`, `3001`, `5173`, `8000` in turn and you’ll find out what’s running, one guess at a time. Here’s how to see all of it at once.

## List every listening port

```bash
lsof -nP -iTCP -sTCP:LISTEN
```

This prints every process on your Mac that’s waiting for TCP connections. Each row has the command, the PID, and the address in the `NAME` column: `*:3000` means any address on port 3000, and `127.0.0.1:5432` means only local connections on port 5432.

The list includes a lot that isn’t yours: `ControlCenter`, `rapportd`, Spotify, Dropbox. To see only likely dev servers:

```bash
lsof -nP -iTCP -sTCP:LISTEN | grep -iE '^(node|bun|deno|python|ruby|java|go|php)'
```

## Turn PIDs into projects

A list of `node` processes isn’t much help when you have six. This loop prints the port, PID and folder of each one:

```bash
for pid in $(lsof -t -a -iTCP -sTCP:LISTEN -c node -c bun -c '/^python/i' -c ruby); do
  port=$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN -Fn | grep -m1 '^n' | sed 's/.*://')
  dir=$(lsof -a -p "$pid" -d cwd -Fn | grep '^n' | cut -c2-)
  echo "$port  $pid  $dir"
done | sort -n
```

```
3000  48213  /Users/tom/code/marketing-site
5173  51002  /Users/tom/code/editor
6006  51190  /Users/tom/code/design-system
8000  39921  /Users/tom/code/api/.worktrees/fix-auth
```

From the folder you can get the git branch (`git -C <dir> branch --show-current`) and the project name from its `package.json`.

## Check memory and CPU

Activity Monitor shows memory per process, but a dev server is usually several processes: `npm`, the framework’s CLI, a server worker, a TypeScript checker, maybe a bundler. To see the whole tree:

```bash
pgrep -P 48213   # direct children
ps -o pid,ppid,rss,%cpu,command -g $(ps -o pgid= -p 48213)
```

Add up the `rss` column (in kilobytes) for a rough total. Next.js and Storybook servers can easily reach 1–3 GB once you’ve clicked around for a while. There’s more on that in [Dev servers eating your RAM](/guides/dev-server-memory-leak-mac).

## Why not netstat?

`netstat -an | grep LISTEN` shows listening ports but not, by default, which process owns them. `lsof` gives you the PID and command in one step, so it’s the better starting point on macOS.

## Or keep them in the menu bar

The commands above answer the question once. If you run more than a couple of servers, or let coding agents start them for you, you’ll want the answer all the time.

[WhatThePort](/) is a free, open-source menu bar app that does exactly what the loop above does, every two seconds: it reads listening sockets with `lsof`, then inspects each process tree for its folder, command, memory and CPU. For each server it shows:

- the port, with a stable color so `:3000` always looks the same
- the project name from `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod` or `Gemfile`, and the framework
- the git branch, and whether its worktree has been deleted
- uptime, memory and CPU for the whole process tree, with ten minutes of history
- the Claude Code, Codex or Conductor session that started it, if any

Press ⌥⌘P to open it, click a server to open it in the browser, or stop it. Prefer the terminal? `wtp` shows the same list there, and `wtp list --json` prints it for scripts.

[Download WhatThePort](/WhatThePort.dmg) for Apple Silicon Macs on macOS 14 or later, or [try the interactive demo](/).

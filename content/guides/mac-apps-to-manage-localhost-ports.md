---
title: Tools for managing localhost ports and dev servers on a Mac
description: A practical overview of the ways to see and stop what’s running on localhost on macOS, from lsof and kill-port to Raycast extensions and menu bar apps, and which fits which workflow.
published: 2026-09-25
order: 9
keywords: localhost manager mac, port monitor mac, dev server manager mac, kill port app mac, lsof gui mac, menu bar app localhost ports, kill-port alternative
---

Every developer on a Mac eventually needs to answer “what’s running on this port?” and “how do I stop it?”. There are a lot of tools for it now. They fall into four groups, and the right one depends on how many servers you run and who starts them.

We make [WhatThePort](/), one of the menu bar apps below, so weigh our opinion accordingly. We’ve tried to describe the others the way they describe themselves.

## 1. Built-in commands

**Best for:** the occasional stuck port.

macOS already has everything you need:

```bash
lsof -nP -iTCP -sTCP:LISTEN          # everything listening
lsof -nP -iTCP:3000 -sTCP:LISTEN     # one port
kill <PID>                           # stop it
```

Free, always there, and works over SSH. The downside is that you only see what you ask about, and a PID doesn’t tell you which project it belongs to. There’s a walkthrough in [Port 3000 already in use on Mac](/guides/port-3000-already-in-use-mac).

## 2. Command-line tools

**Best for:** scripts, and people who live in the terminal.

- [**kill-port**](https://www.npmjs.com/package/kill-port): `npx kill-port 3000`. Kills whatever is on a port. Popular in `predev` scripts.
- [**fkill-cli**](https://github.com/sindresorhus/fkill-cli): an interactive, fuzzy-searchable process killer.
- [**portrm**](https://portrm.dev): a CLI for inspecting and freeing ports, with safety checks before it kills anything.
- [**Portless**](https://github.com/vercel-labs/portless), from Vercel Labs, takes a different approach: it replaces port numbers with stable named URLs like `https://myapp.localhost`, “for humans and agents”. It prevents collisions rather than cleaning up after them, and works alongside any of the tools here.

## 3. Launcher extensions

**Best for:** Raycast or Alfred users who want to kill a port without switching apps.

- [**Port Manager for Raycast**](https://www.raycast.com/lucaschultz/port-manager) lists open ports and kills the processes behind them from the Raycast search bar.
- [**Sloth**](https://sveinbjorn.org/sloth) isn’t a launcher extension, but it fills a similar niche: a free, native GUI for `lsof` that shows every open file, socket and pipe on your Mac. More general than a dev tool, and very thorough.

## 4. Menu bar apps

**Best for:** anyone who regularly has more than a couple of servers running, especially with coding agents starting them.

These stay running and show your servers all the time, so you notice a stray server before it blocks a port. There are many; a few of the most visible:

- [**Ports**](https://www.ports-app.com): “See every dev server running on localhost from your menu bar”, with port, project, uptime, CPU and memory.
- [**Port Menu**](https://www.portmenu.dev): “localhost, organized”. Open source.
- [**PortKiller**](https://portkiller.app): finds and kills stuck ports, including Docker containers and Homebrew services.
- [**Portman**](https://github.com/iannuttall/portman): “Find and kill zombie dev servers.” Open source.
- [**Portie**](https://portie.dev) and [**PortBar**](https://getportbar.com): see what’s using a port and stop it.

### Where WhatThePort fits

[WhatThePort](/) is a free, open-source (MIT) menu bar app written in Swift. Like the others, it lists every dev server with its port, project, uptime, memory and CPU. It’s built around what matters once coding agents are starting servers for you:

- **Agent sessions.** Each server links to the Claude Code, Codex or Conductor session that started it, so you can resume the conversation or find the workspace.
- **Branches and worktrees.** Each server shows its git branch, and servers whose worktree has been deleted are flagged.
- **Leak alerts.** Memory is summed across the whole process tree, with ten minutes of history. A server that passes 2 GB or grows 500 MB in ten minutes turns amber in the menu bar and sends one notification.
- **Clean up.** Preselects idle servers and servers from deleted worktrees, then stops each whole process tree. Databases are protected by default. It can run automatically.
- **A terminal UI.** `wtp` shows the same list in your terminal, and `wtp list --json` gives scripts and agents a structured list of every server.

It needs an Apple Silicon Mac on macOS 14 or later.

## Which should you use?

| If you… | Try |
| --- | --- |
| hit a busy port once a month | `lsof` and `kill` |
| want to free a port in a script | `kill-port` |
| already live in Raycast | Port Manager |
| want every open file and socket, not just dev servers | Sloth |
| run several projects, worktrees or coding agents at once | a menu bar app such as [WhatThePort](/) |
| keep mixing up which app is on which port | Portless, alongside any of the above |

[Download WhatThePort](/WhatThePort.dmg) or [try the interactive demo](/).

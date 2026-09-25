---
title: Port 3000 already in use on Mac: find what’s using it and stop it
description: How to find the process holding port 3000 (or any port) on macOS with lsof, stop it safely, and keep forgotten dev servers from taking your ports again.
published: 2026-09-25
order: 1
keywords: port 3000 already in use mac, kill process on port 3000 mac, lsof -i :3000, find process using port macos, kill-port, address already in use
---

You run `npm run dev` and get one of these:

```
Error: listen EADDRINUSE: address already in use :::3000
```

```
⚠ Port 3000 is in use, trying 3001 instead.
```

Something on your Mac is already listening on port 3000. Usually it’s a dev server you started earlier and forgot about: in another terminal tab, in a closed editor window, or started by a coding agent. Here’s how to find it and stop it.

## The short answer

```bash
# See what's listening on port 3000
lsof -nP -iTCP:3000 -sTCP:LISTEN

# Stop it (replace 12345 with the PID from the output)
kill 12345
```

If you just want port 3000 back and don’t care what it was:

```bash
kill $(lsof -t -iTCP:3000 -sTCP:LISTEN)
```

## Find the process using the port

`lsof` (“list open files”) ships with macOS and treats network sockets as files:

```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN
```

```
COMMAND   PID USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME
node    48213  tom   23u  IPv6  0x1c2…      0t0  TCP *:3000 (LISTEN)
```

What the flags do:

- `-iTCP:3000` only shows TCP sockets on port 3000.
- `-sTCP:LISTEN` only shows sockets that are listening, not connections your browser has open to the server.
- `-n` and `-P` skip DNS and port-name lookups, so it answers instantly and shows `3000`, not `hbci`.

If nothing prints, nothing on your Mac is listening on that port. If a process owned by another user holds it, run the same command with `sudo`.

## Work out what it actually is

`node` and PID `48213` rarely tell you which project it is. Two more commands do:

```bash
# The full command line
ps -ww -o command= -p 48213

# The folder it was started in
lsof -a -p 48213 -d cwd -Fn | tail -1 | cut -c2-
```

Now you know it’s, say, `next dev` in `~/code/marketing-site`, and you can decide whether you still need it.

## Stop it

```bash
kill 48213
```

`kill` sends `SIGTERM`, which asks the process to shut down cleanly. Give it a second. If it’s still there, force it:

```bash
kill -9 48213
```

`-9` (`SIGKILL`) can’t be ignored, but the process gets no chance to clean up, so try the polite version first.

### Why the port sometimes comes straight back

Many dev tools run the real server as a child of a watcher: `npm run dev` starts `next dev`, which starts a worker; `nodemon` restarts your app when it exits. Kill only the process holding the socket and the parent may start a new one, or exit and leave other children behind.

Find the parent and stop that instead:

```bash
ps -o ppid=,command= -p 48213
```

Or stop the whole process group in one go:

```bash
kill -- -$(ps -o pgid= -p 48213 | tr -d ' ')
```

## One-off tools

If you do this often, a couple of npm tools save typing:

- `npx kill-port 3000` stops whatever is on port 3000.
- `npx fkill-cli` gives you an interactive, searchable process list.

Both answer “what’s on this one port, kill it”. They don’t tell you which project the server belongs to, or warn you before the next one piles up.

## Stop it happening again

The error is a symptom. The cause is that dev servers are invisible once their terminal is out of sight, so they accumulate. A few habits help:

- **Close servers from where you started them.** `Ctrl+C` in the terminal lets the tool shut down its whole process tree.
- **Give each project its own port.** Put it in the dev script, such as `next dev -p 3100` in one project’s `package.json` and `vite --port 3200` in another’s, so two projects never fight over 3000.
- **Make port conflicts loud.** Vite’s `--strictPort` exits instead of quietly moving to 5174. See [why Vite jumps to 5174 and Next.js to 3001](/guides/vite-port-5174-nextjs-port-3001).
- **Keep every server in view.** That’s what [WhatThePort](/) does.

## With WhatThePort

WhatThePort lives in your Mac’s menu bar and lists every dev server that’s running, by port, project name and git branch, with memory and CPU for its whole process tree. Press ⌥⌘P, find `:3000`, and you can see it’s `marketing-site` on `main`, up for two days. Hover the row and click stop: WhatThePort sends `SIGTERM` to every process in the tree, then `SIGKILL` if anything is still running a few seconds later.

It’s free and open source. [Download WhatThePort](/WhatThePort.dmg) for Apple Silicon Macs on macOS 14 or later.

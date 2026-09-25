---
title: EADDRINUSE: address already in use, explained
description: What EADDRINUSE means in Node.js, Next.js, nodemon, Python and Rails, why it happens on macOS, and how to fix it for good instead of killing ports by hand.
published: 2026-09-25
order: 2
keywords: EADDRINUSE, address already in use, listen EADDRINUSE address already in use :::3000, nodemon EADDRINUSE, errno 48 address already in use, rails address already in use
---

`EADDRINUSE` means your server asked the operating system for a port and the operating system said no, because another socket is already listening on it. It’s the same error in every language; only the wording changes:

| Runtime | What you see |
| --- | --- |
| Node.js, Next.js, Express | `Error: listen EADDRINUSE: address already in use :::3000` |
| Python (Flask, uvicorn, http.server) | `OSError: [Errno 48] Address already in use` |
| Django | `Error: That port is already in use.` |
| Rails (Puma) | `Address already in use - bind(2) for "127.0.0.1" port 3000 (Errno::EADDRINUSE)` |
| Go | `listen tcp :8080: bind: address already in use` |

On macOS the error number is 48, which is why you’ll see `errno: -48` in Node’s stack trace and `Errno 48` in Python’s.

## The fix, right now

Find the process and stop it:

```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN   # note the PID
kill <PID>
```

There’s a step-by-step version, including how to tell which project the process belongs to, in [Port 3000 already in use on Mac](/guides/port-3000-already-in-use-mac).

## Why it keeps happening

### 1. A server you forgot about

The most common cause by far. You started a server in a terminal tab, an editor’s integrated terminal, or a coding agent’s background shell, then moved on. It’s still running. Check with:

```bash
lsof -nP -iTCP -sTCP:LISTEN
```

That lists every listening socket on your Mac. Anything that says `node`, `python`, `ruby` or `bun` is probably one of yours.

### 2. The same app, started twice

`npm run dev` in two terminals, or a `concurrently` script that starts the server twice, or an agent that didn’t notice the server was already up. The second copy fails with `EADDRINUSE`.

### 3. The old process hasn’t let go yet (nodemon, watch mode)

Watchers such as nodemon restart your app on every save. If the old process takes longer to exit than the new one takes to start, the new one hits `EADDRINUSE`. Close the server when the process is asked to stop:

```js
const server = app.listen(3000)

function shutdown() {
  server.close(() => process.exit(0))
}

process.once('SIGTERM', shutdown)
process.once('SIGINT', shutdown)
// nodemon sends SIGUSR2 to restart by default
process.once('SIGUSR2', shutdown)
```

### 4. An orphaned child process

Stopping a parent doesn’t always stop its children. Kill `npm` with `-9` and the `node` process it started can live on, still holding the port, with no terminal attached. `ps -o ppid= -p <PID>` shows its parent; if that’s `1`, it’s an orphan and safe to stop.

### 5. Something that isn’t a dev server

A few ports are taken by macOS or other apps:

- **5000 and 7000**: AirPlay Receiver on macOS 12 and later. See [Port 5000 in use on Mac](/guides/port-5000-in-use-mac-airplay).
- **Docker Desktop**: a published container port shows up as a Docker process. Use `docker ps` and `docker stop` rather than killing Docker itself.
- **Databases**: Postgres on 5432, Redis on 6379, MySQL on 3306.

## Handle it in code

If you’d rather your server tell you what’s wrong than crash with a stack trace, catch the error:

```js
server.on('error', (error) => {
  if (error.code === 'EADDRINUSE') {
    console.error(`Port ${error.port} is busy. Run: lsof -nP -iTCP:${error.port} -sTCP:LISTEN`)
    process.exit(1)
  }
  throw error
})
```

Avoid silently picking a random free port. That’s how you end up with the same app on 3000, 3001 and 3002, all using memory, and a browser tab pointed at the stale one.

## Fix it for good

`EADDRINUSE` is what happens when running servers are invisible. Make them visible and it mostly goes away. [WhatThePort](/) is a free menu bar app that lists every dev server on your Mac with its port, project, branch and memory, so a stray server is obvious before it blocks a port. **Clean up** finds servers that have been idle for hours or whose git worktree has been deleted, and stops them together.

[Download WhatThePort](/WhatThePort.dmg) (Apple Silicon, macOS 14 or later).

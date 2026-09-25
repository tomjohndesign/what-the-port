---
title: Why Vite starts on 5174 and Next.js on 3001, and how to find the server on the old port
description: “Port 5173 is in use, trying another one” and “Port 3000 is in use, trying 3001 instead” mean an older dev server is still running. How to find it, stop it, and make your dev server fail instead of drifting.
published: 2026-09-25
order: 6
keywords: port 5173 is in use trying another one, vite port 5174, vite strictPort, port 3000 is in use trying 3001 instead, next.js port 3001, create react app something is already running on port 3000
---

Start a dev server and it comes up on a port you didn’t expect:

```
Port 5173 is in use, trying another one...
  ➜  Local:   http://localhost:5174/
```

```
⚠ Port 3000 is in use, trying 3001 instead.
```

Vite, Next.js and most other dev servers do this on purpose. If their default port is taken, they try the next one rather than crash. It’s convenient, but it hides the real problem: **another server is already running on the port you meant to use.** Often it’s an older copy of the same project.

That causes some confusing bugs:

- You edit code and nothing changes in the browser, because the tab is still on the old server.
- Cookies, `localStorage` and OAuth redirect URLs are tied to `localhost:3000`, so sign-in breaks on 3001.
- Each copy uses its own memory. Three forgotten Next.js servers can easily use 3–4 GB.

## Find the server on the original port

```bash
lsof -nP -iTCP:5173 -sTCP:LISTEN
```

The output gives you the process name and PID. To see which project it is:

```bash
lsof -a -p <PID> -d cwd -Fn | tail -1 | cut -c2-
```

If it’s an old copy you don’t need, stop it with `kill <PID>`, then restart your dev server so it takes the port you wanted. More detail, including how to stop a whole process tree, is in [Port 3000 already in use on Mac](/guides/port-3000-already-in-use-mac).

## Make the dev server fail instead of drifting

If you’d rather know straight away, tell the dev server to exit when its port is busy.

**Vite:** set `strictPort`.

```ts
// vite.config.ts
export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
  },
})
```

Or on the command line: `vite --port 5173 --strictPort`. Vite then exits with an error instead of trying 5174.

**Next.js:** set the port explicitly in your dev script (`next dev -p 3000`) and check for an existing server first. A small `predev` script does it:

```json
{
  "scripts": {
    "predev": "! lsof -nP -iTCP:3000 -sTCP:LISTEN || (echo 'Port 3000 is busy' && exit 1)",
    "dev": "next dev -p 3000"
  }
}
```

**Create React App** asks “Something is already running on port 3000. Would you like to run the app on another port instead?”. Answer no, and find the other server.

Failing loudly matters even more when a coding agent is running the server. An agent that sees “Port 3000 is in use” will usually move on to the next port without telling you. An agent that sees an error will look for the existing server. See [Claude Code left a dev server running?](/guides/claude-code-dev-server-left-running)

## Default ports, for reference

| Tool | Default port |
| --- | --- |
| Next.js, Create React App, Remix, Rails, Express (by convention) | 3000 |
| Astro | 4321 |
| Vite, SvelteKit | 5173 |
| Vite preview | 4173 |
| Flask | 5000 |
| Storybook | 6006 |
| Django, uvicorn, `python -m http.server` | 8000 |
| Webpack dev server, many Java apps | 8080 |

When two tools share a default, give one of them a different port in its dev script.

## See every server at once

[WhatThePort](/) shows every dev server on your Mac in the menu bar, with its port, project name and git branch. If `:5173` and `:5174` are both there and both say `editor`, you know you have a duplicate, and you can stop the old one without opening a terminal.

[Download WhatThePort](/WhatThePort.dmg) (free, Apple Silicon, macOS 14 or later).

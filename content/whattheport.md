# WhatThePort

> Every dev server on your Mac, in the menu bar. WhatThePort is a free, open-source macOS menu bar app that shows what’s running on localhost: each dev server’s port, project, git branch, uptime, memory and CPU, and the Claude Code, Codex, Conductor or Pane session that started it. Stop the ones you forgot about in one click.

- Website and interactive demo: https://whattheport.dev
- Download (Apple Silicon, macOS 14 or later): https://whattheport.dev/WhatThePort.dmg
- Source code (MIT): https://github.com/tomjohndesign/what-the-port
- Guides: https://whattheport.dev/guides
- Price: free. No account.
- Made by Tom John (https://tomjohn.design)

## What it does

- **Every dev server at a glance.** Port, project name, git branch, uptime and memory for each local server, with stable port colors and a whole-Mac memory bar for servers, other apps and free RAM.
- **Knows which agent started it.** Servers launched by Claude Code, Codex, Conductor or [Pane](https://runpane.com) link back to the session that started them, so you can resume the conversation (`claude --resume`, `codex resume`), find the Conductor workspace, or open the Pane terminal that started the server.
- **Leak detection.** When a server passes 2 GB of memory or grows more than 500 MB in ten minutes, its memory reading and the menu bar icon turn amber and you get one notification with Details, Stop and Snooze. Thresholds are adjustable.
- **Resource charts.** Ten minutes of memory and CPU history per server, summed across its own process tree.
- **Clean up.** Preselects servers from deleted git worktrees or idle for hours, then stops each server’s own process tree in bulk. Postgres, Redis, MongoDB and MySQL are protected by default. Cleanup can be Off, Ask or Automatic; leaking servers are never stopped automatically.
- **Stop and restart.** Stop sends SIGTERM to the server’s own process tree, then SIGKILL after a short delay. Restart reruns the original command in the same folder.
- **Containers.** Ports published by Docker Desktop, OrbStack, Colima and Rancher Desktop containers show as their own rows: the container’s name, the compose folder’s git branch, and the container’s memory and CPU. Stop and Restart act on the container through the runtime’s Docker Engine socket (like `docker stop`), never on the runtime itself. Clean up only lists a container when it leaks, and database images are protected. Turn it off in Settings → Integrations.
- **Previews and pull requests (optional).** A Vercel preview button and the branch’s pull request, through the GitHub CLI you’re already signed in to.
- **Terminal UI.** `wtp` shows the same servers, details and Clean up in your terminal. `wtp list --json` prints them as JSON for scripts and coding agents.
- **Global shortcut.** ⌥⌘P opens the popover.
- **Interface language.** English, German, French, Spanish, Simplified Chinese, Hebrew, Japanese and Ukrainian. Select a language on the first onboarding screen or in Settings → General → Language; changes apply immediately. System default follows the Mac’s preferred languages, with English fallback. Hebrew uses right-to-left layout. `wtp language` reads the shared app preference; `wtp language ja` sets it; `wtp language system` restores automatic selection. The TUI, command help and JSON remain English; user data and commands stay unchanged. The first onboarding screen previews sample Servers rows in the chosen language. The site’s Languages section shows the Servers popover demo in each language, using the app’s own translations.
- **Native.** Written in Swift. No Electron, no Dock icon. Light and dark mode.

## Install

1. Download https://whattheport.dev/WhatThePort.dmg and open it.
2. Drag WhatThePort onto the Applications shortcut, then open it from Applications.
3. Start a dev server, then click the dot grid in the menu bar or press ⌥⌘P.

The prebuilt download is for Apple Silicon Macs running macOS 14 Sonoma or later. Updates are signed and install automatically when you quit. To build from source you need Swift 5.9 or later: `cd WhatThePort && swift build`.

## The wtp command

Onboarding offers to install `wtp`, or click Install… in Settings → General → Terminal. It links `/usr/local/bin/wtp` to the app.

```
wtp               Browse, open and stop servers
wtp list          Print servers and exit
wtp list --json   Print servers as JSON
wtp --version     Print the version
```

`wtp list --json` prints an array of servers. Each has `port`, `url`, `pid` (for container rows, a `container` object with `id`, `name`, `image`, `runtime`, `composeProject` and `composeService` instead), `name`, `branch`, `framework`, `folder`, `command`, `startedAt`, `memoryBytes`, `cpuPercent`, `status` (`running`, `attention` or `idle`), `protected`, `processes` and, when an agent started it, `session` (`kind`, `id`, `title`).

## How it works

WhatThePort reads listening TCP sockets with `lsof`, then inspects each server’s process tree through `libproc` and `sysctl`: memory footprint, CPU time, working directory, arguments and environment. From the working directory it finds the project manifest (package.json, pyproject.toml, Cargo.toml, go.mod, Gemfile), framework and git branch. Session links come from environment variables that Claude Code, Conductor and Pane pass to the commands they run, and from Codex’s session files. It rescans every 2 seconds. In monorepos, sibling servers stay separate from their shared task runner. When one process serves several ports, each row shows its server’s usage; totals count each process once, and the memory bar divides shared usage between those ports. Stopping or restarting that process affects all ports it serves.

By default it watches ports 3000–65535 and processes that look like dev servers: node, bun, deno, python, uvicorn, gunicorn, ruby, rails, puma, php, java, go, cargo, dotnet, elixir, nginx, postgres, redis, mongod, mysql and more. Both are configurable in Settings → Ports & processes. Standard Homebrew and python.org framework interpreters are supported, including their Python.app wrapper; backends embedded in desktop apps remain excluded. Ports held by a container runtime’s helper are the exception: they’re shown as container rows, matched to their container through the runtime’s Docker Engine socket.

Frameworks it recognizes include Next.js, Nuxt, Remix, Astro, SvelteKit, Vite, Expo, Angular, Create React App, Hono, Express, Storybook, Django, FastAPI, Flask, Rails, Rust and Go.

## Privacy

There’s no account and no analytics SDK. Everything the app shows comes from your Mac and stays there. It only goes online to check for updates, to send an anonymous once-a-day count of which features were used (no identifiers, and you can turn it off), and, if you turn them on, to look up Vercel previews and pull requests through the GitHub CLI.

## FAQ

### Is WhatThePort free?

Yes. It’s free and open source under the MIT license, with no account and no paid tier. There’s an optional tip jar. Once a month the app asks for a tip or a share. It stops after you tip, or you can turn it off in Settings → About.

### Does it work on Intel Macs or older macOS?

The prebuilt download is for Apple Silicon Macs on macOS 14 Sonoma or later. You can build it from source with Swift 5.9 or later.

### How is it different from `lsof` or `npx kill-port`?

Those answer one question about one port. WhatThePort keeps every dev server in view all the time, names them by project and branch, shows memory and CPU for the server’s own process tree, warns you about leaks, links servers to the agent session that started them, and stops the whole tree, not just one PID.

### Will it stop my database?

Not unless you choose to. Postgres, Redis, MongoDB and MySQL are protected from Clean up by default, and you can edit the protected list.

### Can a coding agent use it?

Yes. `wtp list --json` gives agents a machine-readable list of every server, its port, folder, branch, status and the session that started it, so an agent can reuse a running server instead of starting a duplicate on the next port.

### Does it show Docker containers?

Yes, for Docker Desktop, OrbStack, Colima and Rancher Desktop. Each published container port gets its own row with the container’s name, memory and CPU, and the git branch of the folder `docker compose` ran in. Stopping it stops that container, not the runtime. Clean up only suggests a container when it leaks, because its traffic can stay inside the compose network where the Mac can’t see it. Database images such as Postgres, Redis, MySQL, MariaDB and MongoDB are protected. `wtp list --json` gives container rows a `container` object instead of a `pid`, so scripts can’t signal the runtime by mistake.

### Where is the menu bar icon?

It’s a small 5×5 dot grid showing a colon. If the menu bar is full, macOS hides icons that don’t fit: click » at its edge on macOS 27, or check System Settings → Menu Bar. Opening WhatThePort again from Finder or Spotlight shows the popover.

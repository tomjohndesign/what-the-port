# WhatThePort

A macOS menu bar app that monitors your local development servers. See all running ports at a glance, get notifications when servers start or stop, and quickly open them in your browser.

## Features

- **Every dev server at a glance** - Port, project, git branch, uptime and memory for each server, with a live memory share bar
- **Knows what started it** - Links servers to the Claude Code, Codex or Conductor session that launched them
- **Resource charts** - 10 minutes of memory and CPU history per server, summed across its whole process tree
- **Leak detection** - Servers over 2 GB, or growing fast, turn amber in the list and the menu bar
- **Clean up** - Find servers from deleted worktrees or that have gone idle, and stop them in bulk
- **Stop and restart** - Stops the whole process tree; restart reruns the original command in the same folder

## Requirements

- macOS 14.0 or later
- Swift 5.9+

## Building

```bash
cd WhatThePort
swift build
```

To build the app bundle:

```bash
./build-app.sh
open .build/WhatThePort.app
```

## Usage

WhatThePort lives in the menu bar as a small dot grid. Click it to see every server:

- Hover a row to open it in the browser or stop it
- Click a row for details: session, branch, folder, command, charts and processes
- Click **Clean up** to tick the servers you want gone and stop them together

To check the UI without the menu bar, `WhatThePort --snapshot <dir>` renders each view with live data to PNG.

### Settings

Access Settings from the menu bar to configure:

- **Port range** - Which ports to monitor (default: 3000-9999)
- **Process allowlist** - Which processes to track

### Default Allowlist

WhatThePort monitors these processes by default:

| Category | Processes |
|----------|-----------|
| JavaScript | node, npm, npx, deno, bun |
| Python | python, python3, uvicorn, gunicorn, flask, django |
| Ruby | ruby, rails, puma, unicorn |
| Go | go, air |
| Rust | cargo, rustc |
| Java | java, gradle, mvn |
| PHP | php, php-fpm |
| .NET | dotnet |
| Elixir | beam.smp, elixir, mix |
| Servers | nginx, httpd, apache |
| Databases | postgres, mysql, redis-server, mongod |
| Docker | docker-proxy |

## How It Works

WhatThePort reads listening TCP sockets with `lsof`, then inspects each server's process tree directly through `libproc` and `sysctl`: memory footprint, CPU time, working directory, arguments and environment. From the working directory it finds the project manifest, framework and git branch. Session links come from environment variables that Claude Code and Conductor pass to the commands they run, and from Codex's session files. It rescans every 2 seconds.

## License

MIT

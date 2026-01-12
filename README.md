# WhatThePort

A macOS menu bar app that monitors your local development servers. See all running ports at a glance, get notifications when servers start or stop, and quickly open them in your browser.

## Features

- **Menu bar access** - View all running development servers from your menu bar
- **Auto-detection** - Scans for common dev tools (Node, Python, Ruby, Go, Rust, and more)
- **Notifications** - Get notified when ports start or stop listening
- **Quick actions** - Open in browser, copy URL, or stop the server with one click
- **Configurable** - Customize port range and process allowlist

## Requirements

- macOS 14.0 or later
- Swift 5.9+

## Building

```bash
cd WhatThePort
swift build
```

To run:

```bash
swift run
```

For a release build:

```bash
swift build -c release
```

The binary will be at `.build/release/WhatThePort`.

## Usage

Once running, WhatThePort appears in your menu bar with a network icon. Click it to see:

- List of active ports with process names
- For each port:
  - **Open in Browser** - Opens `http://localhost:<port>`
  - **Copy URL** - Copies the URL to clipboard
  - **Stop Server** - Terminates the process

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

WhatThePort uses `lsof` to scan for TCP ports in LISTEN state, then filters results by your configured port range and process allowlist. It rescans every 2 seconds to keep the list current.

## License

MIT

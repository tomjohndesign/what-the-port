# WhatThePort

A macOS menu bar app that monitors your local development servers. See all running ports at a glance, get notifications when servers start or stop, and quickly open them in your browser.

## Features

- **Every dev server at a glance** - Port, project, git branch, uptime and memory for each server, with a live memory share bar
- **Knows what started it** - Links servers to the Claude Code, Codex or Conductor session that launched them
- **Resource charts** - 10 minutes of memory and CPU history per server, summed across its whole process tree
- **Leak detection** - Servers over 2 GB, or growing fast, turn amber in the list and the menu bar
- **Clean up** - Find servers from deleted worktrees or that have gone idle, and stop them in bulk
- **Stop and restart** - Stops the whole process tree; restart reruns the original command in the same folder
- **Alerts** - Notifications with Details, Stop and Snooze when a server passes your memory threshold or starts leaking
- **Automatic clean up (optional)** - Off, Ask or Automatic; leaking servers are never stopped automatically
- **Previews and pull requests (optional)** - A Vercel preview button and the branch's pull request, via the GitHub CLI you're already signed in to
- **Global shortcut** - ⌥⌘P opens the popover

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

To render the onboarding loading, success, missing-tool, and approval states without changing macOS permissions or login items, run `WhatThePort --snapshot-onboarding <dir>`.

### Settings

Open Settings from the gear in the popover (⌘,):

- **General** - Launch at login, menu bar icon style, editor, global shortcut, scan interval
- **Alerts** - Memory threshold, leak warnings, snooze length, start/stop notifications
- **Clean up** - Off / Ask / Automatic, what counts as idle or stale, protected processes, force-quit delay
- **Ports & processes** - Port range and which processes count as dev servers
- **Integrations** - Claude Code, Codex and Conductor session links, branch names, Vercel previews and pull requests

## How It Works

WhatThePort reads listening TCP sockets with `lsof`, then inspects each server's process tree directly through `libproc` and `sysctl`: memory footprint, CPU time, working directory, arguments and environment. From the working directory it finds the project manifest, framework and git branch. Session links come from environment variables that Claude Code and Conductor pass to the commands they run, and from Codex's session files. It rescans every 2 seconds.

## License

MIT

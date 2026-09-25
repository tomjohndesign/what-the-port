---
title: Port 5000 already in use on Mac? It’s AirPlay Receiver
description: On macOS 12 Monterey and later, ControlCenter listens on ports 5000 and 7000 for AirPlay Receiver. How to confirm it, turn it off, or move Flask and other apps to a different port.
published: 2026-09-25
order: 8
keywords: port 5000 already in use mac, port 5000 controlcenter, airplay receiver port 5000, flask port 5000 mac, port 7000 in use mac, address already in use port 5000 macos
---

You start a Flask app, or anything else that defaults to port 5000, and get:

```
Address already in use
Port 5000 is in use by another program.
```

You haven’t started anything else. The culprit is macOS itself.

## Confirm it

```bash
lsof -nP -iTCP:5000 -sTCP:LISTEN
```

```
COMMAND     PID USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME
ControlCe   612  you    9u  IPv4  0x…         0t0  TCP *:5000 (LISTEN)
```

`ControlCe` is `ControlCenter`, the process behind AirPlay Receiver. Since macOS 12 Monterey, your Mac can receive AirPlay from an iPhone or iPad, and it listens on ports 5000 and 7000 to do it.

Don’t `kill` it. ControlCenter also runs the menu bar’s Control Center, and macOS will simply restart it.

## Option 1: turn off AirPlay Receiver

If you never AirPlay to your Mac:

1. Open **System Settings → General → AirDrop & Handoff**.
2. Turn off **AirPlay Receiver**.

Ports 5000 and 7000 are free straight away.

## Option 2: use a different port

If you’d rather keep AirPlay Receiver, move your app instead. Anything other than 5000 and 7000 works.

```bash
flask run --port 5001
```

```python
# app.py
app.run(port=5001)
```

For other tools, look for a `--port` flag or a `PORT` environment variable. Remember to update anything that points at the old port, such as OAuth redirect URLs, proxy settings in your front end, or Docker Compose port mappings.

## If it isn’t ControlCenter

If `lsof` shows `node`, `Python` or something else you recognise, it’s a real server that’s still running. [Port 3000 already in use on Mac](/guides/port-3000-already-in-use-mac) covers finding which project it belongs to and stopping it cleanly, and the same steps work for any port.

## See what’s running without guessing

[WhatThePort](/) lists every dev server on your Mac in the menu bar, with its port, project name, git branch and memory, so you can see what’s on a port before your next server tries to take it. It only lists dev-server-like processes, so system services like ControlCenter stay out of the way.

[Download WhatThePort](/WhatThePort.dmg) (free, Apple Silicon, macOS 14 or later).

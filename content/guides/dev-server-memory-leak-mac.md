---
title: Dev servers eating your Mac’s RAM: finding leaks in Next.js, Vite and Node
description: Why local dev servers grow to gigabytes of memory, how to measure a whole server’s process tree on macOS, how to tell a leak from normal growth, and what to do about it.
published: 2026-09-25
order: 7
keywords: next dev memory leak, next.js dev server high memory usage, turbopack memory usage, too many node processes mac, kill all node processes mac, your system has run out of application memory, node memory leak mac
---

Your fans spin up, everything gets slow, and eventually macOS shows “Your system has run out of application memory”. Activity Monitor is full of `node`. Local dev servers are a common cause, for two reasons: each one can grow to several gigabytes, and the ones you forgot about keep using memory long after you stopped looking at them.

## Measure the whole server, not one process

A dev server is rarely one process. `npm run dev` for a Next.js app is typically `npm`, then `next dev`, then a `next-server` worker, and sometimes a TypeScript checker or a separate bundler process. Activity Monitor lists them separately, so no single row looks alarming.

Find the process on the port, then list its whole process group with memory in megabytes:

```bash
pid=$(lsof -t -iTCP:3000 -sTCP:LISTEN)
ps -o pid=,rss=,command= -g $(ps -o pgid= -p $pid) \
  | awk '{ total += $2; printf "%6d %7.0f MB  %s\n", $1, $2/1024, substr($0, index($0,$3)) }
         END { printf "Total  %7.0f MB\n", total/1024 }'
```

`rss` is resident memory, which is close enough to spot a problem. Activity Monitor’s Memory column shows each process’s *footprint*, which is a better measure of what the process costs your Mac and usually a little higher.

## Normal growth or a leak?

Dev servers get bigger as you use them. They compile pages on demand and cache the results, so visiting twenty routes in a large Next.js app can take it from 300 MB to 1.5 GB. That’s expected. What matters is the shape:

- **Normal:** memory rises as you open new pages, then levels off.
- **Leak:** memory keeps climbing while you edit the same file or reload the same page. Every hot reload adds a few megabytes that never come back.

Watch it for a few minutes while you work:

```bash
while sleep 10; do echo "$(date +%T)  $(( $(ps -o rss= -p $pid) / 1024 )) MB"; done
```

A server that grows by hundreds of megabytes over ten minutes of ordinary editing is worth investigating.

## What to do about it

**Restart it.** The quick fix for a dev server leak is a restart. You lose the compile cache, but you get the memory back.

**Stop the servers you aren’t using.** Every idle dev server holds its memory. Two old copies of the same app on 3001 and 3002 can use more than the one you’re working on. See [How to see every dev server running on your Mac](/guides/see-every-dev-server-running-on-mac).

**Find the leak.** Start the server with Node’s inspector and take heap snapshots in Chrome DevTools (`chrome://inspect`). Run the framework’s binary directly; through `npm run`, npm itself would take the inspector:

```bash
NODE_OPTIONS='--inspect' ./node_modules/.bin/next dev
```

Take a snapshot, reload the page ten times, take another, and compare. Objects that keep growing between snapshots, such as module caches, event listeners or long-lived arrays in your own code, are the leak. Next.js has a memory usage guide in its docs, and Node’s `--heapsnapshot-near-heap-limit=2` flag writes snapshots automatically when a process gets close to running out of memory.

**Cap it.** `NODE_OPTIONS='--max-old-space-size=4096'` limits the JavaScript heap to 4 GB, so a runaway server crashes instead of taking the whole Mac with it.

## If you just want everything gone

```bash
killall node
```

This stops every process named `node` that you own: every dev server, but also any watchers, build tools and CLIs you had running. It works, but it’s a blunt instrument, and you’ll restart servers you still wanted.

## Get told before your fans do

[WhatThePort](/) is a free menu bar app that tracks the memory and CPU of every dev server on your Mac, summed across its whole process tree, with ten minutes of history per server. When a server passes 2 GB, or grows more than 500 MB in ten minutes, its memory reading and the menu bar icon turn amber and you get one notification with **Details**, **Stop** and **Snooze**. The thresholds are adjustable in Settings.

The popover also shows a whole-Mac memory bar split into dev servers, other apps and free memory, so you can see at a glance how much of your RAM your servers are using.

[Download WhatThePort](/WhatThePort.dmg) for Apple Silicon Macs on macOS 14 or later.

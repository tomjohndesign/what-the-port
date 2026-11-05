// Installed copies only update when CFBundleVersion goes up, so a change to the
// app without a bump never reaches them, and republishes different code under
// the same version. `node scripts/check-app-version.mjs <base> <head>` fails then.
// Pull requests run it, and so does the deploy, before anything is published.
import { execFileSync } from 'node:child_process'

const APP_PATHS = [
  'WhatThePort/Sources',
  'WhatThePort/Resources',
  'WhatThePort/Info.plist',
  'WhatThePort/Package.swift',
  'WhatThePort/Package.resolved',
  'WhatThePort/build-app.sh',
]

const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()

function build(commit) {
  const plist = git('show', `${commit}:WhatThePort/Info.plist`)
  const value = plist.match(/<key>CFBundleVersion<\/key>\s*<string>(\d+)<\/string>/)?.[1]
  if (!value) {
    console.error(`check-app-version: no numeric CFBundleVersion in Info.plist at ${commit}.`)
    process.exit(1)
  }
  return Number(value)
}

const [base, head = 'HEAD'] = process.argv.slice(2)
if (!base) {
  console.error('Usage: node scripts/check-app-version.mjs <base> [head]')
  process.exit(64)
}

// A new branch or a force push has no usable base to compare with.
try {
  git('cat-file', '-e', `${base}^{commit}`)
} catch {
  console.log(`check-app-version: can't compare with ${base}, so skipping.`)
  process.exit(0)
}

const changed = git('diff', '--name-only', `${base}...${head}`, '--', ...APP_PATHS).split('\n').filter(Boolean)
if (!changed.length) {
  console.log('check-app-version: the app is unchanged.')
  process.exit(0)
}

const before = build(base)
const after = build(head)
if (after <= before) {
  console.error(
    `check-app-version: the app changed but CFBundleVersion is still ${after}, so installed copies won't update.\n` +
      `Raise it above ${before} in WhatThePort/Info.plist, along with CFBundleShortVersionString. Changed:\n` +
      changed.map((file) => `  ${file}`).join('\n'),
  )
  process.exit(1)
}
console.log(`check-app-version: the app changed and its build goes from ${before} to ${after}.`)

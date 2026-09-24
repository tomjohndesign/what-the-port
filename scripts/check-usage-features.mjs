// The site only counts usage features it knows, so middleware.ts must list
// exactly the features the Mac app reports (Usage.Feature in Usage.swift).
import { readFileSync } from 'node:fs'

const swift = readFileSync('WhatThePort/Sources/WhatThePort/Engine/Usage.swift', 'utf8')
const block = swift.match(/enum Feature: String, CaseIterable \{([\s\S]*?)\n {4}\}/)?.[1] ?? ''
const app = [...block.matchAll(/case (\w+)(?: = "([a-z-]+)")?/g)].map((m) => m[2] ?? m[1])

const middleware = readFileSync('middleware.ts', 'utf8')
const list = middleware.match(/new Set\(\[([\s\S]*?)\]\)/)?.[1] ?? ''
const site = [...list.matchAll(/'([a-z-]+)'/g)].map((m) => m[1])

const missing = app.filter((f) => !site.includes(f))
const extra = site.filter((f) => !app.includes(f))
if (!app.length || missing.length || extra.length) {
  console.error(`check-usage-features: app and site disagree. Missing on site: ${missing.join(', ') || 'none'}. Unknown to app: ${extra.join(', ') || 'none'}.`)
  process.exit(1)
}
console.log(`check-usage-features: ${app.length} features match.`)

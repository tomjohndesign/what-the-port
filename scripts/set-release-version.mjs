// Every merge to main is a release. The deploy runs this to give the commit its
// own version in the checkout's Info.plist: the build is the number of commits
// on main, and the version adds it to the major and minor set in the file.
// Installed copies only update when the build goes up. Needs full git history.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'

const FEED = 'https://whattheport.dev/updates/appcast.xml'
const PLIST = 'WhatThePort/Info.plist'

const fail = (message) => {
  console.error(`set-release-version: ${message}`)
  process.exit(1)
}

if (execFileSync('git', ['rev-parse', '--is-shallow-repository'], { encoding: 'utf8' }).trim() === 'true') {
  fail('the checkout is shallow, so it can\'t count commits. Use fetch-depth: 0.')
}
const build = Number(execFileSync('git', ['rev-list', '--count', 'HEAD'], { encoding: 'utf8' }).trim())

// A rewritten main could count lower than what's published, and installed copies
// would silently ignore it. A feed we can't read doesn't stop a release.
const feed = await fetch(FEED).then((response) => (response.ok ? response.text() : ''), () => '')
const published = Number(feed.match(/<sparkle:version>(\d+)<\/sparkle:version>/)?.[1] ?? 0)
if (build < published) fail(`this commit would be build ${build}, but build ${published} is already published.`)

const plist = readFileSync(PLIST, 'utf8')
const key = (name) => new RegExp(`(<key>${name}</key>\\s*<string>)([^<]*)(</string>)`)
const [major, minor] = plist.match(key('CFBundleShortVersionString'))?.[2].split('.') ?? []
if (!major || !minor) fail(`${PLIST} needs a CFBundleShortVersionString like 2.6.`)
const version = `${major}.${minor}.${build}`

writeFileSync(
  PLIST,
  plist
    .replace(key('CFBundleShortVersionString'), (_, open, __, close) => open + version + close)
    .replace(key('CFBundleVersion'), (_, open, __, close) => open + build + close),
)
console.log(`set-release-version: ${version} (build ${build}), up from build ${published}.`)

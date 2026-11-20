// Sets the app version in the checkout's Info.plist during the deploy.
//
// `node scripts/set-release-version.mjs` numbers a new release: the build is the
// number of commits on main, and the version adds it to the major and minor set
// in the file. Installed copies only update when the build goes up. It also
// writes dist/release.json, which the site publishes as /release.json so later
// deploys know which app is live and which commit it came from. Needs full git history.
//
// `node scripts/set-release-version.mjs --published public/release.json` sets the
// version to an app that's already published, for deploys that reuse it.
import { execFileSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'

const FEED = 'https://whattheport.dev/updates/appcast.xml'
const PLIST = 'WhatThePort/Info.plist'

const fail = (message) => {
  console.error(`set-release-version: ${message}`)
  process.exit(1)
}

const plist = readFileSync(PLIST, 'utf8')
const key = (name) => new RegExp(`(<key>${name}</key>\\s*<string>)([^<]*)(</string>)`)
const write = (version, build) =>
  writeFileSync(
    PLIST,
    plist
      .replace(key('CFBundleShortVersionString'), (_, open, __, close) => open + version + close)
      .replace(key('CFBundleVersion'), (_, open, __, close) => open + build + close),
  )

const [flag, path] = process.argv.slice(2)
if (flag === '--published') {
  const { version, build } = JSON.parse(readFileSync(path, 'utf8'))
  if (!version || !build) fail(`${path} needs a version and build.`)
  write(version, build)
  console.log(`set-release-version: ${version} (build ${build}), the published app.`)
  process.exit(0)
}

if (execFileSync('git', ['rev-parse', '--is-shallow-repository'], { encoding: 'utf8' }).trim() === 'true') {
  fail('the checkout is shallow, so it can\'t count commits. Use fetch-depth: 0.')
}
const build = Number(execFileSync('git', ['rev-list', '--count', 'HEAD'], { encoding: 'utf8' }).trim())
const commit = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim()

// A rewritten main could count lower than what's published, and installed copies
// would silently ignore it. A feed we can't read doesn't stop a release.
const feed = await fetch(FEED).then((response) => (response.ok ? response.text() : ''), () => '')
const published = Number(feed.match(/<sparkle:version>(\d+)<\/sparkle:version>/)?.[1] ?? 0)
if (build <= published) fail(`this commit would be build ${build}, but build ${published} is already published.`)

const [major, minor] = plist.match(key('CFBundleShortVersionString'))?.[2].split('.') ?? []
if (!major || !minor) fail(`${PLIST} needs a CFBundleShortVersionString like 2.6.`)
const version = `${major}.${minor}.${build}`

write(version, build)
mkdirSync('dist', { recursive: true })
writeFileSync('dist/release.json', `${JSON.stringify({ version, build: String(build), commit }, null, 2)}\n`)
console.log(`set-release-version: ${version} (build ${build}), up from build ${published}.`)

// The app releases at most once a day, because installed copies have to restart
// to update. The site deploys on every merge and reuses the published app.
// The deploy runs this first to decide what to do, and writes to $GITHUB_OUTPUT:
//   release  true to build and publish a new app version
//   deploy   true to deploy the site (a daily run with no app changes does nothing)
//   version, build, commit  the published app the site reuses when release is false
// Usage: node scripts/plan-release.mjs <push|schedule|workflow_dispatch> [--release-app]
// Needs full git history.
import { execFileSync } from 'node:child_process'
import { appendFileSync } from 'node:fs'

const SITE = 'https://whattheport.dev'
// Changes here change the app. Its docs and tests don't.
const APP_PATHS = ['WhatThePort', ':(exclude,glob)WhatThePort/**/*.md', ':(exclude)WhatThePort/Tests']

const [event, flag] = process.argv.slice(2)
const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim()
const succeeds = (...args) => {
  try {
    execFileSync('git', args, { stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}
const get = (path) => fetch(SITE + path).then((response) => (response.ok ? response.text() : ''), () => '')

// Each release publishes /release.json. Releases from before it only have the
// feed, whose build is the number of commits on main at the released commit.
async function published() {
  try {
    const release = JSON.parse(await get('/release.json'))
    if (release.version && release.build && release.commit) return release
  } catch {}
  const item = (await get('/updates/appcast.xml')).match(/<item>[\s\S]*?<\/item>/)?.[0] ?? ''
  const build = item.match(/<sparkle:version>(\d+)<\/sparkle:version>/)?.[1]
  const version = item.match(/<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/)?.[1]
  if (!build || !version) return null
  const commit = git('rev-list', '--first-parent', 'HEAD')
    .split('\n')
    .find((sha) => git('rev-list', '--count', sha) === build)
  return commit ? { version, build, commit } : null
}

const current = await published()
const appChanged = () =>
  !succeeds('merge-base', '--is-ancestor', current.commit, 'HEAD') ||
  !succeeds('diff', '--quiet', current.commit, 'HEAD', '--', ...APP_PATHS)

let release, deploy, reason
if (flag === '--release-app') {
  ;[release, deploy, reason] = [true, true, 'a release was requested']
} else if (!current) {
  ;[release, deploy, reason] = [true, true, 'no app is published yet']
} else if (event === 'schedule') {
  release = deploy = appChanged()
  reason = release ? `the app changed since ${current.version}` : `the app hasn't changed since ${current.version}`
} else {
  ;[release, deploy, reason] = [false, true, `the site reuses ${current.version}; the app releases daily`]
}

const outputs = { release, deploy, ...(release ? {} : current) }
if (process.env.GITHUB_OUTPUT) {
  appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(outputs).map(([k, v]) => `${k}=${v}\n`).join(''))
}
console.log(`plan-release: ${release ? 'release the app' : deploy ? 'deploy the site only' : 'nothing to do'}, because ${reason}.`)

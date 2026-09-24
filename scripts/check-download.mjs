// Production must serve the app built from this commit. The deploy workflow
// builds it into public/; nothing else should publish a download.
import { existsSync, readFileSync, statSync } from 'node:fs'

const production = process.env.VERCEL_ENV === 'production' || process.env.VERCEL_TARGET_ENV === 'production'
if (!production) process.exit(0)

const fail = (message) => {
  console.error(`check-download: ${message}`)
  console.error('Deploy production through .github/workflows/deploy.yml, which builds the app first.')
  process.exit(1)
}

const zip = 'public/WhatThePort.zip'
if (!existsSync(zip)) fail(`${zip} is missing.`)

// Release builds also publish the signed feed. Its newest item must be this
// commit's build, and the download must be that exact archive.
const feed = 'public/updates/appcast.xml'
if (existsSync(feed)) {
  const plist = readFileSync('WhatThePort/Info.plist', 'utf8')
  const build = plist.match(/<key>CFBundleVersion<\/key>\s*<string>([^<]+)<\/string>/)?.[1]
  const item = readFileSync(feed, 'utf8').match(/<item>[\s\S]*?<\/item>/)?.[0] ?? ''
  const feedBuild = item.match(/<sparkle:version>([^<]+)<\/sparkle:version>/)?.[1]
  const length = Number(item.match(/<enclosure[^>]*\slength="(\d+)"/)?.[1])
  if (feedBuild !== build) fail(`the update feed is for build ${feedBuild}, but Info.plist is build ${build}.`)
  if (statSync(zip).size !== length) fail(`${zip} isn't the build ${build} update archive.`)
}
console.log('check-download: the download matches this release.')

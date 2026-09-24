// Production must serve the app built from this commit. The deploy workflow
// builds it into public/; nothing else should publish a download.
import { closeSync, existsSync, openSync, readFileSync, readSync, statSync } from 'node:fs'

const production = process.env.VERCEL_ENV === 'production' || process.env.VERCEL_TARGET_ENV === 'production'
if (!production) process.exit(0)

const fail = (message) => {
  console.error(`check-download: ${message}`)
  console.error('Deploy production through .github/workflows/deploy.yml, which builds the app first.')
  process.exit(1)
}

// The download is a disk image. Every UDIF image ends with a 512-byte "koly" trailer.
const dmg = 'public/WhatThePort.dmg'
if (!existsSync(dmg)) fail(`${dmg} is missing.`)
const trailer = Buffer.alloc(4)
const fd = openSync(dmg, 'r')
readSync(fd, trailer, 0, 4, statSync(dmg).size - 512)
closeSync(fd)
if (trailer.toString('latin1') !== 'koly') fail(`${dmg} isn't a disk image.`)

// Release builds also publish the signed feed. Its newest item must be this
// commit's build, and its update archive must be published alongside it.
const feed = 'public/updates/appcast.xml'
if (existsSync(feed)) {
  const plist = readFileSync('WhatThePort/Info.plist', 'utf8')
  const build = plist.match(/<key>CFBundleVersion<\/key>\s*<string>([^<]+)<\/string>/)?.[1]
  const item = readFileSync(feed, 'utf8').match(/<item>[\s\S]*?<\/item>/)?.[0] ?? ''
  const feedBuild = item.match(/<sparkle:version>([^<]+)<\/sparkle:version>/)?.[1]
  const url = item.match(/<enclosure[^>]*\surl="([^"]+)"/)?.[1] ?? ''
  const length = Number(item.match(/<enclosure[^>]*\slength="(\d+)"/)?.[1])
  const archive = `public/updates/${url.split('/').pop()}`
  if (feedBuild !== build) fail(`the update feed is for build ${feedBuild}, but Info.plist is build ${build}.`)
  if (!existsSync(archive) || statSync(archive).size !== length) fail(`${archive} isn't the build ${build} update archive.`)
}
console.log('check-download: the download matches this release.')

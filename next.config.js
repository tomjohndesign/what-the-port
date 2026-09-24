const fs = require('fs')
const path = require('path')

// CI builds the download into public/ for each production deploy; it's never
// checked in. Anywhere it's missing (local dev, preview deployments), downloads
// go to production, which always has the latest release. Production builds
// can't run without it (scripts/check-download.mjs), so this can't loop.
const hasDownload = fs.existsSync(path.join(__dirname, 'public/WhatThePort.dmg'))

// The app's tip jar opens /tip, so the payment page can change without an app
// update. Set TIP_URL (a Stripe Payment Link) in the Vercel project. Without it,
// /tip goes to production, which can't build without it (scripts/check-tip.mjs).
const tipUrl = process.env.TIP_URL || 'https://whattheport.dev/tip'

/** @type {import('next').NextConfig} */
const nextConfig = {
  async redirects() {
    const tip = { source: '/tip', destination: tipUrl, permanent: false }
    // The download was a zip before 2.4. Keep old links working.
    const legacy = { source: '/WhatThePort.zip', destination: '/WhatThePort.dmg', permanent: false }
    if (hasDownload) return [tip, legacy]
    return [tip, legacy, { source: '/WhatThePort.dmg', destination: 'https://whattheport.dev/WhatThePort.dmg', permanent: false }]
  },
}

module.exports = nextConfig

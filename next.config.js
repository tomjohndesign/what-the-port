const fs = require('fs')
const path = require('path')

// CI builds the download into public/ for each production deploy; it's never
// checked in. Anywhere it's missing (local dev, preview deployments), downloads
// go to production, which always has the latest release. Production builds
// can't run without it (scripts/check-download.mjs), so this can't loop.
const hasDownload = fs.existsSync(path.join(__dirname, 'public/WhatThePort.dmg'))

/** @type {import('next').NextConfig} */
const nextConfig = {
  async redirects() {
    // The download was a zip before 2.4. Keep old links working.
    const legacy = { source: '/WhatThePort.zip', destination: '/WhatThePort.dmg', permanent: false }
    if (hasDownload) return [legacy]
    return [legacy, { source: '/WhatThePort.dmg', destination: 'https://whattheport.dev/WhatThePort.dmg', permanent: false }]
  },
}

module.exports = nextConfig

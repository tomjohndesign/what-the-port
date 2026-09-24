const fs = require('fs')
const path = require('path')

// CI builds the download into public/ for each production deploy; it's never
// checked in. Anywhere it's missing (local dev, preview deployments), downloads
// go to production, which always has the latest release. Production builds
// can't run without it (scripts/check-download.mjs), so this can't loop.
const hasDownload = fs.existsSync(path.join(__dirname, 'public/WhatThePort.zip'))

/** @type {import('next').NextConfig} */
const nextConfig = {
  async redirects() {
    if (hasDownload) return []
    return [{ source: '/WhatThePort.zip', destination: 'https://whattheport.dev/WhatThePort.zip', permanent: false }]
  },
}

module.exports = nextConfig

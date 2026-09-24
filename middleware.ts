import { NextResponse, type NextRequest } from 'next/server'

// Anonymous usage from the Mac app (see WhatThePort/Sources/WhatThePort/Engine/Usage.swift).
// Copies that share usage request /usage/<feature> once a day for each feature
// used, so Vercel's request counts per path are installs per feature. Nothing
// is stored or forwarded here; the response is empty.
const FEATURES = new Set([
  'active',
  'popover',
  'shortcut',
  'details',
  'open-browser',
  'open-editor',
  'stop',
  'restart',
  'clean-up',
  'auto-clean-up',
  'memory-alert',
  'resume-session',
  'vercel-preview',
  'pull-request',
])

export function middleware(request: NextRequest) {
  const feature = request.nextUrl.pathname.slice('/usage/'.length)
  return new NextResponse(null, {
    status: FEATURES.has(feature) ? 204 : 404,
    headers: { 'cache-control': 'no-store' },
  })
}

export const config = { matcher: '/usage/:path*' }

import type { Metadata } from 'next'
import { Analytics } from '@vercel/analytics/react'
import { SpeedInsights } from '@vercel/speed-insights/next'
import './globals.css'
import { AUTHOR, OG_IMAGE, SITE_DESCRIPTION, SITE_NAME, SITE_TITLE, SITE_URL } from '@/lib/content'

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: SITE_TITLE, template: `%s · ${SITE_NAME}` },
  description: SITE_DESCRIPTION,
  applicationName: SITE_NAME,
  authors: [AUTHOR],
  creator: AUTHOR.name,
  keywords: [
    'localhost',
    'dev server',
    'port already in use',
    'EADDRINUSE',
    'kill port mac',
    'lsof',
    'menu bar app',
    'macOS',
    'port monitor',
    'localhost manager',
    'Claude Code',
    'Codex',
    'Conductor',
    'git worktrees',
    'memory leak',
  ],
  alternates: { canonical: '/', types: { 'text/markdown': '/index.md' } },
  robots: { index: true, follow: true, 'max-image-preview': 'large', 'max-snippet': -1 },
  icons: {
    icon: [
      {
        url: '/icon-light.svg?v=2',
        type: 'image/svg+xml',
        sizes: 'any',
        media: '(prefers-color-scheme: light)',
      },
      {
        url: '/icon-dark.svg?v=2',
        type: 'image/svg+xml',
        sizes: 'any',
        media: '(prefers-color-scheme: dark)',
      },
    ],
  },
  openGraph: {
    type: 'website',
    siteName: SITE_NAME,
    url: '/',
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: [OG_IMAGE],
  },
  twitter: {
    card: 'summary_large_image',
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: [OG_IMAGE],
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <head>
        <link rel="preload" href="/fonts/Geist-Regular.ttf" as="font" type="font/ttf" crossOrigin="" />
        <link rel="preload" href="/fonts/Geist-Medium.ttf" as="font" type="font/ttf" crossOrigin="" />
        <link rel="preload" href="/scenes/house.jpg" as="image" />
        <link rel="preload" href="/scenes/laptop.jpg" as="image" />
        <link rel="alternate" type="text/plain" href="/llms.txt" title="llms.txt" />
      </head>
      <body>
        {children}
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  )
}

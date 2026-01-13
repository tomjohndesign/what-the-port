import type { Metadata } from 'next'
import { Analytics } from '@vercel/analytics/react'

export const metadata: Metadata = {
  title: 'WhatThePort - Monitor Your Dev Servers',
  description: 'A macOS menu bar app to see what\'s running on your ports',
  icons: {
    icon: [
      {
        url: '/icon-light.svg',
        media: '(prefers-color-scheme: light)',
      },
      {
        url: '/icon-dark.svg',
        media: '(prefers-color-scheme: dark)',
      },
    ],
  },
  openGraph: {
    title: 'WhatThePort - Monitor Your Dev Servers',
    description: 'A macOS menu bar app to see what\'s running on your ports',
    images: [
      {
        url: '/screenshot.png',
        width: 1262,
        height: 812,
        alt: 'WhatThePort screenshot showing ports with node and Python processes',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'WhatThePort - Monitor Your Dev Servers',
    description: 'A macOS menu bar app to see what\'s running on your ports',
    images: ['/screenshot.png'],
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body style={{ margin: 0, padding: 0, backgroundColor: '#000' }}>
        {children}
        <Analytics />
      </body>
    </html>
  )
}

import type { Metadata } from 'next'
import { Analytics } from '@vercel/analytics/react'
import './globals.css'

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
      <head>
        <link rel="preload" href="/fonts/Geist-Regular.ttf" as="font" type="font/ttf" crossOrigin="" />
        <link rel="preload" href="/fonts/Geist-Medium.ttf" as="font" type="font/ttf" crossOrigin="" />
        <link rel="preload" href="/scenes/house.jpg" as="image" />
        <link rel="preload" href="/scenes/laptop.jpg" as="image" />
      </head>
      <body>
        {children}
        <Analytics />
      </body>
    </html>
  )
}

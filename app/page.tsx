'use client'

import Image from 'next/image'
import { useEffect, useState } from 'react'

export default function Home() {
  const [stars, setStars] = useState<number | null>(null)

  useEffect(() => {
    fetch('https://api.github.com/repos/tomjohndesign/what-the-port')
      .then(res => res.json())
      .then(data => {
        if (data.stargazers_count !== undefined) {
          setStars(data.stargazers_count)
        }
      })
      .catch(() => {})
  }, [])

  return (
    <main style={{
      minHeight: '100vh',
      backgroundColor: '#000',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '2rem',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    }}>
      <h1 style={{
        color: '#fff',
        fontSize: '3rem',
        fontWeight: 600,
        marginBottom: '0.5rem',
        textAlign: 'center',
      }}>
        WhatThePort
      </h1>

      <p style={{
        color: '#888',
        fontSize: '1.25rem',
        marginBottom: '3rem',
        textAlign: 'center',
      }}>
        See what&apos;s running on your ports from the menu bar
      </p>

      <Image
        src="/screenshot.png"
        alt="WhatThePort screenshot showing ports 3000, 3001, and 8000 with node and Python processes"
        width={631}
        height={406}
        style={{
          borderRadius: '12px',
          boxShadow: '0 25px 50px -12px rgba(255, 255, 255, 0.1)',
          marginBottom: '3rem',
        }}
        priority
      />

      <a
        href="/WhatThePort.zip"
        download
        style={{
          backgroundColor: '#fff',
          color: '#000',
          padding: '1rem 2rem',
          borderRadius: '8px',
          fontSize: '1.125rem',
          fontWeight: 500,
          textDecoration: 'none',
          transition: 'transform 0.2s, box-shadow 0.2s',
        }}
      >
        Download for macOS
      </a>

      <a
        href="https://github.com/tomjohndesign/what-the-port"
        target="_blank"
        rel="noopener noreferrer"
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '0.5rem',
          marginTop: '1rem',
          padding: '0.625rem 1.25rem',
          backgroundColor: 'transparent',
          border: '1px solid #333',
          borderRadius: '8px',
          color: '#888',
          fontSize: '0.9rem',
          textDecoration: 'none',
          transition: 'border-color 0.2s, color 0.2s',
        }}
      >
        <svg height="18" width="18" viewBox="0 0 16 16" fill="currentColor">
          <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
        </svg>
        View on GitHub
        {stars !== null && (
          <span style={{
            backgroundColor: '#222',
            padding: '0.125rem 0.5rem',
            borderRadius: '4px',
            fontSize: '0.8rem',
            marginLeft: '0.25rem',
          }}>
            {stars}
          </span>
        )}
      </a>

      <p style={{
        color: '#555',
        fontSize: '0.875rem',
        marginTop: '1rem',
      }}>
        Requires macOS 13.0 or later
      </p>

      <div style={{
        marginTop: '2rem',
        padding: '1.5rem',
        backgroundColor: '#111',
        borderRadius: '8px',
        maxWidth: '500px',
        textAlign: 'left',
      }}>
        <p style={{
          color: '#888',
          fontSize: '0.875rem',
          marginBottom: '0.75rem',
        }}>
          After downloading, if macOS says the app is damaged, run this in Terminal:
        </p>
        <code style={{
          display: 'block',
          backgroundColor: '#000',
          padding: '0.75rem 1rem',
          borderRadius: '4px',
          color: '#4ade80',
          fontSize: '0.8rem',
          fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, monospace',
          overflowX: 'auto',
        }}>
          xattr -cr ~/Downloads/WhatThePort.app
        </code>
      </div>

      <footer style={{
        marginTop: '4rem',
        paddingTop: '2rem',
        borderTop: '1px solid #222',
        textAlign: 'center',
      }}>
        <p style={{
          color: '#888',
          fontSize: '0.875rem',
          marginBottom: '0.75rem',
        }}>
          Created by Tomjohn
        </p>
        <div style={{
          display: 'flex',
          gap: '1.5rem',
          justifyContent: 'center',
        }}>
          <a href="https://www.tomjohn.design" target="_blank" rel="noopener noreferrer" style={{ color: '#666', fontSize: '0.875rem', textDecoration: 'none' }}>
            Website
          </a>
          <a href="https://www.linkedin.com/in/tomjohndesign" target="_blank" rel="noopener noreferrer" style={{ color: '#666', fontSize: '0.875rem', textDecoration: 'none' }}>
            LinkedIn
          </a>
          <a href="https://x.com/tomjohndesign" target="_blank" rel="noopener noreferrer" style={{ color: '#666', fontSize: '0.875rem', textDecoration: 'none' }}>
            X
          </a>
        </div>
      </footer>
    </main>
  )
}

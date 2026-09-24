'use client'

import { type CSSProperties, useEffect, useState } from 'react'
import styles from './landing.module.css'
import { AppPopover, useDemo } from './App'
import { SectionCopy } from './Copy'
import { DotMatrix } from './DotMatrix'
import { BatteryIcon, DotGrid, GitHubIcon, WifiIcon } from './icons'
import { GET_IT, GITHUB_URL, SECTIONS } from './sections'

type Props = {
  active: number
  stars: number | null
  onNavigate: (index: number) => void
}

// The menu bar clock, in the visitor's own time and locale ("Wed Sep 23 1:24 PM" / "Wed 23 Sep 13:24").
function Clock() {
  const [now, setNow] = useState<Date | null>(null)

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>
    const tick = () => {
      setNow(new Date())
      timer = setTimeout(tick, 60_000 - (Date.now() % 60_000) + 50)
    }
    tick()
    return () => clearTimeout(timer)
  }, [])

  const label = now
    ? new Intl.DateTimeFormat(undefined, {
        weekday: 'short',
        day: 'numeric',
        month: 'short',
        hour: 'numeric',
        minute: '2-digit',
      })
        .format(now)
        .replace(/,/g, '')
    : ''

  return (
    <time className={styles.clock} dateTime={now?.toISOString()} suppressHydrationWarning>
      {label}
    </time>
  )
}

// The laptop's desktop, laid out at 1152×720 ("larger text" scaling) so the UI
// stays legible once the laptop is scaled down to fit the room.
// Headlines scroll with the page via the --p custom property; everything else is fixed.
export function Screen({ active, stars, onNavigate }: Props) {
  const demo = useDemo(active)
  const alert = demo.running.some((s) => s.status === 'amber')

  return (
    <div className={styles.screen}>
      <div className={styles.wallpapers} aria-hidden="true">
        {SECTIONS.map((section, index) => (
          <div
            key={section.id}
            className={styles.wallpaper}
            style={{
              '--wallpaper-step': index,
              backgroundImage: `url(/wallpapers/${section.scene}.jpg)`,
            } as CSSProperties}
          />
        ))}
      </div>
      <div className={styles.scrollViewport}>
        <div className={styles.headlines}>
          {SECTIONS.map((section, index) => (
            <section key={section.id} id={section.id} className={styles.headlineSection} data-section={index}>
              <SectionCopy index={index} stars={stars} />
            </section>
          ))}
        </div>
      </div>

      <div className={styles.closing} data-visible={active === GET_IT && !demo.open} aria-hidden>
        <DotMatrix size={176} playing={active === GET_IT} />
      </div>

      <div className={styles.popoverShell} data-open={demo.open}>
        <AppPopover demo={demo} />
      </div>

      <nav className={styles.menuBar}>
        <div className={styles.menus}>
          <span className={`${styles.menuItem} ${styles.menuApp}`}>WhatThePort</span>
          {SECTIONS.map((section, index) => (
            <button
              key={section.id}
              type="button"
              className={styles.menuItem}
              data-active={index === active}
              onClick={() => onNavigate(index)}
            >
              {section.menu}
            </button>
          ))}
        </div>
        <div className={styles.extras}>
          <button
            type="button"
            className={styles.statusItem}
            data-open={demo.open}
            onClick={() => demo.setOpen((open) => !open)}
            aria-label={demo.open ? 'Close WhatThePort' : 'Open WhatThePort'}
            aria-expanded={demo.open}
          >
            <DotGrid state={alert ? 'alert' : 'rest'} />
            {demo.running.length > 0 && (
              <span className={styles.mono} style={{ fontWeight: 500 }}>
                {demo.running.length}
              </span>
            )}
            <span className={styles.livesHere} data-visible={active === GET_IT && !demo.open} aria-hidden>
              It lives up here.
              <svg width="48" height="52" viewBox="0 0 48 52">
                <path d="M4 48 C 26 46, 38 34, 40 6" fill="none" stroke="#FFFFFFB3" strokeWidth="1.25" strokeLinecap="round" />
                <path d="M34.5 11 L40 5 L44.5 11.5" fill="none" stroke="#FFFFFFB3" strokeWidth="1.25" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          </button>
          <a className={styles.statusLink} href={GITHUB_URL} target="_blank" rel="noopener noreferrer" aria-label="GitHub">
            <GitHubIcon />
          </a>
          <WifiIcon />
          <BatteryIcon />
          <Clock />
        </div>
      </nav>
    </div>
  )
}

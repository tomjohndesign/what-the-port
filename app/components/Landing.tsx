'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { track } from '@vercel/analytics'
import styles from './landing.module.css'
import { AppPopover, useDemo } from './App'
import { SectionCopy } from './Copy'
import { DotMatrix } from './DotMatrix'
import { DotGrid } from './icons'
import { Screen } from './Screen'
import { DOWNLOAD_URL, GET_IT, GITHUB_URL, SECTIONS } from './sections'

// Scene geometry, in the 2560×1600 space the room photos and laptop were composed in (Paper boards 22–26).
const SCENE = { width: 2560, height: 1600 }
const SCREEN = { x: 624.2, y: 210.02, width: 1310.4, height: 819 }
const LID_TOP = 190

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max)
const easeInOutCubic = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2)

// Each section holds still for most of its scroll distance, then moves quickly to the next.
const HOLD = 0.3
const transition = (fraction: number) => easeInOutCubic(clamp((fraction - HOLD) / (1 - 2 * HOLD), 0, 1))

// Zoom so the laptop screen is comfortable to read while the room still frames it,
// then pan to keep the screen centred without exposing the scene's edges.
function camera(vw: number, vh: number) {
  const target = Math.min(vw * 0.66, vh * 0.72 * (SCREEN.width / SCREEN.height), 1500)
  const scale = Math.max(target / SCREEN.width, vw / SCENE.width, vh / SCENE.height)
  const x = clamp(vw / 2 - (SCREEN.x + SCREEN.width / 2) * scale, vw - SCENE.width * scale, 0)
  const y = clamp(vh * 0.49 - (SCREEN.y + SCREEN.height / 2) * scale, vh - SCENE.height * scale, 0)
  return { x, y, scale }
}

function useGitHubStars() {
  const [stars, setStars] = useState<number | null>(null)
  useEffect(() => {
    fetch('https://api.github.com/repos/tomjohndesign/what-the-port')
      .then((res) => res.json())
      .then((data) => {
        if (typeof data.stargazers_count === 'number') setStars(data.stargazers_count)
      })
      .catch(() => {})
  }, [])
  return stars
}

function Brand({ dark = false }: { dark?: boolean }) {
  return (
    <a className={styles.brand} data-dark={dark} href="#" onClick={() => window.scrollTo({ top: 0 })}>
      <DotGrid size={30} state="currentColor" />
      WhatThePort
    </a>
  )
}

function DeskStage({ stars }: { stars: number | null }) {
  const trackRef = useRef<HTMLDivElement>(null)
  const stageRef = useRef<HTMLDivElement>(null)
  const sceneRef = useRef<HTMLDivElement>(null)
  const roomRefs = useRef<(HTMLDivElement | null)[]>([])
  const [active, setActive] = useState(0)

  useEffect(() => {
    const track = trackRef.current
    const stage = stageRef.current
    const scene = sceneRef.current
    if (!track || !stage || !scene) return
    const sections = Array.from(track.querySelectorAll<HTMLElement>('[data-section]'))
    let frame = 0

    const update = () => {
      frame = 0
      const vh = window.innerHeight
      const progress = clamp(-track.getBoundingClientRect().top / vh, 0, SECTIONS.length - 1)
      const base = Math.floor(progress)
      const moving = transition(progress - base)
      const eased = base + moving

      // Headlines move on the eased curve. Each section gets its signed (--d) and absolute (--a)
      // distance from the middle; the CSS staggers, fades and blurs its parts from those.
      track.style.setProperty('--p', eased.toFixed(4))
      sections.forEach((section, index) => {
        const distance = eased - index
        section.style.setProperty('--d', distance.toFixed(4))
        section.style.setProperty('--a', Math.abs(distance).toFixed(4))
      })

      // Rooms only cross-fade; the scene itself never moves.
      roomRefs.current.forEach((room, index) => {
        if (!room) return
        room.style.opacity = (index <= base ? 1 : index === base + 1 ? moving : 0).toFixed(3)
      })

      setActive(Math.round(progress))
    }
    const layout = () => {
      const view = camera(window.innerWidth, window.innerHeight)
      scene.style.transform = `translate3d(${view.x}px, ${view.y}px, 0) scale(${view.scale})`
      stage.style.setProperty('--lid-top', `${view.y + LID_TOP * view.scale}px`)
      scene.dataset.ready = 'true'
      update()
    }
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(update)
    }

    layout()
    window.addEventListener('scroll', onScroll, { passive: true })
    window.addEventListener('resize', layout)
    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('scroll', onScroll)
      window.removeEventListener('resize', layout)
    }
  }, [])

  const navigate = useCallback((index: number) => {
    const track = trackRef.current
    if (!track) return
    const top = track.getBoundingClientRect().top + window.scrollY + index * window.innerHeight
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    window.scrollTo({ top, behavior: reduce ? 'auto' : 'smooth' })
  }, [])

  return (
    <div ref={trackRef} className={styles.track} style={{ height: `${SECTIONS.length * 100}vh` }}>
      <div ref={stageRef} className={styles.stage}>
        <div ref={sceneRef} className={styles.scene}>
          {SECTIONS.map((section, index) => (
            <div
              key={section.id}
              ref={(el) => {
                roomRefs.current[index] = el
              }}
              className={styles.room}
              style={{ backgroundImage: `url(/scenes/${section.scene}.jpg)`, opacity: index === 0 ? 1 : 0 }}
            />
          ))}
          <div className={styles.contactShadow} />
          <div className={styles.laptopBase} />
          <div className={styles.lid}>
            <div className={styles.screenMask}>
              <Screen active={active} stars={stars} onNavigate={navigate} />
            </div>
            <div className={styles.notch}>
              <span />
            </div>
            <div className={styles.glare} />
          </div>
        </div>
        <div className={styles.brandSlot}>
          <Brand dark={SECTIONS[active].logo === 'dark'} />
        </div>
      </div>
    </div>
  )
}

function StandalonePopover({ section, zoom }: { section: number; zoom: number }) {
  const demo = useDemo(section)
  return (
    <div style={{ zoom }}>
      <AppPopover demo={demo} />
    </div>
  )
}

// Below ~900px wide the laptop would be too small to read, so each section
// stacks its copy above a working popover, set on that section's wallpaper.
function StackedPage({ stars }: { stars: number | null }) {
  const cardRef = useRef<HTMLDivElement>(null)
  const [zoom, setZoom] = useState(1)

  useEffect(() => {
    const card = cardRef.current
    if (!card) return
    const observer = new ResizeObserver(([entry]) => setZoom(Math.min(1, (entry.contentRect.width - 32) / 400)))
    observer.observe(card)
    return () => observer.disconnect()
  }, [])

  return (
    <div className={styles.stacked}>
      <Brand />
      {SECTIONS.map((section, index) => (
        <section key={section.id} className={styles.stackedSection}>
          <SectionCopy index={index} stars={stars} />
          <div
            ref={index === 0 ? cardRef : undefined}
            className={styles.peek}
            style={{ backgroundImage: `linear-gradient(#05080c33, #05080c33), url(/wallpapers/${section.scene}.jpg)` }}
          >
            {index === GET_IT ? <DotMatrix size={160} /> : <StandalonePopover section={index} zoom={zoom} />}
          </div>
        </section>
      ))}
    </div>
  )
}

// Slides up over the page once you reach the bottom, without adding any height.
function Footer() {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    const update = () => {
      const bottom = window.scrollY + window.innerHeight
      setVisible(bottom >= document.documentElement.scrollHeight - 4)
    }
    update()
    window.addEventListener('scroll', update, { passive: true })
    window.addEventListener('resize', update)
    return () => {
      window.removeEventListener('scroll', update)
      window.removeEventListener('resize', update)
    }
  }, [])

  return (
    <footer className={styles.footer} data-visible={visible}>
      <div className={styles.footerInner}>
        <span className={styles.footerBrand}>
          <DotGrid size={22} />
          WhatThePort
        </span>
        <span className={styles.footerMeta}>Free and open source · Made by Tomjohn</span>
        <nav className={styles.footerLinks} aria-label="Footer">
          <a href={DOWNLOAD_URL} download onClick={() => track('Download', { location: 'footer' })}>
            Download <span aria-hidden="true">↗</span>
          </a>
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            GitHub <span aria-hidden="true">↗</span>
          </a>
          <a href="https://tomjohn.design" target="_blank" rel="noopener noreferrer">
            tomjohn.design <span aria-hidden="true">↗</span>
          </a>
        </nav>
      </div>
    </footer>
  )
}

export default function Landing() {
  const stars = useGitHubStars()
  return (
    <main className={styles.landing}>
      <div className={styles.desk}>
        <DeskStage stars={stars} />
      </div>
      <div className={styles.small}>
        <StackedPage stars={stars} />
      </div>
      <Footer />
    </main>
  )
}

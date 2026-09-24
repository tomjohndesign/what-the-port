import styles from './landing.module.css'
import {
  AppleIcon,
  ClaudeIcon,
  CodexIcon,
  Colon,
  type ColonState,
  ConductorIcon,
  GitHubIcon,
  VercelIcon,
} from './icons'
import { track } from '@vercel/analytics'
import { portColor } from './servers'
import { DOWNLOAD_URL, GITHUB_URL } from './sections'

// Marketing copy for each section. Shared by the laptop screen and the small-screen layout.

function PortLabel({ port, colon, label }: { port: string; colon: ColonState; label: string }) {
  return (
    <div className={styles.portLabel}>
      <Colon state={colon} color={portColor(port)} />
      <span className={styles.portLabelPort} style={{ color: portColor(port) }}>
        {port}
      </span>
      <span className={styles.portLabelName}>{label}</span>
    </div>
  )
}

export function Cta({ stars, location }: { stars: number | null; location: string }) {
  return (
    <div className={styles.cta}>
      <div className={styles.ctaButtons}>
        <a className={styles.download} href={DOWNLOAD_URL} download onClick={() => track('Download', { location })}>
          <AppleIcon />
          Download for macOS
        </a>
        <a className={styles.github} href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
          <GitHubIcon />
          Star on GitHub
          {stars !== null && <span className={styles.githubCount}>{stars}</span>}
        </a>
      </div>
      <p className={styles.ctaMeta}>Free and open source · macOS 14 or later · No account</p>
    </div>
  )
}

const TOOLS = [
  { name: 'Claude Code', detail: 'claude --resume', icon: <ClaudeIcon color="#F5F5F7" size={14} width={1.3} /> },
  { name: 'Codex', detail: 'codex resume', icon: <CodexIcon color="#F5F5F7" size={14} width={1.1} /> },
  { name: 'Conductor', detail: 'workspace name', icon: <ConductorIcon /> },
  { name: 'Vercel', detail: 'preview per branch', icon: <VercelIcon /> },
]

const FACTS = [
  { name: 'Native', detail: 'Swift, no Electron, no Dock icon.' },
  { name: 'Private', detail: 'Nothing leaves your Mac.' },
  { name: 'Shortcut', detail: '⌥⌘P', mono: true },
]

export function SectionCopy({ index, stars }: { index: number; stars: number | null }) {
  switch (index) {
    case 0:
      return (
        <div className={styles.copy}>
          <h1 className={styles.headline}>Every dev server on your Mac, in the menu bar.</h1>
          <p className={styles.body}>
            What it is, what branch it’s on, which agent started it, and what it’s costing you. Stop the ones you forgot
            about in one click.
          </p>
          <Cta stars={stars} location="hero" />
        </div>
      )
    case 1:
      return (
        <div className={styles.copy}>
          <PortLabel port="3000" colon="on" label="Sessions" />
          <h2 className={styles.headline}>Knows which agent started it.</h2>
          <p className={styles.body}>
            Servers launched by Claude Code, Codex or Conductor link back to the session that started them. Pick up the
            conversation, check the branch, or open the Vercel preview for the same commit.
          </p>
          <ul className={styles.list}>
            {TOOLS.map((tool) => (
              <li key={tool.name} className={styles.listRow}>
                <span className={styles.toolIcon}>{tool.icon}</span>
                <span className={styles.listName}>{tool.name}</span>
                <span className={styles.listDetail}>{tool.detail}</span>
              </li>
            ))}
          </ul>
        </div>
      )
    case 2:
      return (
        <div className={styles.copy}>
          <PortLabel port="6006" colon="amber" label="Leaks" />
          <h2 className={styles.headline}>Notices before your fans do.</h2>
          <p className={styles.body}>
            When a server passes 2 GB or grows 500 MB in ten minutes, the menu bar turns amber and you get one quiet
            notification. Crashed, hung and failed preview builds get flagged too.
          </p>
        </div>
      )
    case 3:
      return (
        <div className={styles.copy}>
          <PortLabel port="8000" colon="idle" label="Clean up" />
          <h2 className={styles.headline}>Stops the ones you forgot.</h2>
          <p className={styles.body}>
            Clean up selects servers from deleted worktrees or idle for hours. Tick the ones to go and WhatThePort stops
            each whole process tree. Postgres and Redis are protected by default.
          </p>
        </div>
      )
    default:
      return (
        <div className={styles.copy}>
          <h2 className={styles.headline}>Know what’s running.</h2>
          <p className={styles.body}>Two white dots when everything’s fine. You’ll know when it isn’t.</p>
          <Cta stars={stars} location="get-it" />
          <ul className={styles.list}>
            {FACTS.map((fact) => (
              <li key={fact.name} className={styles.listRow} style={{ height: 44 }}>
                <span className={styles.listName} style={{ flexGrow: 0, width: 120 }}>
                  {fact.name}
                </span>
                <span className={fact.mono ? styles.listDetail : styles.factDetail}>{fact.detail}</span>
              </li>
            ))}
          </ul>
        </div>
      )
  }
}

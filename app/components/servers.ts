import type { ColonState } from './icons'

// Sample data for the marketing demo. Keep presentation aligned with the native SwiftUI views.
// Memory values use binary MB, matching Theme.swift / Format.

export type Agent = 'claude' | 'codex'
export type CleanUpReason = 'deleted' | 'idle' | 'leaking'

export type Server = {
  port: string
  name: string
  branch: string
  status: ColonState
  memory: number // binary MB
  cpu: number // % of one core
  cpuNote: string
  uptime: string
  context: { agent?: Agent; text: string; tone?: 'amber' }
  session?: { agent: Agent; title: string; id: string }
  chart: 'steady' | 'leaking' | 'flat'
  spark: string
  processes: { command: string; memory: number }[]
  info: [label: string, value: string][]
  cleanUp?: { reason: CleanUpReason; note: string; suggested: boolean }
}

export const SERVERS: Server[] = [
  {
    port: '3000',
    name: 'what-the-port',
    branch: 'menubar-port-monitor',
    status: 'on',
    memory: 1240,
    cpu: 12,
    cpuNote: 'spikes on rebuild',
    uptime: 'up 3h 12m',
    context: { agent: 'claude', text: 'what the port · up 3h' },
    session: { agent: 'claude', title: 'Dot-grid menu bar icon', id: '68c8fda6' },
    chart: 'steady',
    spark: 'M0 13 L4 12 L8 12.5 L12 10 L16 11 L20 8 L24 9 L28 7 L32 8 L36 6 L40 6.5 L44 5',
    processes: [
      { command: 'node next dev', memory: 796 },
      { command: 'next-server', memory: 418 },
      { command: 'tailwindcss --watch', memory: 26 },
    ],
    info: [
      ['Folder', '~/conductor/workspaces/what-the-port/providence'],
      ['Framework', 'Next.js 14'],
      ['Command', 'npm run dev'],
      ['PID', '48213'],
      ['Started', 'Today 10:12 AM'],
      ['Workspace', 'providence'],
    ],
  },
  {
    port: '3001',
    name: 'tomjohn.design',
    branch: 'main',
    status: 'on',
    memory: 612,
    cpu: 2,
    cpuNote: 'quiet',
    uptime: 'up 1d 4h',
    context: { text: 'tomjohn.design · up 1d' },
    chart: 'steady',
    spark: 'M0 10 L4 10.5 L8 9.5 L12 10 L16 9 L20 10 L24 9.5 L28 10 L32 9 L36 9.5 L40 9 L44 9.5',
    processes: [
      { command: 'astro dev', memory: 571 },
      { command: 'esbuild', memory: 41 },
    ],
    info: [
      ['Folder', '~/Sites/tomjohn.design'],
      ['Framework', 'Astro 4'],
      ['Command', 'npm run dev -- --port 3001'],
      ['PID', '30877'],
      ['Started', 'Yesterday 9:02 AM'],
      ['Git', 'clean'],
    ],
  },
  {
    port: '5173',
    name: 'paper-plugins',
    branch: 'feat/export-svg',
    status: 'on',
    memory: 184,
    cpu: 0,
    cpuNote: 'idle since 8:31',
    uptime: 'idle 5h',
    context: { agent: 'codex', text: 'paper plugins · idle 5h' },
    session: { agent: 'codex', title: 'SVG export for frames', id: 'c7e20b91' },
    chart: 'flat',
    spark: 'M0 13 L4 13 L8 12.5 L12 13 L16 13 L20 13 L24 12.5 L28 13 L32 13 L36 13 L40 13 L44 13',
    processes: [
      { command: 'vite', memory: 142 },
      { command: 'esbuild', memory: 42 },
    ],
    info: [
      ['Folder', '~/conductor/workspaces/paper-plugins/lisbon'],
      ['Framework', 'Vite 5'],
      ['Command', 'pnpm dev'],
      ['PID', '51092'],
      ['Started', 'Today 7:58 AM'],
      ['Workspace', 'lisbon'],
    ],
    cleanUp: { reason: 'idle', note: 'Idle 5h · no connections', suggested: true },
  },
  {
    port: '6006',
    name: 'design-system',
    branch: 'tokens-v2',
    status: 'amber',
    memory: 2810,
    cpu: 34,
    cpuNote: 'climbing since 1:14',
    uptime: 'up 2h 40m',
    context: { text: '+1.1 GB in 10 min', tone: 'amber' },
    session: { agent: 'claude', title: 'Tokens v2 migration', id: 'a3f19c07' },
    chart: 'leaking',
    spark: 'M0 16 L4 15.5 L8 14.5 L12 14 L16 12.5 L20 12 L24 10 L28 9 L32 7 L36 5.5 L40 4 L44 2',
    processes: [
      { command: 'storybook dev -p 6006', memory: 2210 },
      { command: 'webpack', memory: 548 },
      { command: 'node', memory: 52 },
    ],
    info: [
      ['Folder', '~/Code/design-system'],
      ['Framework', 'Storybook 8'],
      ['Command', 'npm run storybook'],
      ['PID', '61540'],
      ['Started', 'Today 10:44 AM'],
      ['Git', '3 changed files'],
    ],
    cleanUp: { reason: 'leaking', note: 'Leaking · +1.1 GB in 10 min', suggested: false },
  },
  {
    port: '8000',
    name: 'api',
    branch: 'fix/auth-timeout',
    status: 'idle',
    memory: 96,
    cpu: 0,
    cpuNote: 'no requests in 2d',
    uptime: 'idle 2d',
    context: { text: 'Worktree deleted · idle 2d' },
    chart: 'flat',
    spark: 'M0 12 L44 12',
    processes: [{ command: 'uvicorn main:app', memory: 96 }],
    info: [
      ['Folder', '~/Code/api-fix-auth (deleted)'],
      ['Framework', 'FastAPI'],
      ['Command', 'uvicorn main:app --port 8000'],
      ['PID', '22718'],
      ['Started', 'Mon 3:40 PM'],
      ['Worktree', 'deleted'],
    ],
    cleanUp: { reason: 'deleted', note: 'Worktree deleted', suggested: true },
  },
]

// Stable identities: stopping a server must not recolor the remaining ports.
const PORT_COLORS = ['#6EC7ED', '#B599F0', '#EB9CD4', '#7D9CF2', '#7DDBE0', '#D9A3F2', '#ABC2E0']
export const portColor = (port: string) =>
  PORT_COLORS[
    Math.max(
      0,
      SERVERS.findIndex((s) => s.port === port),
    ) % PORT_COLORS.length
  ]

export const SYSTEM_MEMORY = 16 * 1024
export const OTHER_APPS = [
  { id: 'chrome', name: 'Google Chrome', memory: 1536 },
  { id: 'conductor', name: 'Conductor', memory: 768 },
  { id: 'rest', name: 'Everything else', memory: 4864 },
]
export const OTHER_MEMORY = OTHER_APPS.reduce((sum, app) => sum + app.memory, 0)

export function formatTotal(mb: number) {
  return mb >= 1024 ? `${Number((mb / 1024).toFixed(1))} GB` : `${Math.round(mb)} MB`
}

export function formatMemory(mb: number) {
  return mb >= 1024 ? `${(mb / 1024).toFixed(2)} GB` : `${Math.round(mb)} MB`
}

// Deterministic ten-minute histories for both synchronized detail charts.
const WOBBLE = [
  40, 39.2, 38.2, 39.3, 39.6, 40.2, 40.1, 38.6, 38, 37.2, 38.1, 38.8, 38.8, 38, 37.7, 36.5, 35.7, 35.8, 37, 37.6, 36.5,
  36.5, 34.5, 34.8, 35.5, 36.3, 36.4, 35.4, 35, 33.6, 34.3, 37.3, 37.9, 36.5, 35, 33.7, 32.2, 32.1, 32.8, 33.2, 33.7,
  33.4, 31.8, 30.9, 31.1, 31.2, 32, 32, 31.6, 31, 29.3, 30, 30.1, 30.5, 31.5, 30.6, 30, 28.3, 28, 29.1,
]

const LEAK =
  'M0 33.4 L11.3 33 L22.6 33.8 L33.9 32.6 L45.2 32.2 L56.6 32.6 L67.9 30.8 L79.2 31.2 L90.5 29.4 L101.8 29.8 L113.1 27.9 L124.4 26.7 L135.7 27.1 L147 24.8 L158.3 23.7 L169.7 24 L181 21.4 L192.3 20 L203.6 19.2 L214.9 17 L226.2 15.2 L237.5 13.8 L248.8 11.9 L260.1 10.4 L271.4 9.3 L282.8 8.1 L294.1 7 L305.4 6.2 L316.7 5.5 L327 4.8'

export function memoryChart(server: Server) {
  const raw =
    server.chart === 'leaking'
      ? Array.from(LEAK.matchAll(/[ML]([\d.]+) ([\d.]+)/g), (match) => Number(match[2]))
      : WOBBLE
  const last = raw[raw.length - 1]
  const values = raw.map(
    (y) =>
      server.memory -
      (y - last) * (server.chart === 'leaking' ? 1126 / (raw[0] - last) : server.chart === 'flat' ? 0.1 : 8),
  )
  const top = Math.max(2048, ...values.map((mb) => mb * 1.1))
  const points = values.map((mb, i) => ({ x: (i * 328) / (values.length - 1), y: 56 * (1 - mb / top), memory: mb }))
  return {
    points,
    line: `M${points.map((p) => `${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' L')}`,
    end: points[points.length - 1].y,
    limit: 56 * (1 - 2048 / top),
  }
}

// CPU history, scaled so the final sample matches the current reading.
const CPU = [
  4.3, 2.1, 3.6, 3.2, 3.1, 2.6, 4.1, 4.5, 2.7, 3.4, 1.1, 3.6, 16, 17.3, 4.1, 2, 2.4, 3.5, 0.9, 2.6, 1.5, 1.3, 1.1, 3.9,
  1.3, 1.8, 2.4, 4.3, 1.2, 2.6, 3, 4.3, 4.1, 4.2, 1.9, 2.5, 2.2, 4.3, 4.6, 1.4, 1.5, 14.3, 14.4, 15.3, 3.1, 1.9, 0.9,
  2.5, 2.3, 3.1, 4.6, 3.5, 2.9, 3.3, 3.5, 1.1, 4.4, 3.9, 4.3, 4,
]

export function cpuBars(server: Server) {
  return CPU.map((h) => Math.min(100, (h / CPU[CPU.length - 1]) * server.cpu))
}

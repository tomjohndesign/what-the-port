'use client'

import { type ReactNode, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import styles from './landing.module.css'
import {
  AMBER,
  BackIcon,
  BranchIcon,
  Chevron,
  ClaudeIcon,
  CodexIcon,
  Colon,
  OpenIcon,
  VercelIcon,
} from './icons'
import { GET_IT } from './sections'
import { type Agent, type Server, SERVERS, cpuBars, formatMemory, memoryChart } from './servers'

// A working copy of the WhatThePort popover. Scrolling picks the view for each
// section; clicking around works like the real app until the next section.

type View = { name: 'list' } | { name: 'detail'; port: string } | { name: 'cleanUp' }

const SECTION_VIEWS: View[] = [
  { name: 'list' },
  { name: 'detail', port: '3000' },
  { name: 'detail', port: '6006' },
  { name: 'cleanUp' },
  { name: 'list' },
]

const suggested = (running: string[]) =>
  SERVERS.filter((s) => s.cleanUp?.suggested && running.includes(s.port)).map((s) => s.port)

export function useDemo(section: number) {
  const [running, setRunning] = useState(() => SERVERS.map((s) => s.port))
  const [view, setView] = useState<View>(SECTION_VIEWS[section])
  const [direction, setDirection] = useState(1)
  const [open, setOpen] = useState(section !== GET_IT)
  const [selected, setSelected] = useState(() => suggested(SERVERS.map((s) => s.port)))
  const previous = useRef(section)

  useEffect(() => {
    if (previous.current === section) return
    setDirection(section > previous.current ? 1 : -1)
    previous.current = section
    setView(SECTION_VIEWS[section])
    setOpen(section !== GET_IT)
    setSelected((current) => (current.length ? current : suggested(running)))
    // `running` intentionally omitted: stopping a server shouldn't reset the view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [section])

  const go = useCallback((next: View, dir: number) => {
    setDirection(dir)
    setView(next)
  }, [])

  const stop = useCallback((ports: string[]) => {
    setRunning((current) => {
      const next = current.filter((port) => !ports.includes(port))
      setSelected((sel) => sel.filter((port) => next.includes(port)))
      return next
    })
    setView((current) => {
      if (current.name === 'detail' && ports.includes(current.port)) {
        setDirection(-1)
        return { name: 'list' }
      }
      return current
    })
  }, [])

  const restartAll = useCallback(() => {
    const all = SERVERS.map((s) => s.port)
    setRunning(all)
    setSelected(suggested(all))
  }, [])

  const toggleSelected = useCallback((port: string) => {
    setSelected((current) => (current.includes(port) ? current.filter((p) => p !== port) : [...current, port]))
  }, [])

  // A detail view for a server that's been stopped falls back to the list.
  const shown: View = view.name === 'detail' && !running.includes(view.port) ? { name: 'list' } : view

  return {
    running: SERVERS.filter((s) => running.includes(s.port)),
    view: shown,
    direction,
    open,
    setOpen,
    selected,
    toggleSelected,
    go,
    stop,
    restartAll,
  }
}

export type Demo = ReturnType<typeof useDemo>

// Keeps the popover's height animating between views, the way a macOS popover resizes.
function Frame({ children, viewKey }: { children: ReactNode; viewKey: string }) {
  const innerRef = useRef<HTMLDivElement>(null)
  const [height, setHeight] = useState<number>()

  useLayoutEffect(() => {
    const inner = innerRef.current
    if (!inner) return
    const measure = () => setHeight(inner.offsetHeight)
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(inner)
    return () => observer.disconnect()
  }, [viewKey])

  return (
    <div className={styles.popover} style={{ height }}>
      <div ref={innerRef}>{children}</div>
    </div>
  )
}

export function AppPopover({ demo }: { demo: Demo }) {
  const { view, direction } = demo
  const key = view.name === 'detail' ? `detail-${view.port}` : demo.running.length ? view.name : 'empty'

  let content: ReactNode
  if (!demo.running.length) content = <EmptyView demo={demo} />
  else if (view.name === 'detail') content = <DetailView demo={demo} server={SERVERS.find((s) => s.port === view.port)!} />
  else if (view.name === 'cleanUp') content = <CleanUpView demo={demo} />
  else content = <ListView demo={demo} />

  return (
    <Frame viewKey={key}>
      <div key={key} className={styles.view} style={{ ['--dir' as string]: direction }}>
        {content}
      </div>
    </Frame>
  )
}

function Header({ title, onBack }: { title: string; onBack?: () => void }) {
  return (
    <div className={styles.popTitleRow}>
      <span className={styles.popTitle}>{title}</span>
      {onBack && (
        <button type="button" className={styles.popBack} onClick={onBack} aria-label="Back">
          <BackIcon />
        </button>
      )}
    </div>
  )
}

function AgentIcon({ agent }: { agent?: Agent }) {
  if (agent === 'claude') return <ClaudeIcon />
  if (agent === 'codex') return <CodexIcon />
  return null
}

// Brief confirmation on buttons that would open something outside the demo.
function useFlash() {
  const [flash, setFlash] = useState<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout>>()
  useEffect(() => () => clearTimeout(timer.current), [])
  const trigger = useCallback((id: string) => {
    setFlash(id)
    clearTimeout(timer.current)
    timer.current = setTimeout(() => setFlash(null), 1400)
  }, [])
  return [flash, trigger] as const
}

function ListView({ demo }: { demo: Demo }) {
  const [flash, trigger] = useFlash()
  const total = demo.running.reduce((sum, s) => sum + s.memory, 0)
  const cpu = Math.round(demo.running.reduce((sum, s) => sum + s.cpu, 0) * 0.375)
  const cleanUpCount = demo.running.filter((s) => s.cleanUp?.suggested).length

  return (
    <>
      <div className={styles.popHead}>
        <Header title="Servers" />
        <div className={styles.popDisplayStack}>
          <div className={styles.popDisplay}>
            <span className={styles.popBig}>{(total / 1000).toFixed(1)}</span>
            <span className={styles.popUnit}>GB</span>
            <span className={`${styles.mono} ${styles.t3}`} style={{ marginLeft: 'auto' }}>
              CPU {cpu}%
            </span>
          </div>
          <div className={styles.shareBar}>
            {demo.running.map((s, i) => (
              <span
                key={s.port}
                style={{
                  flexGrow: s.memory,
                  backgroundColor: s.status === 'amber' ? AMBER : ['#F5F5F7D1', '#F5F5F78C', '#F5F5F766', '#F5F5F74D'][i % 4],
                }}
              />
            ))}
          </div>
        </div>
      </div>

      <div className={`${styles.popSection} ${styles.rowList}`}>
        {demo.running.map((s) => (
          <div
            key={s.port}
            role="button"
            tabIndex={0}
            className={styles.serverRow}
            data-interactive
            data-dim={s.status === 'idle'}
            onClick={() => demo.go({ name: 'detail', port: s.port }, 1)}
            onKeyDown={(e) => e.key === 'Enter' && demo.go({ name: 'detail', port: s.port }, 1)}
          >
            <Colon state={s.status} />
            <span className={styles.rowPort}>{s.port}</span>
            <span className={styles.rowMain}>
              <span className={styles.rowTop}>
                <span className={styles.rowName}>{s.name}</span>
                <span className={styles.rowBranch}>
                  <BranchIcon />
                  <span className={styles.ellipsis}>{s.branch}</span>
                </span>
              </span>
              <span
                className={styles.rowSub}
                style={{ color: s.context.tone === 'amber' ? AMBER : s.context.agent ? '#EBEBF599' : '#EBEBF580' }}
              >
                <AgentIcon agent={s.context.agent} />
                <span className={styles.ellipsis}>{flash === s.port ? `Opened localhost:${s.port}` : s.context.text}</span>
              </span>
            </span>
            <svg className={styles.rowSpark} width="44" height="18" viewBox="0 0 44 18" aria-hidden>
              <path
                d={s.spark}
                fill="none"
                stroke={s.status === 'amber' ? AMBER : `rgb(245 245 247 / ${s.status === 'idle' ? 50 : 70}%)`}
                strokeWidth={s.status === 'amber' ? 1.5 : 1.25}
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeDasharray={s.status === 'idle' ? '2 3' : undefined}
              />
            </svg>
            <span className={styles.rowActions}>
              <button
                type="button"
                className={styles.rowAction}
                aria-label={`Open localhost:${s.port}`}
                onClick={(e) => {
                  e.stopPropagation()
                  trigger(s.port)
                }}
              >
                <OpenIcon />
              </button>
              <button
                type="button"
                className={styles.rowAction}
                aria-label={`Stop ${s.name}`}
                onClick={(e) => {
                  e.stopPropagation()
                  demo.stop([s.port])
                }}
              >
                <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
                  <rect x="2.5" y="2.5" width="7" height="7" rx="1.5" fill="rgb(245 245 247 / 80%)" />
                </svg>
              </button>
            </span>
            <span className={styles.rowMemory} style={{ color: s.status === 'amber' ? AMBER : undefined }}>
              {formatMemory(s.memory)}
            </span>
          </div>
        ))}
      </div>

      <div className={`${styles.popSection} ${styles.popFooter}`}>
        <button type="button" className={styles.chip} onClick={() => demo.go({ name: 'cleanUp' }, 1)}>
          <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
            <path d="M8.5 1.5 6 7M3 8.5h7l.8 4H2.2L3 8.5Z" fill="none" stroke="#F5F5F7" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M5 10.5v2M7.5 10.5v2" fill="none" stroke="#F5F5F7" strokeWidth="1.1" strokeLinecap="round" />
          </svg>
          <span className={styles.popTitle}>Clean up</span>
          {cleanUpCount > 0 && <span className={styles.chipCount}>{cleanUpCount}</span>}
        </button>
        <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden>
          <path
            d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"
            fill="none"
            stroke="rgb(235 235 245 / 70%)"
            strokeWidth="1.9"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <circle cx="12" cy="12" r="3" fill="none" stroke="rgb(235 235 245 / 70%)" strokeWidth="1.9" />
        </svg>
      </div>
    </>
  )
}

function DetailView({ demo, server }: { demo: Demo; server: Server }) {
  const [moreInfo, setMoreInfo] = useState(false)
  const [processesOpen, setProcessesOpen] = useState(false)
  const [restarting, setRestarting] = useState(false)
  const [restarted, setRestarted] = useState(false)
  const [flash, trigger] = useFlash()
  const memory = memoryChart(server)
  const bars = cpuBars(server)
  const leaking = server.chart === 'leaking'

  useEffect(() => {
    if (!restarting) return
    const timer = setTimeout(() => {
      setRestarting(false)
      setRestarted(true)
    }, 900)
    return () => clearTimeout(timer)
  }, [restarting])

  const shownInfo: [string, ReactNode][] = server.session
    ? [
        [
          'Session',
          <span key="session" className={styles.infoValue}>
            <AgentIcon agent={server.session.agent} />
            <span className={`${styles.ellipsis} ${styles.t1}`}>{server.session.title}</span>
            <span className={`${styles.mono} ${styles.t3}`}>{server.session.id}</span>
            <span style={{ flexGrow: 1 }} />
            <OpenIcon color="rgb(235 235 245 / 60%)" />
          </span>,
        ],
        ['Branch', server.branch],
      ]
    : [
        ['Branch', server.branch],
        ['Folder', server.info[0][1]],
      ]
  const hiddenInfo = server.info.filter(([label]) => !(label === 'Folder' && !server.session))

  return (
    <>
      <div className={styles.popHead}>
        <Header title={server.name} onBack={() => demo.go({ name: 'list' }, -1)} />
        <div className={styles.popDisplay} style={{ justifyContent: 'space-between' }}>
          <span className={styles.popDisplay}>
            <Colon state={server.status} dot={6} gap={6} />
            <span className={styles.popBig}>{server.port}</span>
          </span>
          <span className={styles.popDisplay} style={{ gap: 10 }}>
            <span className={`${styles.mono} ${styles.t3}`}>
              {restarting ? 'restarting…' : restarted ? 'up just now' : server.uptime}
            </span>
            <span className={styles.popDisplay}>
              <button
                type="button"
                className={styles.control}
                aria-label="Restart"
                data-spinning={restarting}
                onClick={() => setRestarting(true)}
              >
                <svg width="13" height="13" viewBox="0 0 14 14" aria-hidden>
                  <path d="M11.5 7a4.5 4.5 0 1 1-1.3-3.2" fill="none" stroke="#F5F5F7" strokeWidth="1.4" strokeLinecap="round" />
                  <path d="M10.6 1.6v2.6H8" fill="none" stroke="#F5F5F7" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </button>
              <button
                type="button"
                className={`${styles.control} ${styles.controlStop}`}
                aria-label="Stop"
                onClick={() => demo.stop([server.port])}
              >
                <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
                  <rect x="2" y="2" width="8" height="8" rx="1.8" fill="#FF6961" />
                </svg>
              </button>
            </span>
          </span>
        </div>
      </div>

      <div className={`${styles.popSection} ${styles.infoList}`}>
        {shownInfo.map(([label, value]) => (
          <div key={label} className={styles.infoRow}>
            <span className={styles.infoLabel}>{label}</span>
            {typeof value === 'string' ? <span className={`${styles.ellipsis} ${styles.t1}`}>{value}</span> : value}
          </div>
        ))}
        <div className={styles.collapsible} data-open={moreInfo}>
          <div>
            {hiddenInfo.map(([label, value]) => (
              <div key={label} className={styles.infoRow}>
                <span className={styles.infoLabel}>{label}</span>
                <span className={`${styles.ellipsis} ${label === 'PID' || label === 'Command' ? styles.mono : ''} ${styles.t1}`}>
                  {value}
                </span>
              </div>
            ))}
          </div>
        </div>
        <div className={styles.infoRow}>
          <span className={styles.infoLabel} />
          <button type="button" className={styles.infoMore} onClick={() => setMoreInfo((v) => !v)} data-open={moreInfo}>
            {moreInfo ? 'Less' : `${hiddenInfo.length} more`} <Chevron direction="down" />
          </button>
        </div>
      </div>

      <div className={`${styles.popSection} ${styles.chart}`}>
        <div className={styles.chartHead}>
          <span className={styles.chartTitle}>
            <span className={styles.t2} style={{ fontWeight: 500 }}>
              Memory
            </span>
            <span className={styles.mono} style={{ fontWeight: 500, color: leaking ? AMBER : '#F5F5F7' }}>
              {formatMemory(server.memory)}
            </span>
          </span>
          <span className={`${styles.mono} ${styles.caption} ${styles.t3}`}>10 min</span>
        </div>
        <div className={styles.plot}>
          <span className={styles.axis} style={{ height: 76 }}>
            <span style={{ color: memory.topAmber ? '#FFB224D9' : undefined, marginTop: -6 }}>{memory.top}</span>
            <span style={{ marginBottom: -6 }}>0</span>
          </span>
          <svg width="328" height="76" viewBox="0 0 328 76" aria-hidden style={{ flexShrink: 0 }}>
            <path d="M0.5 0 V76" fill="none" stroke="rgb(255 255 255 / 14%)" />
            <path d="M0 75.5 H328" fill="none" stroke="rgb(255 255 255 / 14%)" />
            <path d={`M0 ${memory.limit} H328`} fill="none" stroke="rgb(255 178 36 / 55%)" strokeDasharray="3 3" />
            <path
              className={styles.chartLine}
              d={memory.line}
              fill="none"
              stroke={leaking ? AMBER : 'rgb(245 245 247 / 90%)'}
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              pathLength={1}
            />
            <circle className={styles.chartDot} cx="327" cy={memory.end} r="3" fill={leaking ? AMBER : '#F5F5F7'} />
          </svg>
        </div>
      </div>

      <div className={styles.chart} style={{ paddingTop: 0 }}>
        <div className={styles.chartHead}>
          <span className={styles.chartTitle}>
            <span className={styles.t2} style={{ fontWeight: 500 }}>
              CPU
            </span>
            <span className={styles.mono} style={{ fontWeight: 500 }}>
              {server.cpu}%
            </span>
          </span>
          <span className={`${styles.caption} ${styles.t3}`}>{server.cpuNote}</span>
        </div>
        <div className={styles.plot}>
          <span className={styles.axis} style={{ height: 28 }}>
            <span style={{ marginTop: -6 }}>100%</span>
            <span style={{ marginBottom: -6 }}>0</span>
          </span>
          <svg width="328" height="28" viewBox="0 0 328 28" aria-hidden style={{ flexShrink: 0 }}>
            <path d="M0.5 0 V28" fill="none" stroke="rgb(255 255 255 / 14%)" />
            {bars.map((h, i) => (
              <rect
                key={i}
                className={styles.cpuBar}
                style={{ animationDelay: `${i * 6}ms` }}
                x={0.5 + i * 5.4627}
                y={28 - h}
                width="4"
                height={h}
                rx="1"
                fill={i === bars.length - 1 ? 'rgb(245 245 247 / 80%)' : 'rgb(245 245 247 / 32%)'}
              />
            ))}
          </svg>
        </div>
      </div>

      <div className={styles.popSection}>
        <button
          type="button"
          className={styles.processes}
          onClick={() => setProcessesOpen((v) => !v)}
          data-open={processesOpen}
        >
          <span className={styles.popDisplay} style={{ gap: 4 }}>
            <span className={styles.t2}>Processes</span>
            <span className={styles.processesChevron}>
              <Chevron direction="right" />
            </span>
          </span>
          <span className={styles.popDisplay} style={{ gap: 8 }}>
            <span className={`${styles.mono} ${styles.t3}`}>{server.processes.length} ·</span>
            <span className={`${styles.mono} ${styles.t2}`}>{formatMemory(server.memory)}</span>
          </span>
        </button>
        <div className={styles.collapsible} data-open={processesOpen}>
          <div>
            <div className={styles.processList}>
              {server.processes.map((p) => (
                <div key={p.command} className={styles.processRow}>
                  <span className={`${styles.mono} ${styles.ellipsis} ${styles.t1}`}>{p.command}</span>
                  <span className={`${styles.mono} ${styles.t2}`}>{formatMemory(p.memory)}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className={`${styles.popSection} ${styles.actions}`}>
        <button type="button" className={styles.primaryAction} onClick={() => trigger('open')}>
          {flash === 'open' ? 'Opened in your browser' : `Open localhost:${server.port}`}
        </button>
        <button type="button" className={styles.secondaryAction} onClick={() => trigger('preview')}>
          <VercelIcon fill="rgb(235 235 245 / 75%)" width={11} height={10} />
          {flash === 'preview' ? 'Opened' : 'Preview'}
        </button>
        <button type="button" className={styles.moreAction} aria-label="More">
          <span />
          <span />
          <span />
        </button>
      </div>
    </>
  )
}

const REASON_ICONS = {
  deleted: (
    <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
      <path d="M1.5 3.5c0-.6.4-1 1-1h2.3l1 1.2h3.7c.6 0 1 .4 1 1V9c0 .6-.4 1-1 1h-7c-.6 0-1-.4-1-1V3.5Z" fill="none" stroke="rgb(235 235 245 / 60%)" strokeWidth="1.1" />
      <path d="M4.5 6.2h3" fill="none" stroke="rgb(235 235 245 / 60%)" strokeWidth="1.1" strokeLinecap="round" />
    </svg>
  ),
  idle: (
    <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
      <circle cx="6" cy="6" r="4.5" fill="none" stroke="rgb(235 235 245 / 60%)" strokeWidth="1.1" />
      <path d="M6 3.6V6l1.6 1" fill="none" stroke="rgb(235 235 245 / 60%)" strokeWidth="1.1" strokeLinecap="round" />
    </svg>
  ),
  leaking: (
    <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
      <path d="M1.5 9 4.5 6l2 2 4-4.5M7.5 3.5h3v3" fill="none" stroke={AMBER} strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ),
}

function CleanUpView({ demo }: { demo: Demo }) {
  const order = ['deleted', 'idle', 'leaking']
  const candidates = demo.running
    .filter((s) => s.cleanUp)
    .sort((a, b) => order.indexOf(a.cleanUp!.reason) - order.indexOf(b.cleanUp!.reason))
  const chosen = candidates.filter((s) => demo.selected.includes(s.port))
  const freed = chosen.reduce((sum, s) => sum + s.memory, 0)
  const count = chosen.length
  const plural = count === 1 ? 'server' : 'servers'
  const [value, unit] = formatMemory(freed).split(' ')

  return (
    <>
      <div className={styles.popHead}>
        <Header title="Clean up" onBack={() => demo.go({ name: 'list' }, -1)} />
        <div className={styles.popDisplayStack}>
          <div className={styles.popDisplay}>
            <span className={styles.popBig}>{count ? `~${value}` : '0'}</span>
            <span className={styles.popUnit}>{count ? unit : 'MB'}</span>
          </div>
          <span className={styles.t2}>
            {candidates.length
              ? `can be freed by stopping ${count} ${plural}`
              : 'Nothing to clean up. Every server is earning its keep.'}
          </span>
        </div>
      </div>

      {candidates.length > 0 && (
        <div className={`${styles.popSection} ${styles.rowList}`}>
          {candidates.map((s) => {
            const checked = demo.selected.includes(s.port)
            const amber = s.cleanUp!.reason === 'leaking'
            return (
              <button
                key={s.port}
                type="button"
                className={styles.serverRow}
                data-interactive
                style={{ gap: 12 }}
                onClick={() => demo.toggleSelected(s.port)}
                aria-pressed={checked}
              >
                <span className={styles.checkbox} data-checked={checked}>
                  <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden>
                    <path d="M2 5.2 4.1 7.3 8 2.8" fill="none" stroke="#0B0D12" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </span>
                <span className={styles.popDisplay} style={{ gap: 0, width: 52, flexShrink: 0 }}>
                  <Colon state={s.status} />
                  <span className={styles.rowPort} style={{ width: 'auto' }}>
                    {s.port}
                  </span>
                </span>
                <span className={styles.rowMain} style={{ gap: 2, paddingRight: 0 }}>
                  <span className={styles.rowName}>{s.name}</span>
                  <span className={styles.rowSub} style={{ color: amber ? AMBER : '#EBEBF599' }}>
                    {REASON_ICONS[s.cleanUp!.reason]}
                    {s.cleanUp!.note}
                  </span>
                </span>
                <span className={styles.rowMemory} style={{ width: 60, color: amber ? AMBER : undefined }}>
                  {formatMemory(s.memory)}
                </span>
              </button>
            )
          })}
        </div>
      )}

      <div className={`${styles.popSection} ${styles.cleanFooter}`}>
        <span className={styles.rowSub} style={{ color: '#EBEBF573', gap: 6, paddingInline: 4 }}>
          <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
            <rect x="2.5" y="5.2" width="7" height="5" rx="1.3" fill="none" stroke="rgb(235 235 245 / 45%)" strokeWidth="1.1" />
            <path d="M4 5.2V3.8a2 2 0 0 1 4 0v1.4" fill="none" stroke="rgb(235 235 245 / 45%)" strokeWidth="1.1" />
          </svg>
          postgres :5432 and redis :6379 are protected
        </span>
        <span className={styles.actions} style={{ padding: 0 }}>
          <button type="button" className={styles.secondaryAction} style={{ paddingInline: 14, fontWeight: 500 }} onClick={() => demo.go({ name: 'list' }, -1)}>
            Cancel
          </button>
          <button
            type="button"
            className={`${styles.primaryAction} ${styles.destructive}`}
            disabled={!count}
            onClick={() => {
              demo.stop(chosen.map((s) => s.port))
              demo.go({ name: 'list' }, -1)
            }}
          >
            {count ? `Stop ${count} ${plural} · free ${formatMemory(freed)}` : 'Select servers to stop'}
          </button>
        </span>
      </div>
    </>
  )
}

function EmptyView({ demo }: { demo: Demo }) {
  return (
    <>
      <div className={styles.popHead}>
        <Header title="Servers" />
        <div className={styles.popDisplayStack}>
          <div className={styles.popDisplay}>
            <span className={styles.popBig}>0</span>
            <span className={styles.popUnit}>GB</span>
          </div>
          <span className={styles.t2}>Nothing is listening. Every port is free.</span>
        </div>
      </div>
      <div className={`${styles.popSection} ${styles.actions}`}>
        <button type="button" className={styles.primaryAction} onClick={demo.restartAll}>
          Start the demo servers again
        </button>
      </div>
    </>
  )
}

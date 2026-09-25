'use client'

import { type ReactNode, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import styles from './landing.module.css'
import { AMBER, BackIcon, Chevron, ClaudeIcon, CodexIcon, Colon, DotGrid, OpenIcon, VercelIcon } from './icons'
import { GET_IT, TERMINAL } from './sections'
import {
  type Agent,
  type Server,
  SERVERS,
  OTHER_APPS,
  OTHER_MEMORY,
  SYSTEM_MEMORY,
  cpuBars,
  formatMemory,
  formatTotal,
  memoryChart,
  portColor,
} from './servers'

// A working copy of the WhatThePort popover. Scrolling picks the view for each
// section; clicking around works like the real app until the next section.

type View = { name: 'list' } | { name: 'detail'; port: string } | { name: 'cleanUp' }

const SECTION_VIEWS: View[] = [
  { name: 'list' },
  { name: 'detail', port: '3000' },
  { name: 'detail', port: '6006' },
  { name: 'cleanUp' },
  { name: 'list' },
  { name: 'list' },
]

// The Terminal section shows `wtp` instead, and the last section the dot matrix.
const opensPopover = (section: number) => section !== GET_IT && section !== TERMINAL

const suggested = (running: string[]) =>
  SERVERS.filter((s) => s.cleanUp?.suggested && running.includes(s.port)).map((s) => s.port)

export function useDemo(section: number) {
  const [running, setRunning] = useState(() => SERVERS.map((s) => s.port))
  const [view, setView] = useState<View>(SECTION_VIEWS[section])
  const [direction, setDirection] = useState(1)
  const [open, setOpen] = useState(opensPopover(section))
  const [selected, setSelected] = useState(() => suggested(SERVERS.map((s) => s.port)))
  const previous = useRef(section)

  useEffect(() => {
    if (previous.current === section) return
    setDirection(section > previous.current ? 1 : -1)
    previous.current = section
    setView(SECTION_VIEWS[section])
    setOpen(opensPopover(section))
    setSelected(suggested(running))
    // `running` intentionally omitted: stopping a server shouldn't reset the view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [section])

  const go = useCallback(
    (next: View, dir: number) => {
      setDirection(dir)
      if (next.name === 'cleanUp') setSelected(suggested(running))
      setView(next)
    },
    [running],
  )

  const stop = useCallback((ports: string[]) => {
    setRunning((current) => current.filter((port) => !ports.includes(port)))
    setSelected((current) => current.filter((port) => !ports.includes(port)))
    setDirection(-1)
    setView((current) => {
      if (current.name === 'detail' && ports.includes(current.port)) {
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
  const key =
    view.name === 'detail'
      ? `detail-${view.port}`
      : demo.running.length
        ? view.name === 'cleanUp'
          ? 'list'
          : view.name
        : 'empty'

  let content: ReactNode
  if (view.name === 'detail') content = <DetailView demo={demo} server={SERVERS.find((s) => s.port === view.port)!} />
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
  const cleaning = demo.view.name === 'cleanUp'
  const [focus, setFocus] = useState<string | null>(null)
  const [hoveredRow, setHoveredRow] = useState<string | null>(null)
  const [cpuAll, setCpuAll] = useState(false)
  const total = demo.running.reduce((sum, s) => sum + s.memory, 0)
  const cpu = Math.round(demo.running.reduce((sum, s) => sum + s.cpu, 0) / 8)
  const cleanUpCount = demo.running.filter((s) => s.cleanUp?.suggested).length
  const chosen = demo.running.filter((s) => demo.selected.includes(s.port))
  const freed = chosen.reduce((sum, s) => sum + s.memory, 0)
  const focusedServer = demo.running.find((s) => s.port === focus)
  const focusedApp = OTHER_APPS.find((app) => app.id === focus)
  const focusedMemory = focusedServer?.memory ?? focusedApp?.memory
  const [value, unit] = (
    focusedServer ? formatMemory(focusedServer.memory) : formatTotal(focusedMemory ?? (cleaning ? freed : total))
  ).split(' ')
  const activePort = focus ?? hoveredRow
  const activate = (port: string) => {
    if (cleaning) demo.toggleSelected(port)
    else {
      setFocus(null)
      demo.go({ name: 'detail', port }, 1)
    }
  }

  return (
    <>
      <div className={styles.popHead}>
        <Header
          title={
            focusedServer
              ? `${focusedServer.name} :${focusedServer.port}`
              : (focusedApp?.name ?? (cleaning ? 'Clean up' : 'Servers'))
          }
        />
        <div className={styles.popDisplay}>
          <span className={styles.popBig}>{value}</span>
          <span className={styles.popUnit}>{unit}</span>
          <span className={styles.summaryDetail}>
            {focusedMemory !== undefined ? (
              <span className={focusedApp?.id === 'rest' ? styles.t2 : styles.mono}>
                {focusedApp?.id === 'rest'
                  ? 'System and smaller apps'
                  : `${((focusedMemory / SYSTEM_MEMORY) * 100).toFixed(1)}% of RAM${focusedServer ? ` · CPU ${focusedServer.cpu}%` : ''}`}
              </span>
            ) : cleaning ? (
              <span className={styles.t2}>
                {chosen.length ? `freed by stopping ${chosen.length}` : 'Pick servers to stop'}
              </span>
            ) : (
              <button
                type="button"
                className={styles.cpuToggle}
                onClick={() => setCpuAll((v) => !v)}
                title={
                  cpuAll
                    ? 'Whole Mac. Click for servers only.'
                    : 'Dev servers, as a share of the whole Mac. Click for all.'
                }
              >
                <span className={styles.t3}>CPU ({cpuAll ? 'all' : 'servers'})</span>
                <span className={`${styles.mono} ${styles.t2}`}>{cpuAll ? cpu + 18 : cpu}%</span>
              </button>
            )}
          </span>
        </div>
        <div className={styles.shareBar} aria-label="Mac memory usage">
          {demo.running.map((s) => (
            <button
              key={s.port}
              type="button"
              className={styles.memorySegment}
              style={{ flexGrow: s.memory, color: portColor(s.port) }}
              data-raised
              data-focused={activePort === s.port}
              data-dim={
                (activePort !== null && activePort !== s.port) ||
                (cleaning && !demo.selected.includes(s.port) && activePort !== s.port)
              }
              aria-label={`${s.name} :${s.port} · ${formatMemory(s.memory)}`}
              aria-pressed={cleaning ? demo.selected.includes(s.port) : undefined}
              onMouseEnter={() => setFocus(s.port)}
              onMouseLeave={() => setFocus(null)}
              onFocus={() => setFocus(s.port)}
              onBlur={() => setFocus(null)}
              onClick={() => activate(s.port)}
            />
          ))}
          {OTHER_APPS.map((app) => (
            <span
              key={app.id}
              className={styles.memorySegment}
              style={{ flexGrow: app.memory }}
              tabIndex={0}
              role="img"
              aria-label={`${app.name} · ${formatMemory(app.memory)}`}
              data-focused={focus === app.id}
              onMouseEnter={() => setFocus(app.id)}
              onMouseLeave={() => setFocus(null)}
              onFocus={() => setFocus(app.id)}
              onBlur={() => setFocus(null)}
            />
          ))}
          <span
            className={styles.freeMemory}
            style={{ flexGrow: SYSTEM_MEMORY - total - OTHER_MEMORY }}
            title={`Free · ${formatMemory(SYSTEM_MEMORY - total - OTHER_MEMORY)}`}
          />
        </div>
        <div className={styles.memoryLegend}>
          <span>
            <i data-servers />
            Servers <b>{formatTotal(total)}</b>
          </span>
          <span>
            <i />
            Other apps <b>{formatTotal(OTHER_MEMORY)}</b>
          </span>
          <span>
            <i data-free />
            Free <b>{formatTotal(SYSTEM_MEMORY - total - OTHER_MEMORY).split(' ')[0]} of 16 GB</b>
          </span>
        </div>
      </div>

      <div className={`${styles.popSection} ${styles.rowList}`}>
        {!demo.running.length && (
          <div className={styles.emptyState}>
            <DotGrid size={48} />
            <span className={styles.t2}>Nothing listening</span>
            <span className={`${styles.caption} ${styles.t3}`}>Dev servers on ports 3000–9999 show up here.</span>
          </div>
        )}
        {demo.running.map((s) => (
          <div
            key={s.port}
            role="button"
            tabIndex={0}
            className={styles.serverRow}
            data-interactive
            data-dim={s.status === 'idle' || (focus !== null && focus !== s.port)}
            data-focused={focus === s.port}
            data-cleaning={cleaning}
            aria-pressed={cleaning ? demo.selected.includes(s.port) : undefined}
            aria-label={`${cleaning ? 'Select' : 'View'} ${s.branch} on port ${s.port}`}
            onMouseEnter={() => setHoveredRow(s.port)}
            onMouseLeave={() => setHoveredRow(null)}
            onClick={() => activate(s.port)}
            onKeyDown={(e) => {
              if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
                e.preventDefault()
                activate(s.port)
              }
            }}
          >
            {cleaning && (
              <span className={styles.checkbox} data-checked={demo.selected.includes(s.port)} aria-hidden>
                <svg width="10" height="10" viewBox="0 0 10 10">
                  <path
                    d="M2 5.2 4.1 7.3 8 2.8"
                    fill="none"
                    stroke="#0B0D12"
                    strokeWidth="1.6"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </span>
            )}
            <Colon state={s.status} color={portColor(s.port)} />
            <span className={styles.rowPort} style={{ color: portColor(s.port) }}>
              {s.port}
            </span>
            <span className={styles.rowMain}>
              <span className={styles.rowName} title={s.branch}>
                {s.branch.replaceAll('-', ' ')}
              </span>
              <span className={styles.rowSub} style={{ color: s.context.tone === 'amber' ? AMBER : '#EBEBF599' }}>
                {cleaning && s.cleanUp ? REASON_ICONS[s.cleanUp.reason] : <AgentIcon agent={s.context.agent} />}
                <span className={styles.ellipsis}>
                  {flash === s.port
                    ? `Opened localhost:${s.port}`
                    : cleaning && s.cleanUp
                      ? s.cleanUp.note
                      : s.context.text}
                </span>
              </span>
            </span>
            <svg className={styles.rowSpark} width="40" height="18" viewBox="0 0 44 18" aria-hidden>
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
            {!cleaning && (
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
            )}
            <span className={styles.rowMemory} style={{ color: s.status === 'amber' ? AMBER : undefined }}>
              {formatMemory(s.memory)}
            </span>
          </div>
        ))}
      </div>

      {!demo.running.length ? (
        <div className={`${styles.popSection} ${styles.actions}`}>
          <button type="button" className={styles.primaryAction} onClick={demo.restartAll}>
            Start the demo servers again
          </button>
        </div>
      ) : cleaning ? (
        <div className={`${styles.popSection} ${styles.actions}`}>
          <button type="button" className={styles.secondaryAction} onClick={() => demo.go({ name: 'list' }, -1)}>
            Cancel
          </button>
          <button
            type="button"
            className={`${styles.primaryAction} ${styles.destructive}`}
            disabled={!chosen.length}
            onClick={() => {
              demo.stop(chosen.map((s) => s.port))
              demo.go({ name: 'list' }, -1)
            }}
          >
            {chosen.length
              ? `Stop ${chosen.length} ${chosen.length === 1 ? 'server' : 'servers'} · free ${formatMemory(freed)}`
              : 'Stop servers'}
          </button>
        </div>
      ) : (
        <div className={`${styles.popSection} ${styles.popFooter}`}>
          <button type="button" className={styles.chip} onClick={() => demo.go({ name: 'cleanUp' }, 1)}>
            <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
              <path
                d="M8.5 1.5 6 7M3 8.5h7l.8 4H2.2L3 8.5Z"
                fill="none"
                stroke="#F5F5F7"
                strokeWidth="1.3"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
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
      )}
    </>
  )
}

function DetailView({ demo, server }: { demo: Demo; server: Server }) {
  const [moreInfo, setMoreInfo] = useState(false)
  const [processesOpen, setProcessesOpen] = useState(false)
  const [restarting, setRestarting] = useState(false)
  const [restarted, setRestarted] = useState(false)
  const [flash, trigger] = useFlash()
  const [hover, setHover] = useState<number | null>(null)
  const memory = memoryChart(server)
  const bars = cpuBars(server)
  const sample = hover === null ? null : memory.points[Math.round(hover * (memory.points.length - 1))]
  const cpuSample = hover === null ? server.cpu : bars[Math.round(hover * (bars.length - 1))]
  const timestamp =
    hover === null
      ? null
      : `13:${String(14 + Math.floor(hover * 10)).padStart(2, '0')}:${String(Math.floor(hover * 600) % 60).padStart(2, '0')}`
  const chartHover = (event: React.MouseEvent<SVGSVGElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect()
    setHover(Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width)))
  }

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
  const hiddenInfo: [string, string][] = server.info
    .filter(([label]) => !(label === 'Folder' && !server.session) && label !== 'PID' && label !== 'Git')
    .map(([label, value]) => [label, label === 'Workspace' ? `Conductor · ${value}` : value])
  if (server.session) hiddenInfo.push(['Session ID', server.session.id])

  return (
    <>
      <div className={styles.popHead}>
        <Header title={server.name} onBack={() => demo.go({ name: 'list' }, -1)} />
        <div className={styles.popDisplay} style={{ justifyContent: 'space-between' }}>
          <span className={styles.popDisplay}>
            <Colon state={server.status} color={portColor(server.port)} dot={6} gap={6} />
            <span className={styles.popBig} style={{ color: portColor(server.port) }}>
              {server.port}
            </span>
          </span>
          <span className={styles.popDisplay} style={{ gap: 10 }}>
            <span className={styles.t3}>
              {restarting
                ? 'restarting…'
                : restarted
                  ? 'Running for <1m'
                  : `Running for ${server.uptime.replace(/^(up|idle) /, '')}`}
            </span>
            <span className={styles.popDisplay}>
              <button
                type="button"
                className={styles.control}
                aria-label="Restart"
                disabled={server.status === 'idle' || restarting}
                title={
                  server.status === 'idle' ? 'Working directory no longer exists' : 'Restart with the same command'
                }
                data-spinning={restarting}
                onClick={() => setRestarting(true)}
              >
                <svg width="13" height="13" viewBox="0 0 14 14" aria-hidden>
                  <path
                    d="M11.5 7a4.5 4.5 0 1 1-1.3-3.2"
                    fill="none"
                    stroke="#F5F5F7"
                    strokeWidth="1.4"
                    strokeLinecap="round"
                  />
                  <path
                    d="M10.6 1.6v2.6H8"
                    fill="none"
                    stroke="#F5F5F7"
                    strokeWidth="1.4"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
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
                <span
                  className={`${styles.ellipsis} ${label === 'PID' || label === 'Command' ? styles.mono : ''} ${styles.t1}`}
                >
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
            <span className={styles.t2}>Memory</span>
            <span className={styles.mono} style={{ fontWeight: 500 }}>
              {formatMemory(sample?.memory ?? server.memory)}
            </span>
          </span>
          <span className={`${styles.mono} ${styles.caption} ${styles.t3}`}>{timestamp ?? '10 min'}</span>
        </div>
        <div className={styles.plot}>
          <span className={styles.axis} style={{ height: 56, position: 'relative' }}>
            <span style={{ position: 'absolute', top: memory.limit - 7, color: '#FFB224D9' }}>2 GB</span>
            <span style={{ position: 'absolute', bottom: -6 }}>0</span>
          </span>
          <svg
            width="328"
            height="56"
            viewBox="0 0 328 56"
            role="img"
            aria-label="Memory over the last ten minutes"
            style={{ flexShrink: 0 }}
            onMouseMove={chartHover}
            onMouseLeave={() => setHover(null)}
          >
            <path d="M0.5 0 V56 M0 55.5 H328" fill="none" stroke="rgb(255 255 255 / 14%)" />
            <path d={`M0 ${memory.limit} H328`} fill="none" stroke="rgb(255 178 36 / 55%)" strokeDasharray="3 3" />
            <path
              className={styles.chartLine}
              d={memory.line}
              fill="none"
              stroke="rgb(245 245 247 / 90%)"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              pathLength={1}
            />
            {sample && <path d={`M${sample.x} 0 V56`} stroke="#F5F5F740" />}
            <circle cx={sample?.x ?? 327} cy={sample?.y ?? memory.end} r="3" fill="#F5F5F7" />
          </svg>
        </div>
      </div>

      <div className={styles.chart} style={{ paddingTop: 0 }}>
        <div className={styles.chartHead}>
          <span className={styles.chartTitle}>
            <span className={styles.t2}>CPU</span>
            <span className={styles.mono} style={{ fontWeight: 500 }}>
              {Math.round(cpuSample)}%
            </span>
          </span>
          {timestamp && <span className={`${styles.mono} ${styles.caption} ${styles.t3}`}>{timestamp}</span>}
        </div>
        <div className={styles.plot}>
          <span className={styles.axis} style={{ height: 56 }}>
            <span style={{ marginTop: -6 }}>100%</span>
            <span style={{ marginBottom: -6 }}>0</span>
          </span>
          <svg
            width="328"
            height="56"
            viewBox="0 0 328 56"
            role="img"
            aria-label="CPU over the last ten minutes"
            style={{ flexShrink: 0 }}
            onMouseMove={chartHover}
            onMouseLeave={() => setHover(null)}
          >
            <path d="M0.5 0 V56 M0 55.5 H328" fill="none" stroke="rgb(255 255 255 / 14%)" />
            {bars.map((cpu, i) => (
              <rect
                key={i}
                className={styles.cpuBar}
                style={{ animationDelay: `${i * 6}ms` }}
                x={0.5 + i * 5.4627}
                y={56 - Math.max(0.6, cpu * 0.56)}
                width="3"
                height={Math.max(0.6, cpu * 0.56)}
                rx="1"
                fill={i === Math.round((hover ?? 1) * (bars.length - 1)) ? '#F5F5F7D9' : '#F5F5F752'}
              />
            ))}
            {hover !== null && <path d={`M${hover * 328} 0 V56`} stroke="#F5F5F740" />}
          </svg>
        </div>
      </div>

      <div className={styles.popSection}>
        <button
          type="button"
          className={styles.processes}
          onClick={() => setProcessesOpen((v) => !v)}
          aria-expanded={processesOpen}
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
              {server.processes.map((p, index) => (
                <div key={p.command} className={styles.processRow}>
                  <span className={`${styles.mono} ${styles.ellipsis} ${styles.t1}`}>
                    {index ? '└ ' : ''}
                    {p.command}
                  </span>
                  <span className={styles.processBar}>
                    <i style={{ width: `${(p.memory / Math.max(...server.processes.map((p) => p.memory))) * 100}%` }} />
                  </span>
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
      <path
        d="M1.5 3.5c0-.6.4-1 1-1h2.3l1 1.2h3.7c.6 0 1 .4 1 1V9c0 .6-.4 1-1 1h-7c-.6 0-1-.4-1-1V3.5Z"
        fill="none"
        stroke="rgb(235 235 245 / 60%)"
        strokeWidth="1.1"
      />
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
      <path
        d="M1.5 9 4.5 6l2 2 4-4.5M7.5 3.5h3v3"
        fill="none"
        stroke={AMBER}
        strokeWidth="1.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
}

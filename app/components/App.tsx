'use client'

import { Fragment, type ReactNode, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import styles from './landing.module.css'
import { AMBER, BackIcon, Chevron, ClaudeIcon, CodexIcon, Colon, ContainerIcon, DotGrid, OpenIcon, PauseIcon, PlayIcon, ServiceIcon, VercelIcon } from './icons'
import { type AppLanguageCode, type Localizer, localizer } from './languages'
import { GET_IT, TERMINAL } from './sections'
import {
  type Agent,
  type Server,
  type ServerSort,
  SERVERS,
  SERVER_SORTS,
  OTHER_APPS,
  OTHER_MEMORY,
  SYSTEM_MEMORY,
  cpuBars,
  formatMemory,
  formatTotal,
  memoryChart,
  pausedServer,
  portColor,
  serverResources,
  serverSections,
  shortBranch,
  sortServers,
  stoppedPorts,
} from './servers'

// A working copy of the WhatThePort popover. Scrolling picks the view for each
// section; clicking around works like the real app until the next section.

type View = { name: 'list' } | { name: 'detail'; port: string } | { name: 'cleanUp' } | { name: 'pauseMany' }

const SECTION_VIEWS: View[] = [
  { name: 'list' },
  { name: 'detail', port: '3000' },
  { name: 'detail', port: '6006' },
  { name: 'cleanUp' },
  { name: 'list' },
  { name: 'list' },
  { name: 'list' },
]

// The Terminal section shows `wtp` instead, and the last section the dot matrix.
const opensPopover = (section: number) => section !== GET_IT && section !== TERMINAL

const ramShare = (mb: number) => `${((mb / SYSTEM_MEMORY) * 100).toFixed(1)}%`

const suggested = (running: string[], paused: string[] = []) =>
  SERVERS.filter((s) => s.cleanUp?.suggested && running.includes(s.port) && !paused.includes(s.port)).map((s) => s.port)

export function useDemo(section: number) {
  const [running, setRunning] = useState(() => SERVERS.map((s) => s.port))
  const [paused, setPaused] = useState<string[]>([])
  const [sort, setSort] = useState<ServerSort>('port')
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
    setSelected(suggested(running, paused))
    // `running` and `paused` intentionally omitted: stopping a server shouldn't reset the view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [section])

  const go = useCallback(
    (next: View, dir: number) => {
      setDirection(dir)
      if (next.name === 'cleanUp') setSelected(suggested(running, paused))
      if (next.name === 'pauseMany') setSelected([])
      setView(next)
    },
    [running, paused],
  )

  const stop = useCallback((selectedPorts: string[]) => {
    const ports = stoppedPorts(SERVERS, selectedPorts)
    setRunning((current) => current.filter((port) => !ports.includes(port)))
    setSelected((current) => current.filter((port) => !ports.includes(port)))
    setPaused((current) => current.filter((port) => !ports.includes(port)))
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
    setPaused([])
    setSelected(suggested(all))
  }, [])

  // Ports served by one process pause together, as they stop together.
  const togglePause = useCallback((port: string) => {
    const ports = stoppedPorts(SERVERS, [port])
    setPaused((current) => (current.includes(port) ? current.filter((p) => !ports.includes(p)) : [...current, ...ports]))
  }, [])

  const pause = useCallback((ports: string[]) => {
    const all = stoppedPorts(SERVERS, ports)
    setPaused((current) => [...current, ...all.filter((port) => !current.includes(port))])
  }, [])

  const resume = useCallback((port: string) => {
    const ports = stoppedPorts(SERVERS, [port])
    setPaused((current) => current.filter((p) => !ports.includes(p)))
  }, [])

  const toggleSelected = useCallback((port: string) => {
    setSelected((current) => (current.includes(port) ? current.filter((p) => p !== port) : [...current, port]))
  }, [])

  // A detail view for a server that's been stopped falls back to the list.
  const shown: View = view.name === 'detail' && !running.includes(view.port) ? { name: 'list' } : view

  return {
    running: SERVERS.filter((s) => running.includes(s.port)).map((s) => (paused.includes(s.port) ? pausedServer(s) : s)),
    view: shown,
    direction,
    open,
    setOpen,
    selected,
    sort,
    setSort,
    toggleSelected,
    go,
    stop,
    togglePause,
    pause,
    resume,
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

// `language` shows the app's own translations, laid out right-to-left for Hebrew.
export function AppPopover({ demo, language = 'en' }: { demo: Demo; language?: AppLanguageCode }) {
  const { view, direction } = demo
  const l = localizer(language)
  const key =
    view.name === 'detail'
      ? `detail-${view.port}`
      : demo.running.length
        ? 'list'
        : 'empty'

  let content: ReactNode
  if (view.name === 'detail') content = <DetailView demo={demo} server={demo.running.find((s) => s.port === view.port)!} l={l} />
  else content = <ListView demo={demo} l={l} />

  return (
    <Frame viewKey={key}>
      <div
        key={key}
        className={styles.view}
        style={{ ['--dir' as string]: direction }}
        lang={language}
        dir={l.rtl ? 'rtl' : 'ltr'}
      >
        {content}
      </div>
    </Frame>
  )
}

function Header({ title, onBack, backLabel }: { title: string; onBack?: () => void; backLabel?: string }) {
  return (
    <div className={styles.popTitleRow}>
      <span className={styles.popTitle}>{title}</span>
      {onBack && (
        <button type="button" className={styles.popBack} onClick={onBack} aria-label={backLabel}>
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

function ListView({ demo, l }: { demo: Demo; l: Localizer }) {
  const [flash, trigger] = useFlash()
  const cleaning = demo.view.name === 'cleanUp'
  const pausing = demo.view.name === 'pauseMany'
  const selecting = cleaning || pausing
  const [focus, setFocus] = useState<string | null>(null)
  const [hoveredRow, setHoveredRow] = useState<string | null>(null)
  const [cpuAll, setCpuAll] = useState(false)
  const resources = serverResources(demo.running)
  const total = resources.memory
  const cpu = Math.round(resources.cpu / 8)
  const cleanUpCount = demo.running.filter((s) => s.cleanUp?.suggested).length
  // Protected servers can't be stopped from Clean up or paused in bulk, so they're hidden there, like the app.
  const pausable = demo.running.filter((s) => s.status !== 'paused' && !s.protected)
  const listed = pausing ? pausable : cleaning ? demo.running.filter((s) => !s.protected) : demo.running
  const sections = serverSections(sortServers(listed, demo.sort), demo.sort)
  const visible = sections.flatMap((section) => section.servers)
  const chosen = visible.filter((s) => demo.selected.includes(s.port))
  const freed = serverResources(chosen).memory
  const focusedServer = demo.running.find((s) => s.port === focus)
  const focusedApp = OTHER_APPS.find((app) => app.id === focus)
  const focusedMemory = focusedServer?.memory ?? focusedApp?.memory
  const [value, unit] = (
    focusedServer ? formatMemory(focusedServer.memory) : formatTotal(focusedMemory ?? (selecting ? freed : total))
  ).split(' ')
  const activePort = focus ?? hoveredRow
  const activate = (port: string) => {
    if (selecting) demo.toggleSelected(port)
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
              : (focusedApp?.id === 'rest' ? l.text('Everything else') : (focusedApp?.name ?? l.text(cleaning ? 'Clean up' : pausing ? 'Pause multiple' : 'Servers')))
          }
        />
        <div className={styles.popDisplay}>
          <span className={styles.popBig}>{value}</span>
          <span className={styles.popUnit}>{unit}</span>
          <span className={styles.summaryDetail}>
            {focusedMemory !== undefined ? (
              <span className={focusedApp?.id === 'rest' ? styles.t2 : styles.mono}>
                {focusedApp?.id === 'rest'
                  ? l.text('System and smaller apps')
                  : focusedServer
                    ? l.format('%@ of RAM · CPU %@', ramShare(focusedMemory), `${focusedServer.cpu}%`)
                    : l.format('%@ of RAM', ramShare(focusedMemory))}
              </span>
            ) : pausing ? (
              chosen.length ? (
                <span className={styles.mono}>{l.format('%@ of RAM · CPU %@', ramShare(freed), `${serverResources(chosen).cpu}%`)}</span>
              ) : (
                <span className={styles.t2}>{l.text('Pick servers to pause')}</span>
              )
            ) : cleaning ? (
              <span className={styles.t2}>
                {chosen.length ? l.format('freed by stopping %d', chosen.length) : l.text('Pick servers to stop')}
              </span>
            ) : (
              <button
                type="button"
                className={styles.cpuToggle}
                onClick={() => setCpuAll((v) => !v)}
                title={l.text(
                  cpuAll ? 'Whole Mac. Click for servers only.' : 'Dev servers, as a share of the whole Mac. Click for all.',
                )}
              >
                <span className={styles.t3}>{l.text(cpuAll ? 'CPU (all)' : 'CPU (servers)')}</span>
                <span className={`${styles.mono} ${styles.t2}`}>{cpuAll ? cpu + 18 : cpu}%</span>
              </button>
            )}
          </span>
        </div>
        <div className={styles.shareBar} aria-label="Mac memory usage">
          {visible.map((s) => (
            <button
              key={s.port}
              type="button"
              className={styles.memorySegment}
              style={{ flexGrow: resources.memoryByPort.get(s.port) ?? 0, color: portColor(s.port) }}
              data-raised
              data-focused={activePort === s.port}
              data-dim={
                (activePort !== null && activePort !== s.port) ||
                (selecting && !demo.selected.includes(s.port) && activePort !== s.port)
              }
              aria-label={`${s.name} :${s.port} · ${formatMemory(s.memory)}`}
              aria-pressed={selecting ? demo.selected.includes(s.port) : undefined}
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
              aria-label={app.id === 'rest' ? l.format('Everything else · %@', formatMemory(app.memory)) : `${app.name} · ${formatMemory(app.memory)}`}
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
            title={l.format('Free · %@', formatMemory(SYSTEM_MEMORY - total - OTHER_MEMORY))}
          />
        </div>
        <div className={styles.memoryLegend}>
          <span>
            <i data-servers />
            {l.text('Servers')} <b>{formatTotal(total)}</b>
          </span>
          <span>
            <i />
            {l.text('Other apps')} <b>{formatTotal(OTHER_MEMORY)}</b>
          </span>
          <span>
            <i data-free />
            {l.text('Free')} <b>{l.format('%@ of %@', formatTotal(SYSTEM_MEMORY - total - OTHER_MEMORY).split(' ')[0], '16 GB')}</b>
          </span>
        </div>
      </div>

      {visible.length > 0 && (
        <div className={styles.sortDivider}>
          <i />
          <label className={styles.sortMenu} title={l.text('Sort servers')}>
            {l.text(SERVER_SORTS.find(([id]) => id === demo.sort)![1])}
            <Chevron direction="down" />
            <select aria-label={l.text('Sort servers')} value={demo.sort} onChange={(e) => demo.setSort(e.target.value as ServerSort)}>
              {SERVER_SORTS.map(([id, label]) => (
                <option key={id} value={id}>
                  {l.text(label)}
                </option>
              ))}
            </select>
          </label>
          <i />
        </div>
      )}

      <div className={`${styles.popSection} ${styles.rowList}`}>
        {!demo.running.length && (
          <div className={styles.emptyState}>
            <DotGrid size={48} />
            <span className={styles.t2}>{l.text('Nothing listening')}</span>
            <span className={`${styles.caption} ${styles.t3}`}>
              {l.format('Dev servers on ports %d–%d show up here.', 3000, 65535)}
            </span>
          </div>
        )}
        {sections.map((section) => (
          <Fragment key={section.id}>
            {section.title && (
              <div className={styles.serverGroup}>
                <span className={styles.serverGroupTitle}>{section.title}</span>
                <span className={styles.serverGroupDetail}>{section.detail}</span>
                {!selecting && (
                  <button
                    type="button"
                    className={styles.rowAction}
                    aria-label={l.text('Stop all')}
                    title={l.text('Stop all')}
                    onClick={() => demo.stop(section.servers.map((s) => s.port))}
                  >
                    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
                      <rect x="2.5" y="2.5" width="7" height="7" rx="1.5" fill="rgb(245 245 247 / 80%)" />
                    </svg>
                  </button>
                )}
                <span className={styles.serverGroupMemory}>{formatMemory(serverResources(section.servers).memory)}</span>
              </div>
            )}
            {section.servers.map((s) => (
              <div
                key={s.port}
                role="button"
                tabIndex={0}
                className={styles.serverRow}
                data-interactive
                data-dim={s.status === 'idle' || (s.status === 'paused' && hoveredRow !== s.port) || (focus !== null && focus !== s.port)}
                data-focused={focus === s.port}
                data-cleaning={selecting}
                aria-pressed={selecting ? demo.selected.includes(s.port) : undefined}
                aria-label={`${selecting ? 'Select' : 'View'} ${shortBranch(s.branch)} on port ${s.port}`}
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
                {selecting && (
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
                <span className={styles.portLabel}>
                  <Colon state={s.status} color={portColor(s.port)} />
                  <span className={styles.rowPort} style={{ color: portColor(s.port) }}>
                    {s.port}
                  </span>
                </span>
                <span className={styles.rowMain}>
                  <span className={styles.rowName} title={s.branch}>
                    {shortBranch(s.branch).replaceAll('-', ' ')}
                  </span>
                  <span className={styles.rowSub} style={{ color: s.context.tone === 'amber' ? AMBER : '#EBEBF599' }}>
                    {cleaning && s.cleanUp ? REASON_ICONS[s.cleanUp.reason] : s.container ? <ServiceIcon service={s.container.service} color={s.context.tone === 'amber' ? AMBER : undefined} /> : <AgentIcon agent={s.context.agent} />}
                    <span className={styles.ellipsis}>
                      {flash === s.port
                        ? `Opened localhost:${s.port}`
                        : cleaning && s.cleanUp
                          ? s.lines(l).note
                          : s.lines(l).context}
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
                {!selecting && (
                  <span className={styles.rowActions}>
                    <button
                      type="button"
                      className={styles.rowAction}
                      aria-label={l.text('Open in browser')}
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
                      aria-label={l.text(s.status === 'paused' ? 'Resume' : 'Pause')}
                      title={l.text(s.status === 'paused' ? 'Resume' : 'Pause')}
                      onClick={(e) => {
                        e.stopPropagation()
                        demo.togglePause(s.port)
                      }}
                    >
                      {s.status === 'paused' ? <PlayIcon color="rgb(245 245 247 / 80%)" /> : <PauseIcon color="rgb(245 245 247 / 80%)" />}
                    </button>
                    <button
                      type="button"
                      className={styles.rowAction}
                      aria-label={l.text('Stop')}
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
          </Fragment>
        ))}
      </div>

      {!demo.running.length ? (
        <div className={`${styles.popSection} ${styles.actions}`}>
          <button type="button" className={styles.primaryAction} onClick={demo.restartAll}>
            Start the demo servers again
          </button>
        </div>
      ) : pausing ? (
        <div className={`${styles.popSection} ${styles.actions}`}>
          <button type="button" className={styles.secondaryAction} onClick={() => demo.go({ name: 'list' }, -1)}>
            {l.text('Cancel')}
          </button>
          <button
            type="button"
            className={styles.primaryAction}
            disabled={!chosen.length}
            onClick={() => {
              demo.pause(chosen.map((s) => s.port))
              demo.go({ name: 'list' }, -1)
            }}
          >
            {chosen.length ? l.format('Pause %d %@', chosen.length, l.counted('server', 'servers', chosen.length)) : l.text('Pause servers')}
          </button>
        </div>
      ) : cleaning ? (
        <div className={`${styles.popSection} ${styles.actions}`}>
          <button type="button" className={styles.secondaryAction} onClick={() => demo.go({ name: 'list' }, -1)}>
            {l.text('Cancel')}
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
              ? l.format('Stop %d %@ · free %@', chosen.length, l.counted('server', 'servers', chosen.length), formatMemory(freed))
              : l.text('Stop servers')}
          </button>
        </div>
      ) : (
        <div className={`${styles.popSection} ${styles.popFooter}`}>
          <span className={styles.footerActions}>
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
              <span className={styles.popTitle}>{l.text('Clean up')}</span>
              {cleanUpCount > 0 && <span className={styles.chipCount}>{cleanUpCount}</span>}
            </button>
            <button type="button" className={styles.chip} disabled={!pausable.length} onClick={() => demo.go({ name: 'pauseMany' }, 1)}>
              <PauseIcon />
              <span className={styles.popTitle}>{l.text('Pause multiple')}</span>
            </button>
          </span>
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

function DetailView({ demo, server, l }: { demo: Demo; server: Server; l: Localizer }) {
  const [moreInfo, setMoreInfo] = useState(false)
  const [processesOpen, setProcessesOpen] = useState(false)
  const [restarting, setRestarting] = useState(false)
  const [restarted, setRestarted] = useState(false)
  const [flash, trigger] = useFlash()
  const [hover, setHover] = useState<number | null>(null)
  const isPaused = server.status === 'paused'
  const worktreeDeleted = SERVERS.find((s) => s.port === server.port)?.status === 'idle'
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

  const shownInfo: [string, ReactNode][] = server.container
    ? [
        [
          'Container',
          <span key="container" className={styles.infoValue}>
            {server.container ? <ServiceIcon service={server.container.service} /> : <ContainerIcon />}
            <span className={`${styles.ellipsis} ${styles.t1}`}>
              {server.container.runtime} · {server.name}
            </span>
          </span>,
        ],
        ['Branch', server.container.branch],
      ]
    : server.session
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
    .filter(([label]) => !(label === 'Folder' && !server.session && !server.container) && label !== 'PID' && label !== 'Git')
  if (server.session) hiddenInfo.push(['Session ID', server.session.id])

  return (
    <>
      <div className={styles.popHead}>
        <Header title={server.name} onBack={() => demo.go({ name: 'list' }, -1)} backLabel={l.text('Back')} />
        <div className={styles.popDisplay} style={{ justifyContent: 'space-between' }}>
          <span className={styles.popDisplay} dir="ltr">
            <Colon state={server.status} color={portColor(server.port)} dot={6} gap={6} />
            <span className={styles.popBig} style={{ color: portColor(server.port) }}>
              {server.port}
            </span>
          </span>
          <span className={styles.popDisplay} style={{ gap: 10 }}>
            <span className={styles.t3}>
              {restarting
                ? 'restarting…'
                : isPaused
                  ? l.text('Paused')
                  : restarted
                    ? l.format('Running for %@', l.duration(0))
                    : l.format('Running for %@', server.lines(l).running)}
            </span>
            <span className={styles.popDisplay}>
              <button
                type="button"
                className={styles.control}
                aria-label="Restart"
                disabled={worktreeDeleted || restarting}
                title={
                  worktreeDeleted
                    ? 'Working directory no longer exists'
                    : l.text(server.container ? 'Restart container' : 'Restart with the same command')
                }
                data-spinning={restarting}
                onClick={() => {
                  demo.resume(server.port)
                  setRestarting(true)
                }}
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
                className={styles.control}
                aria-label={l.text(isPaused ? 'Resume' : 'Pause')}
                title={l.text(isPaused ? 'Resume' : 'Pause')}
                onClick={() => demo.togglePause(server.port)}
              >
                {isPaused ? <PlayIcon /> : <PauseIcon />}
              </button>
              <button
                type="button"
                className={`${styles.control} ${styles.controlStop}`}
                aria-label={l.text('Stop')}
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
            <span className={styles.infoLabel}>{l.text(label)}</span>
            {typeof value === 'string' ? <span className={`${styles.ellipsis} ${styles.t1}`}>{value}</span> : value}
          </div>
        ))}
        <div className={styles.collapsible} data-open={moreInfo}>
          <div>
            {hiddenInfo.map(([label, value]) => (
              <div key={label} className={styles.infoRow}>
                <span className={styles.infoLabel}>{l.text(label)}</span>
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
            {moreInfo ? l.text('Less') : l.format('%d more', hiddenInfo.length)} <Chevron direction="down" />
          </button>
        </div>
      </div>

      <div className={`${styles.popSection} ${styles.chart}`}>
        <div className={styles.chartHead}>
          <span className={styles.chartTitle}>
            <span className={styles.t2}>{l.text('Memory')}</span>
            <span className={styles.mono} style={{ fontWeight: 500 }}>
              {formatMemory(sample?.memory ?? server.memory)}
            </span>
          </span>
          <span className={`${styles.mono} ${styles.caption} ${styles.t3}`}>{timestamp ?? l.text('10 min')}</span>
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

      {server.container ? (
        // A container's processes run inside the runtime's VM, so the app shows the container instead.
        <div className={styles.popSection}>
          <div className={styles.processes}>
            <span className={styles.t2}>{l.text('Container')}</span>
            <span className={`${styles.mono} ${styles.t2}`}>
              {server.container.id} · {formatMemory(server.memory)}
            </span>
          </div>
        </div>
      ) : (
        <div className={styles.popSection}>
          <button
            type="button"
            className={styles.processes}
            onClick={() => setProcessesOpen((v) => !v)}
            aria-expanded={processesOpen}
            data-open={processesOpen}
          >
            <span className={styles.popDisplay} style={{ gap: 4 }}>
              <span className={styles.t2}>{l.text('Processes')}</span>
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
      )}

      <div className={`${styles.popSection} ${styles.actions}`}>
        <button type="button" className={styles.primaryAction} onClick={() => trigger('open')}>
          {flash === 'open' ? 'Opened in your browser' : l.format('Open localhost:%@', server.port)}
        </button>
        {!server.container && (
          <button type="button" className={styles.secondaryAction} onClick={() => trigger('preview')}>
            <VercelIcon fill="rgb(235 235 245 / 75%)" width={11} height={10} />
            {flash === 'preview' ? 'Opened' : l.text('Preview')}
          </button>
        )}
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

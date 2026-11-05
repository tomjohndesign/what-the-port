import type { CSSProperties } from 'react'

export const AMBER = '#FFB224'

const GRID = [1.8, 5.4, 9, 12.6, 16.2]
const COLON = new Set(['2,1', '2,3'])

export type GridState = 'rest' | 'alert' | 'currentColor'

// The 5×5 dot-matrix mark. At rest the colon is lit; on alert every dot turns
// amber and the colon is knocked out. 'currentColor' draws it in the text colour.
export function DotGrid({ state = 'rest', size = 18 }: { state?: GridState; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" aria-hidden style={{ flexShrink: 0 }}>
      {GRID.map((cy, row) =>
        GRID.map((cx, col) => {
          const lit = COLON.has(`${col},${row}`)
          if (state === 'currentColor') {
            return <circle key={`${col}-${row}`} cx={cx} cy={cy} r={1.4} fill="currentColor" fillOpacity={lit ? 1 : 0.25} />
          }
          const fill =
            state === 'alert' ? (lit ? '#FFFFFF40' : AMBER) : lit ? '#FFFFFF' : '#FFFFFF40'
          return <circle key={`${col}-${row}`} cx={cx} cy={cy} r={1.4} fill={fill} />
        }),
      )}
    </svg>
  )
}

export type ColonState = 'on' | 'amber' | 'idle' | 'paused'

// The two status dots that prefix every port.
export function Colon({
  state = 'on',
  dot = 4,
  gap = 3,
  color,
}: {
  state?: ColonState
  dot?: number
  gap?: number
  color?: string
}) {
  const style: CSSProperties = { width: dot, height: dot, borderRadius: dot, flexShrink: 0 }
  if (state === 'on') style.backgroundColor = color ?? '#F5F5F7'
  if (state === 'amber') {
    style.backgroundColor = color ?? AMBER
    style.boxShadow = `${color ?? AMBER} 0 0 5px`
  }
  if (state === 'idle') style.boxShadow = `${color ?? '#EBEBF580'} 0 0 0 1.1px inset`
  if (state === 'paused') {
    style.backgroundColor = color ?? '#F5F5F7'
    style.opacity = 0.4
  }
  return (
    <span style={{ display: 'flex', flexDirection: 'column', gap, width: dot === 4 ? 9 : undefined, flexShrink: 0 }}>
      <span style={style} />
      <span style={style} />
    </span>
  )
}

const stroke = (alpha: number) => `rgb(235 235 245 / ${alpha}%)`

export function BranchIcon() {
  return (
    <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <circle cx="3" cy="2.5" r="1.4" fill="none" stroke={stroke(50)} strokeWidth="1.1" />
      <circle cx="3" cy="9.5" r="1.4" fill="none" stroke={stroke(50)} strokeWidth="1.1" />
      <circle cx="9" cy="4" r="1.4" fill="none" stroke={stroke(50)} strokeWidth="1.1" />
      <path d="M3 4v4M9 5.4c0 2-2 2.3-4.8 3.4" fill="none" stroke={stroke(50)} strokeWidth="1.1" />
    </svg>
  )
}

// The app's ServiceGlyph, for the services the demo runs. The icon is the row's second-line mark.
export type ServiceIconName = 'postgres' | 'redis'
const SERVICE_ICONS: Record<ServiceIconName, { d: string; evenOdd: boolean }> = {
  postgres: { d: 'M 6.5 1 C 5.119 1 4 2.119 4 3.5 C 4 3.5 4 4 4 4 C 4 4 3.5 4 3.5 4 C 2.119 4 1 5.119 1 6.5 C 1 6.5 1 13.5 1 13.5 C 1 13.776 1.224 14 1.5 14 C 1.776 14 2 13.776 2 13.5 C 2 13.5 2 6.5 2 6.5 C 2 5.672 2.672 5 3.5 5 C 3.5 5 4 5 4 5 C 4 5 4 7.073 4 7.073 C 4 8.56 5.565 9.527 6.894 8.862 C 6.894 8.862 7.618 8.5 7.618 8.5 C 8.465 8.077 9 7.211 9 6.264 C 9 6.264 9 5.5 9 5.5 C 9 5.224 8.776 5 8.5 5 C 8.224 5 8 5.224 8 5.5 C 8 5.5 8 6.264 8 6.264 C 8 6.832 7.679 7.351 7.171 7.606 C 7.171 7.606 6.447 7.967 6.447 7.967 C 5.782 8.3 5 7.816 5 7.073 C 5 7.073 5 3.5 5 3.5 C 5 2.672 5.672 2 6.5 2 C 6.5 2 9.5 2 9.5 2 C 11.433 2 13 3.567 13 5.5 C 13 5.5 13 7 13 7 C 13 7 12.618 7 12.618 7 C 12.618 7 10.724 6.053 10.724 6.053 C 10.569 5.975 10.385 5.984 10.237 6.075 C 10.09 6.166 10 6.327 10 6.5 C 10 6.5 10 13.5 10 13.5 C 10 13.776 10.224 14 10.5 14 C 10.776 14 11 13.776 11 13.5 C 11 13.5 11 7.309 11 7.309 C 11 7.309 12.276 7.947 12.276 7.947 C 12.346 7.982 12.422 8 12.5 8 C 12.5 8 13 8 13 8 C 13 8 13 9.672 13 9.672 C 13 10.335 13.263 10.97 13.732 11.439 C 13.732 11.439 14.146 11.854 14.146 11.854 C 14.342 12.049 14.658 12.049 14.854 11.854 C 15.049 11.658 15.049 11.342 14.854 11.146 C 14.854 11.146 14.439 10.732 14.439 10.732 C 14.158 10.451 14 10.069 14 9.672 C 14 9.672 14 8 14 8 C 14 8 14.5 8 14.5 8 C 14.776 8 15 7.776 15 7.5 C 15 7.224 14.776 7 14.5 7 C 14.5 7 14 7 14 7 C 14 7 14 5.5 14 5.5 C 14 3.015 11.985 1 9.5 1 C 9.5 1 6.5 1 6.5 1 Z M 3.5 11 C 3.224 11 3 11.224 3 11.5 C 3 11.5 3 13.5 3 13.5 C 3 13.776 3.224 14 3.5 14 C 3.776 14 4 13.776 4 13.5 C 4 13.5 4 12 4 12 C 4 12 8 12 8 12 C 8 12 8 13.5 8 13.5 C 8 13.776 8.224 14 8.5 14 C 8.776 14 9 13.776 9 13.5 C 9 13.5 9 11.5 9 11.5 C 9 11.224 8.776 11 8.5 11 C 8.5 11 3.5 11 3.5 11 Z', evenOdd: true },
  redis: { d: 'M 12.855 8.072 C 12.025 9.119 11.129 10.314 9.336 10.314 C 7.735 10.314 7.138 8.902 7.096 7.754 C 7.447 8.496 8.133 9.096 9.203 9.069 C 11.261 9.002 12.673 7.143 12.673 5.449 C 12.673 3.424 11.162 1.963 8.539 1.963 C 6.663 1.963 4.339 2.677 2.811 3.806 C 2.795 4.969 3.442 6.479 3.675 6.313 C 4.999 5.361 6.049 4.748 7.067 4.441 C 5.56 6.122 1.943 10.025 1.5 10.713 C 1.55 11.343 2.33 13.037 2.712 13.037 C 2.828 13.037 2.928 12.97 3.044 12.854 C 4.016 11.767 4.94 10.639 5.814 9.471 C 5.925 11.024 6.688 12.921 8.821 12.921 C 10.73 12.921 12.623 11.543 13.486 8.438 C 13.586 8.056 13.121 7.758 12.856 8.073 Z M 10.681 5.566 C 10.681 6.545 9.718 7.027 8.838 7.027 C 8.367 7.027 8.006 6.904 7.721 6.743 C 8.246 5.947 8.767 5.131 9.325 4.257 C 10.312 4.424 10.681 4.972 10.681 5.566 Z', evenOdd: false },
}

export function ServiceIcon({ service, color = stroke(60) }: { service: ServiceIconName; color?: string }) {
  const icon = SERVICE_ICONS[service]
  return (
    <svg width="15" height="15" viewBox="0 0 15 15" aria-hidden style={{ flexShrink: 0, margin: '-1px 0' }}>
      <path d={icon.d} fill={color} fillRule={icon.evenOdd ? 'evenodd' : 'nonzero'} />
    </svg>
  )
}

// The app's ContainerGlyph (SF Symbols shippingbox): marks a port a container publishes.
export function ContainerIcon({ color = stroke(75), size = 11 }: { color?: string; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M6 1.2 10.6 3.5v5L6 10.8 1.4 8.5v-5z" fill="none" stroke={color} strokeWidth="1.1" strokeLinejoin="round" />
      <path d="M1.4 3.5 6 5.8l4.6-2.3M6 5.8v5" fill="none" stroke={color} strokeWidth="1.1" strokeLinejoin="round" />
    </svg>
  )
}

export function ClaudeIcon({ color = stroke(75), size = 12, width = 1.4 }: { color?: string; size?: number; width?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M6 1v10M1 6h10M2.5 2.5l7 7M9.5 2.5l-7 7" fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" />
    </svg>
  )
}

export function CodexIcon({ color = stroke(75), size = 12, width = 1.2 }: { color?: string; size?: number; width?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <rect x="1" y="1.5" width="10" height="9" rx="2.5" fill="none" stroke={color} strokeWidth={width} />
      <path d="M3.5 5 5 6.2 3.5 7.4M6.2 7.6h2.3" fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function ConductorIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      {[
        [1.5, 1.5],
        [6.5, 1.5],
        [1.5, 6.5],
        [6.5, 6.5],
      ].map(([x, y]) => (
        <rect key={`${x}-${y}`} x={x} y={y} width="4" height="4" rx="1" fill="none" stroke="#F5F5F7" strokeWidth="1.1" />
      ))}
    </svg>
  )
}

export function PaneIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <rect x="1" y="2" width="10" height="8" rx="1.5" fill="none" stroke="#F5F5F7" strokeWidth="1.1" />
      <path d="M6 2v8" stroke="#F5F5F7" strokeWidth="1.1" />
    </svg>
  )
}

export function VercelIcon({ fill = '#FFFFFF', width = 12, height = 11 }: { fill?: string; width?: number; height?: number }) {
  return (
    <svg width={width} height={height} viewBox="0 0 12 11" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M6 0.5 11.5 10.5H0.5Z" fill={fill} />
    </svg>
  )
}

export function OpenIcon({ color = '#F5F5F7' }: { color?: string }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M4 2.5h5.5V8M9.5 2.5 2.5 9.5" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function PauseIcon({ color = '#F5F5F7' }: { color?: string }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <rect x="2.5" y="2" width="2.6" height="8" rx="0.8" fill={color} />
      <rect x="6.9" y="2" width="2.6" height="8" rx="0.8" fill={color} />
    </svg>
  )
}

export function PlayIcon({ color = '#F5F5F7' }: { color?: string }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M3.5 2.5a.6.6 0 0 1 .9-.5l5.2 3.5a.6.6 0 0 1 0 1L4.4 10a.6.6 0 0 1-.9-.5v-7Z" fill={color} />
    </svg>
  )
}

export function BackIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
      <path d="M8.5 3 4.5 7l4 4" fill="none" stroke={stroke(60)} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function Chevron({ direction }: { direction: 'down' | 'right' }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d={direction === 'down' ? 'M3 4.5 6 7.5l3-3' : 'M4.5 3 7.5 6l-3 3'}
        fill="none"
        stroke={stroke(50)}
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function AppleIcon() {
  return (
    <svg width="14" height="16" viewBox="0 0 14 16" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d="M11.6 8.5c0-2 1.6-2.9 1.7-3-.9-1.3-2.3-1.5-2.8-1.5-1.2-.1-2.3.7-2.9.7-.6 0-1.5-.7-2.5-.7C3.8 4 2.6 4.8 2 6c-1.4 2.4-.4 6 1 7.9.6.9 1.4 2 2.4 1.9 1-.1 1.3-.6 2.5-.6s1.5.6 2.5.6c1 0 1.7-.9 2.3-1.9.7-1.1 1-2.1 1-2.2 0 0-2-.8-2.1-3.2ZM9.7 2.6c.5-.7.9-1.6.8-2.6-.8 0-1.8.5-2.4 1.2-.5.6-1 1.6-.8 2.5.9.1 1.8-.4 2.4-1.1Z"
        fill="currentColor"
      />
    </svg>
  )
}

export function GitHubIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"
        fill="currentColor"
      />
    </svg>
  )
}

export function WifiIcon() {
  return (
    <svg width="17" height="12" viewBox="0 0 17 12" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d="M8.5 2.2c2.3 0 4.4.9 6 2.4l1.1-1.1C13.7 1.6 11.2.6 8.5.6S3.3 1.6 1.4 3.5l1.1 1.1c1.6-1.5 3.7-2.4 6-2.4Zm0 3.2c1.4 0 2.7.5 3.7 1.4l1.1-1.1C12 4.5 10.3 3.8 8.5 3.8S5 4.5 3.7 5.7l1.1 1.1c1-.9 2.3-1.4 3.7-1.4Zm0 3.2c.6 0 1.1.2 1.5.5L8.5 10.6 7 9.1c.4-.3.9-.5 1.5-.5Z"
        fill="#FFFFFF"
      />
    </svg>
  )
}

export function BatteryIcon() {
  return (
    <svg width="25" height="12" viewBox="0 0 25 12" aria-hidden style={{ flexShrink: 0 }}>
      <rect x="0.5" y="0.5" width="21" height="11" rx="3.5" fill="none" stroke="#FFFFFF80" />
      <rect x="2" y="2" width="15" height="8" rx="2" fill="#FFFFFF" />
      <path d="M23 4v4c.8-.3 1.3-1.1 1.3-2S23.8 4.3 23 4Z" fill="#FFFFFF80" />
    </svg>
  )
}

'use client'

import { useEffect, useState } from 'react'
import styles from './landing.module.css'

// The 5×5 mark as a tiny display, cycling through the glyphs from the "08 · 5×5 dot grid" board.
// '#' lit white, 'a' lit amber, '.' off.
const GLYPHS: Record<string, string[]> = {
  colon: ['.....', '..#..', '.....', '..#..', '.....'],
  W: ['#...#', '#...#', '#.#.#', '#.#.#', '.#.#.'],
  T: ['#####', '..#..', '..#..', '..#..', '..#..'],
  P: ['####.', '#...#', '####.', '#....', '#....'],
  question: ['.###.', '#...#', '..##.', '.....', '..#..'],
  bang: ['..a..', '..a..', '..a..', '.....', '..a..'],
  questionBang: ['##..a', '..#.a', '.#..a', '.....', '.#..a'],
  line: ['....#', '...#.', '.#...', '#.#..', '.....'],
  bars: ['....#', '...##', '.#.##', '.####', '#####'],
  count: ['#####', '#....', '####.', '....#', '####.'],
  leak: ['....a', '...a.', '..#..', '.#...', '#....'],
  alert: ['aaaaa', 'aa.aa', 'aaaaa', 'aa.aa', 'aaaaa'],
  H: ['#...#', '#...#', '#####', '#...#', '#...#'],
  A: ['.###.', '#...#', '#####', '#...#', '#...#'],
  N: ['#...#', '##..#', '#.#.#', '#..##', '#...#'],
  K: ['#...#', '#..#.', '###..', '#..#.', '#...#'],
  Y: ['#...#', '.#.#.', '..#..', '..#..', '..#..'],
  O: ['.###.', '#...#', '#...#', '#...#', '.###.'],
  U: ['#...#', '#...#', '#...#', '#...#', '.###.'],
}

type Sequence = [glyph: keyof typeof GLYPHS, hold: number][]

// Colon at rest, spell the name, then show off what the grid can say.
const SEQUENCE: Sequence = [
  ['colon', 1600],
  ['W', 700],
  ['T', 700],
  ['P', 700],
  ['colon', 1200],
  ['line', 900],
  ['bars', 900],
  ['count', 900],
  ['leak', 900],
  ['alert', 1000],
  ['question', 800],
  ['bang', 800],
  ['questionBang', 1000],
]

// The tip jar's thank-you page.
export const THANK_YOU: Sequence = [
  ['colon', 1200],
  ...(['T', 'H', 'A', 'N', 'K', 'Y', 'O', 'U'] as const).map((letter): Sequence[number] => [letter, 600]),
]

const COLORS = { '#': '#F5F5F7', a: '#FFB224', '.': '#F5F5F71F' } as const

export function DotMatrix({
  size = 216,
  playing = true,
  sequence = SEQUENCE,
}: {
  size?: number
  playing?: boolean
  sequence?: Sequence
}) {
  const [step, setStep] = useState(0)

  useEffect(() => {
    if (!playing) {
      setStep(0)
      return
    }
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const timer = setTimeout(() => setStep((s) => (s + 1) % sequence.length), sequence[step][1])
    return () => clearTimeout(timer)
  }, [step, playing, sequence])

  const rows = GLYPHS[sequence[step][0]]

  return (
    <svg className={styles.dotMatrix} width={size} height={size} viewBox="0 0 216 216" aria-hidden>
      {rows.map((row, y) =>
        row.split('').map((cell, x) => (
          <circle
            key={`${x}-${y}`}
            cx={20 + x * 44}
            cy={20 + y * 44}
            r={14}
            data-lit={cell !== '.'}
            style={{ fill: COLORS[cell as keyof typeof COLORS], transitionDelay: `${x * 45}ms` }}
          />
        )),
      )}
    </svg>
  )
}

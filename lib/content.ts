import fs from 'node:fs'
import path from 'node:path'
import { Marked } from 'marked'

// The site's written content lives in content/ as Markdown, so the same source
// renders the HTML pages and the .md versions that agents read (/index.md,
// /guides/<slug>.md, /llms.txt, /llms-full.txt).

export const SITE_URL = 'https://whattheport.dev'
export const SITE_NAME = 'WhatThePort'
export const SITE_TITLE = 'WhatThePort: see every dev server and port on your Mac'
export const SITE_DESCRIPTION =
  'A free, open-source macOS menu bar app that shows what’s running on localhost: every dev server’s port, project, git branch, memory and the Claude Code, Codex or Conductor session that started it. Stop the ones you forgot in one click.'
export const AUTHOR = { name: 'Tom John', url: 'https://tomjohn.design' }
export const GITHUB_URL = 'https://github.com/tomjohndesign/what-the-port'
export const OG_IMAGE = {
  url: '/og-image.png',
  width: 1200,
  height: 630,
  alt: 'What the port?! Your dev servers, in the menu bar. WhatThePort server list on an amber background.',
}

const CONTENT = path.join(process.cwd(), 'content')

export type Guide = {
  slug: string
  title: string
  description: string
  published: string
  updated: string
  order: number
  keywords: string[]
  markdown: string
}

// A small frontmatter block of `key: value` lines between --- fences.
function parse(file: string) {
  const source = fs.readFileSync(file, 'utf8')
  const match = source.match(/^---\n([\s\S]*?)\n---\n+([\s\S]*)$/)
  if (!match) return { data: {} as Record<string, string>, body: source }
  const data: Record<string, string> = {}
  for (const line of match[1].split('\n')) {
    const colon = line.indexOf(':')
    if (colon > 0) data[line.slice(0, colon).trim()] = line.slice(colon + 1).trim()
  }
  return { data, body: match[2] }
}

export function getGuides(): Guide[] {
  const dir = path.join(CONTENT, 'guides')
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .map((name) => {
      const { data, body } = parse(path.join(dir, name))
      return {
        slug: name.replace(/\.md$/, ''),
        title: data.title,
        description: data.description,
        published: data.published,
        updated: data.updated || data.published,
        order: Number(data.order) || 99,
        keywords: (data.keywords || '').split(',').map((k) => k.trim()).filter(Boolean),
        markdown: body.trim(),
      }
    })
    .sort((a, b) => a.order - b.order || a.title.localeCompare(b.title))
}

export function getGuide(slug: string) {
  return getGuides().find((guide) => guide.slug === slug)
}

// The product overview agents get at /index.md and at the top of /llms-full.txt.
export function getOverview() {
  return fs.readFileSync(path.join(CONTENT, 'whattheport.md'), 'utf8').trim()
}

const slugify = (text: string) =>
  text
    .toLowerCase()
    .replace(/<[^>]+>|&[a-z0-9#]+;/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')

// Headings get ids so sections can be linked to directly.
const marked = new Marked({
  gfm: true,
  renderer: {
    heading({ tokens, depth }) {
      const html = this.parser.parseInline(tokens)
      return `<h${depth} id="${slugify(html)}">${html}</h${depth}>\n`
    },
  },
})

export function renderMarkdown(markdown: string) {
  return marked.parse(markdown, { async: false })
}

// A rough reading time, at 220 words a minute.
export function readingMinutes(markdown: string) {
  return Math.max(1, Math.round(markdown.split(/\s+/).length / 220))
}

// The article as a standalone Markdown document, with its canonical URL.
export function guideMarkdown(guide: Guide) {
  return [
    `# ${guide.title}`,
    `> ${guide.description}`,
    `Canonical: ${SITE_URL}/guides/${guide.slug} · Updated ${guide.updated}`,
    guide.markdown,
  ].join('\n\n')
}

// The app version from the Mac app's Info.plist, when the source is present at build time.
export function appVersion() {
  try {
    const plist = fs.readFileSync(path.join(process.cwd(), 'WhatThePort/Info.plist'), 'utf8')
    return plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1]
  } catch {
    return undefined
  }
}

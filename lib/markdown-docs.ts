import { SITE_DESCRIPTION, SITE_URL, getGuides, getOverview, guideMarkdown } from './content'

// Plain-text versions of the site for agents and LLMs. Served at /index.md,
// /guides.md, /guides/<slug>.md (see middleware.ts), /llms.txt and /llms-full.txt.

export function guidesIndexMarkdown() {
  return [
    '# WhatThePort guides',
    '> Practical guides to ports, dev servers and coding agents on macOS.',
    ...getGuides().map((guide) => `- [${guide.title}](${SITE_URL}/guides/${guide.slug}.md): ${guide.description}`),
  ].join('\n\n')
}

// Every Markdown document, keyed by its path under /md.
export function markdownDocs() {
  const docs = new Map<string, { markdown: string; canonical: string }>()
  docs.set('index', { markdown: getOverview(), canonical: SITE_URL })
  docs.set('guides', { markdown: guidesIndexMarkdown(), canonical: `${SITE_URL}/guides` })
  for (const guide of getGuides()) {
    docs.set(`guides/${guide.slug}`, { markdown: guideMarkdown(guide), canonical: `${SITE_URL}/guides/${guide.slug}` })
  }
  return docs
}

// https://llmstxt.org
export function llmsTxt() {
  const guides = getGuides()
  return `# WhatThePort

> ${SITE_DESCRIPTION}

WhatThePort is a native Swift menu bar app for Apple Silicon Macs on macOS 14 or later. It's free, open source (MIT) and needs no account. It also installs a \`wtp\` terminal command; \`wtp list --json\` prints every running dev server (port, url, pid, name, branch, framework, folder, command, memory, CPU, status and the agent session that started it) for scripts and coding agents.

Every page on this site is also available as Markdown: add \`.md\` to its URL, or request it with \`Accept: text/markdown\`.

## Product

- [WhatThePort overview](${SITE_URL}/index.md): features, install, the wtp command and its JSON output, how it works, privacy and FAQ
- [Download for macOS](${SITE_URL}/WhatThePort.dmg): the latest signed release, as a disk image
- [Source code on GitHub](https://github.com/tomjohndesign/what-the-port): README, Swift source and releases

## Guides

${guides.map((guide) => `- [${guide.title}](${SITE_URL}/guides/${guide.slug}.md): ${guide.description}`).join('\n')}

## Optional

- [Everything in one file](${SITE_URL}/llms-full.txt): the overview and every guide, concatenated
`
}

export function llmsFullTxt() {
  return [getOverview(), ...getGuides().map(guideMarkdown)].join('\n\n---\n\n') + '\n'
}

export function markdownResponse(body: string, canonical?: string) {
  const headers: Record<string, string> = {
    'content-type': 'text/markdown; charset=utf-8',
    'cache-control': 'public, max-age=0, must-revalidate',
  }
  // Search engines index the HTML page, not its Markdown copy.
  if (canonical) headers.link = `<${canonical}>; rel="canonical"`
  return new Response(body, { headers })
}

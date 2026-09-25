import { AUTHOR, GITHUB_URL, SITE_DESCRIPTION, SITE_NAME, SITE_URL, appVersion, type Guide } from './content'

// schema.org JSON-LD, so search engines and agents can read what the site is about
// without interpreting the interactive demo.

const author = { '@type': 'Person', name: AUTHOR.name, url: AUTHOR.url }

export function softwareApplication() {
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    '@id': `${SITE_URL}/#app`,
    name: SITE_NAME,
    alternateName: ['What The Port', 'wtp'],
    description: SITE_DESCRIPTION,
    url: SITE_URL,
    downloadUrl: `${SITE_URL}/WhatThePort.dmg`,
    installUrl: `${SITE_URL}/WhatThePort.dmg`,
    image: `${SITE_URL}/og-image.png`,
    screenshot: `${SITE_URL}/screenshot.png`,
    softwareVersion: appVersion(),
    applicationCategory: 'DeveloperApplication',
    applicationSubCategory: 'Menu bar utility',
    operatingSystem: 'macOS 14 or later',
    processorRequirements: 'Apple Silicon',
    isAccessibleForFree: true,
    license: 'https://opensource.org/licenses/MIT',
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    author,
    sameAs: [GITHUB_URL],
    featureList: [
      'Lists every local dev server with its port, project, git branch, uptime, memory and CPU',
      'Links servers to the Claude Code, Codex or Conductor session that started them',
      'Memory leak alerts at 2 GB or 500 MB growth in ten minutes',
      'Clean up stops idle servers and servers from deleted git worktrees',
      'Stops and restarts whole process trees',
      'wtp terminal UI and wtp list --json for scripts and agents',
      'Global shortcut ⌥⌘P',
    ],
  }
}

export function website() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    '@id': `${SITE_URL}/#website`,
    name: SITE_NAME,
    url: SITE_URL,
    description: SITE_DESCRIPTION,
    publisher: author,
  }
}

export function article(guide: Guide) {
  const url = `${SITE_URL}/guides/${guide.slug}`
  return [
    {
      '@context': 'https://schema.org',
      '@type': 'TechArticle',
      headline: guide.title,
      description: guide.description,
      keywords: guide.keywords.join(', '),
      datePublished: guide.published,
      dateModified: guide.updated,
      url,
      mainEntityOfPage: url,
      image: `${SITE_URL}/og-image.png`,
      author,
      publisher: author,
      about: { '@id': `${SITE_URL}/#app` },
      isPartOf: { '@id': `${SITE_URL}/#website` },
      encoding: { '@type': 'MediaObject', encodingFormat: 'text/markdown', contentUrl: `${url}.md` },
    },
    breadcrumbs([
      ['Guides', `${SITE_URL}/guides`],
      [guide.title, url],
    ]),
  ]
}

export function breadcrumbs(items: [string, string][]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [['WhatThePort', SITE_URL], ...items].map(([name, item], index) => ({
      '@type': 'ListItem',
      position: index + 1,
      name,
      item,
    })),
  }
}

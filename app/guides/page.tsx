import type { Metadata } from 'next'
import styles from './guides.module.css'
import { JsonLd } from '../components/JsonLd'
import { OG_IMAGE, SITE_NAME, SITE_URL, getGuides } from '@/lib/content'
import { breadcrumbs } from '@/lib/structured-data'

const title = 'Guides: ports, dev servers and coding agents on macOS'
const description =
  'Practical guides to finding what’s running on localhost, fixing “port already in use” and EADDRINUSE, cleaning up dev servers left by Claude Code and Codex, and keeping memory in check on a Mac.'

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: '/guides', types: { 'text/markdown': '/guides.md' } },
  openGraph: { title, description, url: '/guides', type: 'website', siteName: SITE_NAME, images: [OG_IMAGE] },
  twitter: { card: 'summary_large_image', title, description, images: [OG_IMAGE] },
}

export default function GuidesIndex() {
  const guides = getGuides()
  return (
    <>
      <JsonLd
        data={[
          breadcrumbs([['Guides', `${SITE_URL}/guides`]]),
          {
            '@context': 'https://schema.org',
            '@type': 'ItemList',
            itemListElement: guides.map((guide, index) => ({
              '@type': 'ListItem',
              position: index + 1,
              url: `${SITE_URL}/guides/${guide.slug}`,
              name: guide.title,
            })),
          },
        ]}
      />
      <div className={styles.intro}>
        <h1 className={styles.title}>Guides</h1>
        <p className={styles.lede}>{description}</p>
      </div>
      <ol className={styles.index}>
        {guides.map((guide) => (
          <li key={guide.slug}>
            <a className={styles.indexLink} href={`/guides/${guide.slug}`}>
              <span className={styles.indexTitle}>{guide.title}</span>
              <span className={styles.indexDescription}>{guide.description}</span>
            </a>
          </li>
        ))}
      </ol>
    </>
  )
}

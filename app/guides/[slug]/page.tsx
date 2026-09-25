import type { Metadata } from 'next'
import { notFound } from 'next/navigation'
import styles from '../guides.module.css'
import { DownloadButton, TrackDownloads } from '../Chrome'
import { JsonLd } from '../../components/JsonLd'
import { OG_IMAGE, SITE_NAME, getGuide, getGuides, readingMinutes, renderMarkdown } from '@/lib/content'
import { article } from '@/lib/structured-data'

type Props = { params: { slug: string } }

export const dynamicParams = false

export function generateStaticParams() {
  return getGuides().map((guide) => ({ slug: guide.slug }))
}

export function generateMetadata({ params }: Props): Metadata {
  const guide = getGuide(params.slug)
  if (!guide) return {}
  const url = `/guides/${guide.slug}`
  return {
    title: guide.title,
    description: guide.description,
    keywords: guide.keywords,
    alternates: { canonical: url, types: { 'text/markdown': `${url}.md` } },
    openGraph: {
      title: guide.title,
      description: guide.description,
      url,
      type: 'article',
      publishedTime: guide.published,
      modifiedTime: guide.updated,
      siteName: SITE_NAME,
      images: [OG_IMAGE],
    },
    twitter: { card: 'summary_large_image', title: guide.title, description: guide.description, images: [OG_IMAGE] },
  }
}

const formatDate = (date: string) =>
  new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(date))

export default function GuidePage({ params }: Props) {
  const guide = getGuide(params.slug)
  if (!guide) notFound()
  const more = getGuides().filter((other) => other.slug !== guide.slug)

  return (
    <>
      <JsonLd data={article(guide)} />
      <TrackDownloads location={`guide:${guide.slug}`} />
      <article className={styles.article}>
        <header className={styles.articleHeader}>
          <nav className={styles.crumbs} aria-label="Breadcrumb">
            <a href="/guides">Guides</a>
          </nav>
          <h1 className={styles.title}>{guide.title}</h1>
          <p className={styles.lede}>{guide.description}</p>
          <p className={styles.meta}>
            <time dateTime={guide.updated}>{formatDate(guide.updated)}</time> · {readingMinutes(guide.markdown)} min
            read
          </p>
        </header>
        <div className={styles.prose} dangerouslySetInnerHTML={{ __html: renderMarkdown(guide.markdown) }} />
      </article>

      <aside className={styles.cta}>
        <div>
          <p className={styles.ctaTitle}>Every dev server on your Mac, in the menu bar.</p>
          <p className={styles.ctaMeta}>Free and open source · macOS 14 or later · No account</p>
        </div>
        <DownloadButton location={`guide-cta:${guide.slug}`} />
      </aside>

      <nav className={styles.more} aria-label="More guides">
        <h2 className={styles.moreTitle}>More guides</h2>
        <ul className={styles.index}>
          {more.map((other) => (
            <li key={other.slug}>
              <a className={styles.indexLink} href={`/guides/${other.slug}`}>
                <span className={styles.indexTitle}>{other.title}</span>
              </a>
            </li>
          ))}
        </ul>
      </nav>
    </>
  )
}

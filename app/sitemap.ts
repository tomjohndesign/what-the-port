import type { MetadataRoute } from 'next'
import { SITE_URL, getGuides } from '@/lib/content'

export default function sitemap(): MetadataRoute.Sitemap {
  const guides = getGuides()
  const latest = guides.map((guide) => guide.updated).sort().at(-1)
  return [
    { url: SITE_URL, changeFrequency: 'weekly', priority: 1 },
    { url: `${SITE_URL}/guides`, lastModified: latest, changeFrequency: 'weekly', priority: 0.8 },
    ...guides.map((guide) => ({
      url: `${SITE_URL}/guides/${guide.slug}`,
      lastModified: guide.updated,
      changeFrequency: 'monthly' as const,
      priority: 0.7,
    })),
  ]
}

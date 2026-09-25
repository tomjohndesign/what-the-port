import type { MetadataRoute } from 'next'
import { SITE_URL } from '@/lib/content'

// Everyone, including AI crawlers and agents, is welcome. /usage/ is the Mac app's
// anonymous feature counter and /md/ is the internal path behind the .md URLs.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: '*', allow: '/', disallow: ['/usage/', '/md/'] },
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  }
}

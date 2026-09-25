import { notFound } from 'next/navigation'
import { markdownDocs, markdownResponse } from '@/lib/markdown-docs'

// Markdown copies of each page. middleware.ts rewrites /index.md, /guides.md and
// /guides/<slug>.md here, and so do requests that ask for text/markdown.

export const dynamicParams = false

export function generateStaticParams() {
  return Array.from(markdownDocs().keys()).map((key) => ({ path: key.split('/') }))
}

export function GET(_request: Request, { params }: { params: { path: string[] } }) {
  const doc = markdownDocs().get(params.path.join('/'))
  if (!doc) notFound()
  return markdownResponse(doc.markdown + '\n', doc.canonical)
}

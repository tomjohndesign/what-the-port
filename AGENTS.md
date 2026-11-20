# The download is always the latest release

Never commit `public/WhatThePort.dmg`, `public/updates/` or `public/release.json`. The deploy workflow builds them when it releases the app and carries them over from production otherwise, and `scripts/check-download.mjs` fails production builds whose download isn't the published release. Local dev and previews redirect the download to production. Don't link a versioned archive such as `/updates/WhatThePort-4.zip` from the site or README; always link `/WhatThePort.dmg`.

# The app releases once a day

Each merge to `main` deploys the website straight away, but reuses the published app. A daily run at 10:00 UTC releases a new app version only if `WhatThePort/` (other than its tests and docs) changed since the last release, so a day's merges reach installed copies as one update. Until then, the marketing demo can show app changes a day before the download has them. To release sooner, run the deploy workflow with **Release a new app version now**. `scripts/set-release-version.mjs` sets the numbers during the release, so don't bump `CFBundleVersion` by hand. Change `CFBundleShortVersionString` in `WhatThePort/Info.plist` only to start a new major or minor version. See `WhatThePort/UPDATES.md`.

# Keep the marketing demo in sync with the product

The native macOS app is the source of truth for product UI and behavior. Whenever a change affects a screen, control, label, visual style, or interaction represented on the marketing website, update the website in the **same change**. Do not leave the marketing demo showing an older version of the product.

- Compare `WhatThePort/Sources/WhatThePort/UI/` (especially `ServersView.swift`, `ServerDetailView.swift`, `Components.swift`, and `Theme.swift`) with `app/components/App.tsx`, `icons.tsx`, `servers.ts`, and `landing.module.css`.
- Mirror layout, typography, colors, formatting, states, and interactions. Keep demo data deterministic and external/destructive actions simulated; never operate on the visitor's real processes or sessions.
- Update affected marketing copy in `Copy.tsx` and `README.md`, the product overview agents read in `content/whattheport.md` (served as `/index.md` and in `/llms.txt`), and any guide in `content/guides/` that describes the changed behavior. Refresh affected product screenshots in `docs/images/` and any referenced product images in `public/` when their depicted UI changes. Do not replace unrelated artwork or rebuild the downloadable app for a demo-only change.
- Verify every affected demo view and interaction in a browser on desktop and mobile, check for console errors, and run `npm run build`. Save review screenshots in `.context/`.
- If a product change has no marketing equivalent, state that briefly in the change description instead of inventing a new marketing screen.

# Guides and agent-readable pages

Articles live in `content/guides/*.md` (frontmatter: `title`, `description`, `published`, `updated`, `order`, `keywords`) and render at `/guides/<slug>`. Every page is also served as Markdown (`/index.md`, `/guides.md`, `/guides/<slug>.md`, or any page with `Accept: text/markdown`), and listed in `/llms.txt`, `/llms-full.txt` and `/sitemap.xml`, all generated from `content/`. Test every shell command in a guide on a Mac before publishing it, and keep claims about WhatThePort in line with the app's defaults in `Preferences.swift` and `ServerMonitor.swift`.

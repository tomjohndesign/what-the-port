# The download is always the latest release

Never commit `public/WhatThePort.zip` or `public/updates/`. The deploy workflow builds them for each production deploy, and `scripts/check-download.mjs` fails production builds whose download isn't this commit's release. Local dev and previews redirect the download to production. Don't link a versioned archive such as `/updates/WhatThePort-4.zip` from the site or README; always link `/WhatThePort.zip`.

# Keep the marketing demo in sync with the product

The native macOS app is the source of truth for product UI and behavior. Whenever a change affects a screen, control, label, visual style, or interaction represented on the marketing website, update the website in the **same change**. Do not leave the marketing demo showing an older version of the product.

- Compare `WhatThePort/Sources/WhatThePort/UI/` (especially `ServersView.swift`, `ServerDetailView.swift`, `Components.swift`, and `Theme.swift`) with `app/components/App.tsx`, `icons.tsx`, `servers.ts`, and `landing.module.css`.
- Mirror layout, typography, colors, formatting, states, and interactions. Keep demo data deterministic and external/destructive actions simulated; never operate on the visitor's real processes or sessions.
- Update affected marketing copy in `Copy.tsx` and `README.md`. Refresh affected product screenshots in `docs/images/` and any referenced product images in `public/` when their depicted UI changes. Do not replace unrelated artwork or rebuild the downloadable app for a demo-only change.
- Verify every affected demo view and interaction in a browser on desktop and mobile, check for console errors, and run `npm run build`. Save review screenshots in `.context/`.
- If a product change has no marketing equivalent, state that briefly in the change description instead of inventing a new marketing screen.

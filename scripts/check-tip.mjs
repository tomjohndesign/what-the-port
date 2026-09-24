// The app's tip jar opens whattheport.dev/tip, which redirects to TIP_URL.
// Production must have it, or the redirect would point back at itself.
const production = process.env.VERCEL_ENV === 'production' || process.env.VERCEL_TARGET_ENV === 'production'
if (!production) process.exit(0)

const value = process.env.TIP_URL ?? ''
let url
try {
  url = new URL(value)
} catch {}
if (url?.protocol !== 'https:' || url.hostname === 'whattheport.dev') {
  console.error(`check-tip: TIP_URL must be an https link to the payment page${value ? `, not ${value}` : ''}.`)
  console.error('Add your Stripe Payment Link as TIP_URL in the Vercel project’s production environment. See README.md.')
  process.exit(1)
}
console.log(`check-tip: /tip goes to ${url.host}.`)

export const DOWNLOAD_URL = '/WhatThePort.dmg'
export const GITHUB_URL = 'https://github.com/tomjohndesign/what-the-port'

// One entry per scroll step. `scene` is the room the laptop sits in while this
// section is on screen; `menu` is its label in the fake menu bar; `logo` is the
// logo colour that stands out against that room's (deliberately plain) top centre.
export const SECTIONS = [
  { id: 'servers', menu: 'Servers', scene: 'house', logo: 'dark' },
  { id: 'sessions', menu: 'Sessions', scene: 'coffee-shop', logo: 'light' },
  { id: 'leaks', menu: 'Leaks', scene: 'home-office', logo: 'light' },
  { id: 'clean-up', menu: 'Clean up', scene: 'coworking', logo: 'light' },
  { id: 'get-it', menu: 'Download', scene: 'corporate-office', logo: 'light' },
] as const

export const LEAKS = 2
export const GET_IT = SECTIONS.length - 1

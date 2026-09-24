export const DOWNLOAD_URL = '/WhatThePort.zip'
export const GITHUB_URL = 'https://github.com/tomjohndesign/what-the-port'

// One entry per scroll step. `scene` is the room the laptop sits in while this
// section is on screen; `menu` is its label in the fake menu bar.
export const SECTIONS = [
  { id: 'servers', menu: 'Servers', scene: 'house' },
  { id: 'sessions', menu: 'Sessions', scene: 'coffee-shop' },
  { id: 'leaks', menu: 'Leaks', scene: 'home-office' },
  { id: 'clean-up', menu: 'Clean up', scene: 'coworking' },
  { id: 'get-it', menu: 'Download', scene: 'corporate-office' },
] as const

export const LEAKS = 2
export const GET_IT = SECTIONS.length - 1

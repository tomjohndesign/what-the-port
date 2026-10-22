'use client'

import { useEffect } from 'react'
import styles from '../guides/guides.module.css'
import { OpenIcon } from '../components/icons'

// The app handles whattheport://tipped by never showing its tip reminder again.
// Browsers ask before opening it, so the button is there if that's dismissed.
const TIPPED_URL = 'whattheport://tipped'

export function OpenApp() {
  useEffect(() => {
    window.location.href = TIPPED_URL
  }, [])
  return (
    <a className={`${styles.download} ${styles.openApp}`} href={TIPPED_URL}>
      Open WhatThePort
      <OpenIcon color="currentColor" />
    </a>
  )
}

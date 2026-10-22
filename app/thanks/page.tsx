import type { Metadata } from 'next'
import styles from '../guides/guides.module.css'
import { Footer, Header } from '../guides/Chrome'
import { DotMatrix, THANK_YOU } from '../components/DotMatrix'
import { OpenApp } from './OpenApp'

// Stripe sends tippers here after paying (see README.md). The page hands the
// tip to the app, which stops its monthly tip reminder.

export const metadata: Metadata = {
  title: 'Thanks for the tip',
  robots: { index: false, follow: false },
}

export default function Thanks() {
  return (
    <div className={styles.page}>
      <Header />
      <main className={`${styles.main} ${styles.thanks}`}>
        <DotMatrix size={160} sequence={THANK_YOU} />
        <div className={styles.intro}>
          <h1 className={styles.title}>Thanks for the tip</h1>
          <p className={styles.lede}>
            Click this button to stop the monthly tip notification.
          </p>
        </div>
        <OpenApp />
      </main>
      <Footer />
    </div>
  )
}

import styles from './guides.module.css'
import { Footer, Header } from './Chrome'

export default function GuidesLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={styles.page}>
      <Header />
      <main className={styles.main}>{children}</main>
      <Footer />
    </div>
  )
}

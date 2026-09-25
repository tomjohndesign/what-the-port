import Landing from './components/Landing'
import { JsonLd } from './components/JsonLd'
import { softwareApplication, website } from '@/lib/structured-data'

export default function Home() {
  return (
    <>
      <JsonLd data={[softwareApplication(), website()]} />
      <Landing />
    </>
  )
}

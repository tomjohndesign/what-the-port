// Run with Node 24, the version used by the deploy workflow.
import assert from 'node:assert/strict'
import { SERVERS, SESSION_METADATA_LABELS, serverResources, stoppedPorts } from '../app/components/servers.ts'

const copilot = SERVERS.find(server => server.session?.agent === 'copilot')
assert(copilot, 'The demo must represent the Copilot integration')
assert.match(copilot.session.id, /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i)
assert.equal(copilot.session.metadataState, 'unavailable', 'The minimal Copilot fixture has no workspace metadata')
for (const server of SERVERS.filter(server => server.session)) {
  assert.equal(server.session.metadataState, server.session.agent === 'copilot' ? 'unavailable' : 'available')
}
assert.deepEqual(SESSION_METADATA_LABELS, { available: 'Available', unavailable: 'Unavailable', limited: 'Limited' })

for (const server of SERVERS) {
  const resources = serverResources([server])
  assert.equal(resources.memory, server.memory, `Memory mismatch on :${server.port}`)
  assert.equal(resources.cpu, server.cpu, `CPU mismatch on :${server.port}`)
}
const original = SERVERS[0]
const shared = { ...original, port: '3200' }
const sibling = SERVERS[1]
const rows = [original, shared, sibling]
const resources = serverResources(rows)
assert.equal(resources.memory, original.memory + sibling.memory)
assert.equal(resources.cpu, original.cpu + sibling.cpu)
assert.equal(resources.memoryByPort.get(original.port), original.memory / 2)
assert.equal(resources.memoryByPort.get(shared.port), original.memory / 2)
assert.equal([...resources.memoryByPort.values()].reduce((a, b) => a + b, 0), resources.memory)
assert.deepEqual(stoppedPorts(rows, [original.port]), [original.port, shared.port])
assert.deepEqual(stoppedPorts(rows, [sibling.port]), [sibling.port])
assert.equal(serverResources([original, shared]).memory, original.memory)
assert.equal(serverResources([]).memory, 0)
assert.deepEqual(stoppedPorts(rows, []), [])
console.log('Demo resources: session metadata, shared-port totals, CPU, bar shares, and stop isolation passed.')

// Run with Node 24, the version used by the deploy workflow.
import assert from 'node:assert/strict'
import { SERVERS, serverResources, stoppedPorts } from '../app/components/servers.ts'

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
console.log('Demo resources: shared-port totals, CPU, bar shares, and stop isolation passed.')

import { defineWebSocketHandler } from 'h3'

const topic = 'lifebuoy-light'
const maxBytes = 64 * 1024

export default defineWebSocketHandler({
  open(peer) {
    peer.subscribe(topic)
  },
  message(peer, message) {
    if (message.uint8Array().byteLength > maxBytes) {
      peer.close(1009, 'Packet too large')
      return
    }
    const text = message.text()
    let packet: unknown
    try {
      packet = JSON.parse(text)
    } catch {
      return
    }
    if (!packet || typeof packet !== 'object' || Array.isArray(packet)) return
    const { kind, app } = packet as Record<string, unknown>
    if (typeof kind !== 'string' || !kind.startsWith('aieco.light.') ||
        (app !== undefined && typeof app !== 'string')) return
    peer.publish(topic, text)
  },
})

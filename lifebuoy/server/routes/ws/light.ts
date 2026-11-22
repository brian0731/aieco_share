import { defineWebSocketHandler } from 'h3'
import { database } from '../../utils/database'
import { chatFingerprint, contentAllowed, removedChatKeys } from '../../utils/moderation'
import { relayMayPublish } from '../../utils/member-chat'

const topic = 'lifebuoy-light'
const maxBytes = 64 * 1024

export default defineWebSocketHandler({
  open(peer) {
    peer.subscribe(topic)
  },
  async message(peer, message) {
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
    const { kind, app, messageId, senderId, senderName, senderUserName, text: content } = packet as Record<string, unknown>
    if (typeof kind !== 'string' || !kind.startsWith('aieco.light.') ||
        (app !== undefined && typeof app !== 'string')) return
    if (kind === 'aieco.light.chat.v1') {
      if (typeof messageId !== 'string' || !messageId.trim() || messageId.length > 128 ||
          typeof senderId !== 'string' || !senderId.trim() || senderId.length > 128 ||
          typeof content !== 'string' || !content.trim() ||
          !contentAllowed(content, String(senderName ?? ''), String(senderUserName ?? ''))) return
      const key = chatFingerprint(messageId, senderId, content)
      try {
        const db = database()
        if (!await relayMayPublish(db, senderId.trim(), messageId.trim(), key) ||
            (await removedChatKeys(db, [key])).length) return
      } catch {
        peer.close(1011, 'Chat moderation unavailable')
        return
      }
    }
    peer.publish(topic, text)
  },
})

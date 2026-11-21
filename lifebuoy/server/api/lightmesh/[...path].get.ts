import { getQuery, getRouterParam, setResponseHeader } from 'h3'
import { normalizeRelay } from '../../../shared/lightmesh-registry.mjs'
import { database, fail, rows } from '../../utils/database'

export default defineEventHandler(async event => {
  const path = getRouterParam(event, 'path')
  setResponseHeader(event, 'Cache-Control', 'no-store')
  if (path === 'health') {
    await lookup('SELECT code FROM lightmesh_networks LIMIT 1')
    return { ok: true, service: 'lightmesh-network-directory' }
  }
  if (path === 'networks') {
    const relay = normalizeRelay(getQuery(event).relay)
    if (!relay) fail(400, 'invalid_relay')
    const [network] = await lookup('SELECT code FROM lightmesh_networks WHERE relay=?', [relay])
    if (!network) fail(404, 'network_not_found')
    return network
  }
  const match = /^networks\/([^/]+)$/.exec(path ?? '')
  if (!match) fail(404, 'unknown_route')
  const code = match[1]
  if (!/^[0-9]{6}$/.test(code)) fail(400, 'invalid_code')
  const [network] = await lookup('SELECT code,relay FROM lightmesh_networks WHERE code=?', [code])
  if (!network) fail(404, 'network_not_found')
  return network

  async function lookup(sql: string, params: string[] = []) {
    try {
      return await rows<{ code: string, relay?: string }>(database(event), sql, params)
    } catch {
      fail(503, 'directory_unavailable')
    }
  }
})

import { expect, test, type Browser, type Page } from '@playwright/test'
import { signInAtKeycloak } from './keycloak'

const jitsiHost = process.env.E2E_JITSI_HOST
const password = process.env.E2E_USER_PASSWORD ?? ''

test.skip(!jitsiHost, 'openDesk without Jitsi (E2E_OPENDESK_JITSI=true deploys it)')

// Signs in through openDesk's Keycloak adapter (as Jitsi's own Log-in button
// does) and joins from the prejoin page, which creates the local tracks.
// p2p off: with two participants Jitsi would otherwise bypass the bridge.
async function joinRoom(browser: Browser, room: string, username: string): Promise<Page> {
  const page = await (await browser.newContext({ permissions: ['microphone', 'camera'] })).newPage()
  const hash = encodeURIComponent('config.p2p.enabled=false')
  await page.goto(`https://${jitsiHost}/oidc/auth?path=${encodeURIComponent(`/${room}`)}&search=&hash=${hash}`)
  await page.waitForURL((url) => url.hostname !== jitsiHost)
  await signInAtKeycloak(page, username, password)
  await page.waitForURL((url) => url.hostname === jitsiHost && !url.pathname.startsWith('/static/'))
  await page.getByRole('button', { name: /^join meeting$/i }).click()
  await page.waitForFunction(() => (window as any).APP?.conference?.isJoined?.())
  return page
}

function conference(page: Page) {
  return page.evaluate(async () => {
    const room = (window as any).APP.conference._room
    const pc: RTCPeerConnection | undefined = room.jvbJingleSession?.peerconnection?.peerconnection
    let audioPacketsReceived = 0
    if (pc) (await pc.getStats()).forEach((s: any) => { if (s.type === 'inbound-rtp' && s.kind === 'audio') audioPacketsReceived += s.packetsReceived })
    return {
      others: room.getParticipants().map((p: any) => p.getDisplayName()),
      localTracks: room.getLocalTracks().filter((t: any) => !t.isMuted()).map((t: any) => t.getType()),
      p2p: room.isP2PActive(),
      ice: pc?.iceConnectionState,
      audioPacketsReceived,
    }
  })
}

test('two openDesk users meet in Jitsi and hear each other through the bridge', async ({ browser }) => {
  test.setTimeout(120_000)
  const room = `e2e-${Date.now()}`
  const a = await joinRoom(browser, room, process.env.E2E_USER_USERNAME ?? '')
  const b = await joinRoom(browser, room, process.env.E2E_USER2_USERNAME ?? '')

  for (const [page, other] of [[a, 'E2E Two'], [b, 'E2E User']] as const) {
    await expect.poll(() => conference(page), { timeout: 30_000 }).toMatchObject({ others: [other], p2p: false, ice: expect.stringMatching(/^(connected|completed)$/) })
    await expect.poll(async () => (await conference(page)).localTracks, { timeout: 30_000 }).toContain('audio')
    await expect.poll(async () => (await conference(page)).audioPacketsReceived, { timeout: 30_000 }).toBeGreaterThan(0)
  }
})

import path from 'node:path'
import { chromium, expect, test, type Browser, type BrowserContext, type Page } from '@playwright/test'
import { signInAtKeycloak } from './keycloak'

// Meeting notes (synaScriber) inside openDesk: needs Jitsi, the synaScriber
// plugin, Prosody module, transcriber and a speech-to-text server deployed.
// fixtures/speech.wav (espeak-ng, German) is the first participant's microphone:
// "Guten Tag zusammen. Wir besprechen heute das Projekt Synaplan. Die Mitschrift
// wird automatisch erstellt. Das Budget beträgt zwölftausend Euro, und der
// Liefertermin ist der dritte November."
// Both sign in to Jitsi only (Keycloak); the button's sign-in to Synaplan
// has to work from there, without a Synaplan session. Synaplan is opened
// afterwards to read the transcripts.
const jitsiHost = process.env.E2E_JITSI_HOST
const synaplanHost = process.env.E2E_HOST ?? ''
const password = process.env.E2E_USER_PASSWORD ?? ''
const keywords = [/synaplan/i, /budget/i, /12\.?000|zwölftausend/i, /november/i]

test.skip(!process.env.E2E_SYNASCRIBER || !jitsiHost, 'synaScriber not deployed (E2E_SYNASCRIBER=true with Jitsi)')

const hits = (text: string) => keywords.filter((k) => k.test(text)).length

// With a Keycloak session from Jitsi the redirects go straight through and
// no Keycloak page is ever shown, so this waits for the outcome, not the hop.
async function signInSynaplan(ctx: BrowserContext, username: string) {
  const page = await ctx.newPage()
  const signedIn = async () =>
    new URL(page.url()).hostname === synaplanHost &&
    (await page.evaluate(async () => (await fetch('/api/v1/auth/me')).ok).catch(() => false))
  const form = page.locator('input[name="username"]')
  await page.goto(`https://${synaplanHost}/`)
  await expect.poll(async () => (await form.count()) > 0 || (await signedIn()), { timeout: 60_000 }).toBe(true)
  if (await form.count()) await signInAtKeycloak(page, username, password)
  await expect.poll(signedIn, { timeout: 60_000 }).toBe(true)
  return page
}

async function joinRoom(ctx: BrowserContext, room: string, username: string): Promise<Page> {
  const page = await ctx.newPage()
  const hash = encodeURIComponent('config.p2p.enabled=false')
  await page.goto(`https://${jitsiHost}/oidc/auth?path=${encodeURIComponent(`/${room}`)}&search=&hash=${hash}`)
  await page.waitForURL((url) => url.hostname !== jitsiHost)
  if (await page.locator('input[name="username"]').count()) await signInAtKeycloak(page, username, password)
  await page.waitForURL((url) => url.hostname === jitsiHost && !url.pathname.startsWith('/static/'))
  await page.getByRole('button', { name: /^join meeting$/i }).click()
  await page.waitForFunction(() => (window as any).APP?.conference?.isJoined?.())
  return page
}

// The loader renders into shadow roots; their text without the <style>.
const shadowText = (page: Page, id: string) =>
  page.evaluate((id) => {
    const root = document.getElementById(id)?.shadowRoot
    return root ? Array.from(root.children).filter((e) => e.tagName !== 'STYLE').map((e) => e.textContent ?? '').join(' ').replace(/\s+/g, ' ').trim() : ''
  }, id)

const api = (page: Page, url: string) => page.evaluate(async (url) => (await fetch(url)).json(), url)
const text = (page: Page, url: string) => page.evaluate(async (url) => (await fetch(url)).text(), url)

test('meeting notes: speech in a Jitsi room becomes a transcript in Synaplan for every participant', async () => {
  test.setTimeout(300_000)
  const browser: Browser = await chromium.launch({
    args: [
      `--host-resolver-rules=MAP *.${synaplanHost.split('.').slice(1).join('.')} ${process.env.E2E_INGRESS_IP}`,
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      `--use-file-for-fake-audio-capture=${path.join(__dirname, 'fixtures', 'speech.wav')}`,
    ],
  })
  const newContext = () => browser.newContext({ ignoreHTTPSErrors: true, permissions: ['microphone', 'camera'] })
  const ctxA = await newContext()
  const ctxB = await newContext()

  const room = `e2e-notes-${Date.now()}`
  const a = await joinRoom(ctxA, room, process.env.E2E_USER_USERNAME ?? '')
  const b = await joinRoom(ctxB, room, process.env.E2E_USER2_USERNAME ?? '')
  await b.getByRole('button', { name: /^mute microphone$/i }).click()

  const loader = a.locator('#synascriber')
  await expect(loader.locator('.pill')).toHaveText(/meeting notes/i, { timeout: 60_000 })
  await loader.locator('.pill').click()
  await loader.locator('button.primary').click()
  await expect.poll(() => shadowText(a, 'synascriber'), { timeout: 60_000 }).toMatch(/notes on/i)

  await expect.poll(async () => hits(await shadowText(b, 'synascriber-captions')), { timeout: 120_000 }).toBeGreaterThanOrEqual(2)
  await a.waitForTimeout(10_000)
  await loader.locator('button.danger').click()

  const synaplanA = await signInSynaplan(ctxA, process.env.E2E_USER_USERNAME ?? '')
  const synaplanB = await signInSynaplan(ctxB, process.env.E2E_USER2_USERNAME ?? '')
  const sessions = () => api(synaplanA, '/api/v1/plugins/synascriber/me/sessions').then((r) => r.sessions?.find((s: any) => s.room === room))
  await expect.poll(sessions, { timeout: 120_000 }).toMatchObject({ state: 'saved', recipients: 2, notDelivered: 0 })
  const session = await sessions()
  expect(session.segments).toBeGreaterThan(0)

  const transcriptA = await text(synaplanA, `/api/v1/files/${session.fileId}/content`)
  expect(hits(transcriptA)).toBeGreaterThanOrEqual(3)

  const filesB = await api(synaplanB, '/api/v1/files')
  const copyB = (filesB.files ?? filesB.data ?? filesB).find?.((f: any) => f.name === session.fileName || f.filename === session.fileName)
  expect(copyB, `B's copy of ${session.fileName} in ${JSON.stringify(filesB).slice(0, 300)}`).toBeTruthy()
  expect(hits(await text(synaplanB, `/api/v1/files/${copyB.id}/content`))).toBeGreaterThanOrEqual(3)
  await browser.close()
})

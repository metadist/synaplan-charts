import { readFileSync } from 'node:fs'
import path from 'node:path'
import { expect, test, type Page } from '@playwright/test'
import { signInAtKeycloak } from './keycloak'

// Office previews through openDesk's Collabora: the helmfile points
// office.convertUrl at it when apps.collabora.enabled. A Word upload gets a
// first-page thumbnail from the worker and exports to PDF, both through
// Collabora's convert-to. fixtures/report.docx is a one-page Word document.
const synaplanHost = process.env.E2E_HOST ?? ''
const fixture = path.join(__dirname, 'fixtures', 'report.docx')

type Probe = { status: number; type: string; head: string; size: number }

const probe = (page: Page, url: string) =>
  page.evaluate(async (url): Promise<Probe> => {
    const res = await fetch(url)
    const bytes = new Uint8Array(await res.arrayBuffer())
    return {
      status: res.status,
      type: res.headers.get('content-type') ?? '',
      head: String.fromCharCode(...bytes.slice(0, 8)),
      size: bytes.length,
    }
  }, url)

test('a Word upload gets a thumbnail and exports to PDF through Collabora', async ({ page }) => {
  test.setTimeout(180_000)
  await page.goto(`https://${synaplanHost}/`)
  await page.waitForURL((url) => url.hostname !== synaplanHost)
  await signInAtKeycloak(page, process.env.E2E_USER_USERNAME ?? '', process.env.E2E_USER_PASSWORD ?? '')
  await expect.poll(() => page.evaluate(async () => (await fetch('/api/v1/auth/me')).ok), { timeout: 60_000 }).toBe(true)

  const upload = await page.evaluate(
    async ({ b64, name }) => {
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
      const form = new FormData()
      form.append('files[]', new File([bytes], name, {
        type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      }))
      form.append('process_level', 'extract')
      const res = await fetch('/api/v1/files/upload', { method: 'POST', body: form })
      return { status: res.status, body: await res.json() }
    },
    { b64: readFileSync(fixture).toString('base64'), name: `e2e-office-${Date.now()}.docx` },
  )
  expect(upload.status, JSON.stringify(upload.body)).toBe(200)
  const id: number | undefined = upload.body.files?.[0]?.id
  expect(id, JSON.stringify(upload.body)).toBeTruthy()

  try {
    const pdf = await probe(page, `/api/v1/files/${id}/export?format=pdf`)
    expect(pdf.status, 'PDF export through Collabora').toBe(200)
    expect(pdf.head.startsWith('%PDF')).toBe(true)

    await expect
      .poll(async () => (await probe(page, `/api/v1/files/${id}/thumb`)).status, {
        message: 'thumbnail rendered by the worker through Collabora',
        timeout: 120_000,
        intervals: [2_000, 5_000],
      })
      .toBe(200)
    const thumb = await probe(page, `/api/v1/files/${id}/thumb`)
    expect(thumb.type).toMatch(/^image\//)
    expect(thumb.size).toBeGreaterThan(1_000)
  } finally {
    await page.evaluate(async (id) => { await fetch(`/api/v1/files/${id}`, { method: 'DELETE' }) }, id)
  }
})

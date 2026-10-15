import { createHmac } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { expect, test, type Page } from '@playwright/test'

const totpFile = process.env.E2E_TOTP_FILE ?? '.totp.json'
const synaplanHost = process.env.E2E_HOST ?? 'synaplan.opendesk.test'
const domain = synaplanHost.split('.').slice(1).join('.')

function totpSecrets(): Record<string, string> {
  return existsSync(totpFile) ? JSON.parse(readFileSync(totpFile, 'utf8')) : {}
}

function totp(secret: string): string {
  const counter = Buffer.alloc(8)
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30_000)))
  const digest = createHmac('sha1', Buffer.from(secret)).update(counter).digest()
  const offset = digest[digest.length - 1] & 15
  return String((digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000).padStart(6, '0')
}

async function signIn(page: Page, username: string, password: string) {
  await page.goto('/')
  await page.waitForURL((url) => url.hostname !== synaplanHost)

  await page.locator('input[name="username"]').fill(username)
  await page.locator('input[name="password"]').fill(password)
  await page.locator('input[name="password"]').press('Enter')

  const secondFactor = page.locator('input[name="totp"], input[name="otp"]')
  await Promise.race([
    secondFactor.first().waitFor(),
    page.waitForURL((url) => url.hostname === synaplanHost),
  ])

  if (new URL(page.url()).hostname !== synaplanHost) {
    if (await page.locator('input[name="totp"]').count()) {
      const secret = await page.locator('input[name="totpSecret"]').inputValue()
      writeFileSync(totpFile, JSON.stringify({ ...totpSecrets(), [username]: secret }))
      await page.locator('input[name="totp"]').fill(totp(secret))
      await page.locator('input[name="userLabel"]').fill('e2e')
      await page.locator('input[name="totp"]').press('Enter')
    } else {
      const otp = page.locator('input[name="otp"]')
      for (let attempt = 0; attempt < 2; attempt++) {
        await otp.fill(totp(totpSecrets()[username]))
        await otp.press('Enter')
        const accepted = await page
          .waitForURL((url) => url.hostname === synaplanHost, { timeout: 5_000 })
          .then(() => true, () => false)
        if (accepted) break
        await page.waitForTimeout(31_000 - (Date.now() % 30_000))
      }
    }
    await page.waitForURL((url) => url.hostname === synaplanHost)
  }

  return page.evaluate(async () => (await fetch('/api/v1/auth/me')).json())
}

test('an openDesk Domain Admin signs in through Keycloak and is administrator', async ({ page }) => {
  const me = await signIn(page, process.env.E2E_ADMIN_USERNAME ?? '', process.env.E2E_ADMIN_PASSWORD ?? '')
  expect(me.user ?? me).toMatchObject({ isAdmin: true })
})

test('an openDesk user signs in through Keycloak and is not administrator', async ({ page }) => {
  const me = await signIn(page, process.env.E2E_USER_USERNAME ?? '', process.env.E2E_USER_PASSWORD ?? '')
  expect(me.user ?? me).toMatchObject({ email: `${process.env.E2E_USER_USERNAME}@${domain}`, isAdmin: false })
})

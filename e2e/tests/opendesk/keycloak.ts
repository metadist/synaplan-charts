import type { Page } from '@playwright/test'

// Keycloak's login form, on the page it is showing. Keycloak now and then
// answers a submit with the form again (seen on CI under load); this tries
// three times and says what Keycloak showed.
export async function signInAtKeycloak(page: Page, username: string, password: string) {
  const keycloakHost = new URL(page.url()).hostname
  for (let attempt = 1; attempt <= 3; attempt++) {
    const user = page.locator('input[name="username"]')
    await user.waitFor({ timeout: 30_000 })
    await user.fill(username)
    await page.locator('input[name="password"]').fill(password)
    await page.locator('input[name="password"]').press('Enter')
    const left = await page.waitForURL((url) => url.hostname !== keycloakHost, { timeout: 30_000 }).then(() => true, () => false)
    if (left) return
    const message = await page.locator('#input-error, .pf-c-alert__title, .alert-error').first().textContent({ timeout: 1_000 }).catch(() => null)
    console.log(`keycloak: ${username} is still on ${page.url()} after attempt ${attempt}${message ? `: ${message.trim()}` : ''}`)
  }
  throw new Error(`Keycloak did not let ${username} through in three attempts`)
}

import { expect, test } from '@playwright/test'

const email = process.env.E2E_ADMIN_EMAIL ?? ''
const password = process.env.E2E_ADMIN_PASSWORD ?? ''

test('the first administrator signs in', async ({ page }) => {
  await page.goto('/login')
  await page.getByTestId('input-email').fill(email)
  await page.getByTestId('input-password').fill(password)
  await page.getByTestId('btn-login').click()
  await expect(page).not.toHaveURL(/\/login/)

  const me = await page.evaluate(async () => (await fetch('/api/v1/auth/me')).json())
  expect(me.user ?? me).toMatchObject({ email, isAdmin: true })
})

test('a wrong password is refused', async ({ page }) => {
  await page.goto('/login')
  await page.getByTestId('input-email').fill(email)
  await page.getByTestId('input-password').fill(`${password}-wrong`)
  await page.getByTestId('btn-login').click()
  await expect(page.getByTestId('alert-login-error')).toBeVisible()
  await expect(page).toHaveURL(/\/login/)
})

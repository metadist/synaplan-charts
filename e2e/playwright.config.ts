import { defineConfig } from '@playwright/test'

const host = process.env.E2E_HOST ?? 'synaplan.example.org'
const domain = host.split('.').slice(1).join('.')
const ingressIp = process.env.E2E_INGRESS_IP ?? '127.0.0.1'

export default defineConfig({
  testDir: './tests',
  timeout: 60_000,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `https://${host}`,
    ignoreHTTPSErrors: true,
    trace: 'retain-on-failure',
    launchOptions: {
      args: [`--host-resolver-rules=MAP *.${domain} ${ingressIp}`],
    },
  },
  projects: [
    { name: 'standalone', testDir: './tests/standalone' },
    { name: 'opendesk', testDir: './tests/opendesk' },
  ],
})

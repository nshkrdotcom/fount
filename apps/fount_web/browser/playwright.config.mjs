import {defineConfig, devices} from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 90_000,
  expect: {timeout: 30_000},
  retries: 0,
  reporter: [['list'], ['html', {open: 'never'}]],
  use: {
    baseURL: process.env.FOUNT_WEB_BASE_URL || 'http://127.0.0.1:4011',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    ...devices['Desktop Chrome']
  }
});

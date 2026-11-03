import { defineConfig } from '@playwright/test';

/**
 * The web app journey. It drives a running app at `APP_URL`, against the Aztec node that the app uses (the local
 * network or the testnet). Start the app first:
 *
 *     npm run build && PORT=3001 node --env-file=.env.local .output/server/index.mjs
 *     APP_URL=http://localhost:3001 npm run journey
 */
export default defineConfig({
  testDir: '.',
  testMatch: '**/*.journey.ts',
  outputDir: './test-results',
  timeout: 30 * 60_000,
  expect: { timeout: 60_000 },
  workers: 1,
  fullyParallel: false,
  // A retry sends transactions on a chain that the first attempt changed.
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: process.env.APP_URL ?? 'http://localhost:3001',
    viewport: { width: 1440, height: 1000 },
    actionTimeout: 60_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
});

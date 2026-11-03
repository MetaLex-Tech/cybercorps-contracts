import { defineConfig } from '@playwright/test';

/**
 * The PoC web app journey. It needs a local network on 8090. It starts the app on 8091, or uses one that runs.
 *
 *     aztec start --local-network --port 8090
 *     npm run journey
 */
const appUrl = 'http://localhost:8091';

export default defineConfig({
  testDir: '.',
  testMatch: '**/*.journey.ts',
  outputDir: './test-results',
  timeout: 15 * 60_000,
  expect: { timeout: 30_000 },
  workers: 1,
  fullyParallel: false,
  // A retry sends transactions on a chain that the first attempt changed.
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: appUrl,
    viewport: { width: 1440, height: 1000 },
    actionTimeout: 30_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'node app/server.ts',
    cwd: '..',
    url: `${appUrl}/api/state`,
    env: { AZTEC_NODE_URL: process.env.AZTEC_NODE_URL ?? 'http://localhost:8090', PORT: '8091' },
    reuseExistingServer: true,
    timeout: 5 * 60_000,
  },
});

import { rmSync } from 'node:fs';
import { join } from 'node:path';
import { tanstackStart } from '@tanstack/react-start/plugin/vite';
import react from '@vitejs/plugin-react';
import { nitro } from 'nitro/vite';
import { defineConfig, type Plugin, type UserConfig } from 'vite';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

// bb.js runs its prover in threads, and threads need SharedArrayBuffer, which needs cross-origin isolation.
// The prover binary for the machine that builds. Vercel builds on Linux x64.
const bbPlatform = `${process.arch === 'arm64' ? 'arm64' : 'amd64'}-${process.platform === 'darwin' ? 'macos' : 'linux'}`;

// bb.js keeps a prover binary for each platform and builds for browsers and CommonJS. The server needs one binary,
// its wasm fallback and the ES module build.
function pruneBb(serverDir: string) {
  const bb = join(serverDir, 'node_modules/@aztec-foundation/bb.js');
  for (const dir of ['amd64-linux', 'arm64-linux', 'amd64-macos', 'arm64-macos'].filter(d => d !== bbPlatform)) {
    rmSync(join(bb, 'build', dir), { recursive: true, force: true });
  }
  for (const dir of ['dest/browser', 'dest/node-cjs', 'src']) rmSync(join(bb, dir), { recursive: true, force: true });
}

// The Aztec browser packages import `buffer`, `path` and `tty`. The polyfill plugin writes its injections and
// aliases into the top-level config, which every environment reads, so this moves them under the client only.
function browserPolyfills(): Plugin {
  const plugin = nodePolyfills({ include: ['buffer', 'path', 'tty'] });
  const config = plugin.config as (this: unknown, ...args: unknown[]) => UserConfig;
  return {
    ...plugin,
    config(userConfig, env) {
      const { build, resolve, optimizeDeps } = config.call(this, userConfig, env);
      return { environments: { client: { build, resolve, optimizeDeps } } };
    },
    applyToEnvironment: environment => environment.name === 'client',
  };
}

const isolation = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
};

export default defineConfig({
  server: { port: 3000, strictPort: true, headers: isolation },
  build: { target: 'esnext' },
  resolve: { tsconfigPaths: true },
  plugins: [
    browserPolyfills(),
    tanstackStart(),
    nitro({
      preset: process.env.VERCEL ? 'vercel' : 'node-server',
      routeRules: { '/**': { headers: isolation } },
      // These packages read their wasm, workers and binaries from paths next to their own files, so they stay
      // whole packages, outside the bundle.
      // pino starts its log transport in a worker that it finds next to its own files too.
      traceDeps: [
        '@aztec-foundation/bb.js*',
        '@aztec-foundation/noir-acvm_js*',
        '@aztec-foundation/noir-noirc_abi*',
        'pino*',
        'thread-stream*',
      ],
      hooks: { compiled: nitro => pruneBb(nitro.options.output.serverDir) },
      vercel: { functions: { maxDuration: 300 } },
    }),
    react(),
  ],
});

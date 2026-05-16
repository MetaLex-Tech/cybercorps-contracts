# Local development setup

Audience: anyone running the `metalex-webapp` apps locally.

## Prerequisites

* **Bun** — the package manager and runtime. Install with
  `curl -fsSL https://bun.sh/install | bash`. The repo pins `bun@1.3.x` via
  `packageManager` in the root `package.json`.
* **Vercel CLI** — `npm i -g vercel@latest`. Used to pull environment
  variables.
* **Turborepo** — `npm i -g turbo@latest` (optional; `bunx turbo` also works).
* **Node.js** — only the Ponder-based `cybercorps-indexer` needs Node;
  `v22.14.0` is known-good. Everything else runs on Bun.
* A **Web3 wallet** (MetaMask, Rabby) for the browser apps.

## 1. Install

```bash
git clone git@github.com:MetaLex-Tech/metalex-webapp.git
cd metalex-webapp
bun install
```

## 2. Link to Vercel

```bash
vercel link
# Scope: MetaLex Labs
# Project: metalex-labs/metalex-webapp
```

This creates a `.vercel/` directory and lets you pull environment variables.

## 3. Pull environment variables

```bash
bun pullenv
# equivalent to: vercel env pull .env.development
```

See [Environment variables and secrets](environment.md) for how the layered
`.env` files resolve and the Husky branch-handling behaviour.

## 4. Run the workspace(s) you need

The root `package.json` defines Turbo-filtered dev scripts. Run only what you
need — starting every app is slow and rarely necessary.

| Script | Starts |
|---|---|
| `bun dev:cybercorps-web` | `cybercorps-web` only |
| `bun dev:cybercorps` | `cybercorps-web` + `cybercorps-db` + `cybercorps-indexer` |
| `bun dev:cybercorps-and-db` | `cybercorps-web` + `cybercorps-db` |
| `bun dev:web` | the main `web` app |
| `bun dev:web-and-db` | `web` + `db` |
| `bun dev:web-stack` | `web` + `db` + `snapshot-executor` |
| `bun dev:lexchex` | `lexchex-web` + `lexchex-oracle` |
| `bun dev:landing` | the `landing` site |
| `bun dev:notifier` | `cybercorps-indexer` + `cybercorps-db` + `notifier` |

For the cyberCORPs platform, the usual command is:

```bash
bun dev:cybercorps
```

Then open <http://localhost:3000>.

## 5. Typecheck and lint

From the app directory you edited:

```bash
bun run tsc --noEmit     # typecheck
bunx biome check .       # lint + format check
bunx biome check --write .   # autofix
```

Linting and formatting use **Biome**, not ESLint/Prettier.

## Troubleshooting

* **Indexer import errors** — use Node `v22.14.0`; older versions break on
  some of Ponder's dependencies.
* **Wrong env after switching branches** — a Husky hook renames
  `.env.development.local` per branch. See [Environment variables](environment.md).
* **Dependency version mismatches** — run `bun syncpack` to list and
  `bun syncpack:fix` to resolve.

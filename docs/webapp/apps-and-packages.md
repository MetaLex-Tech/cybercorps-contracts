# Apps and packages

A complete inventory of the `metalex-webapp` workspace. Workspaces are globbed
from `apps/*` and `packages/*` (see the root `package.json`).

## Apps

| Directory | Workspace name | Type | Purpose |
|---|---|---|---|
| `apps/cybercorps-web` | `@metalex-web/cybercorps-web` | Next.js | cyberCORPs platform UI: Mainframe, cyberRAISE, ACE, MetaDAO, profiles. |
| `apps/web` | `@metalex-web/webapp` | Next.js | Main MetaLeX webapp (BORG OS surface). |
| `apps/lexchex-web` | `@metalex-web/lexchex-web` | Next.js | LeXcheX onchain-accreditation app. |
| `apps/landing` | `@metalex-web/landing` | Next.js | Marketing landing site. |
| `apps/cybercorps-indexer` | `@metalex-web/cybercorps-indexer` | Ponder service | Indexes protocol events; serves REST + GraphQL. |
| `apps/lexchex-oracle` | `@metalex-web/lexchex-oracle` | Service | LeXcheX backend: identity / portfolio verification. |
| `apps/notifier` | `@metalex-web/notifier` | Cron service | Telegram notifications for cyberRAISE activity. |
| `apps/snapshot-executor` | `@metalex-web/snapshot-executor` | Service | Executes successful Snapshot / BORG votes onchain. |

Each app has a dedicated page under **Web App — Apps and Services**.

## Packages

| Directory | Purpose |
|---|---|
| `packages/abis` | Contract ABIs for the protocol, consumed by the apps for typed contract calls. |
| `packages/config` | Shared configuration (chains, addresses, constants). |
| `packages/db` | Drizzle schema and client for the main webapp database. |
| `packages/cybercorps-db` | Drizzle schema and client for the cyberCORPs database. |
| `packages/lexchex-db` | Drizzle schema and client for the LeXcheX database. |
| `packages/design-system` | Shared UI design system (components, tokens, styling). |
| `packages/evmClients` | Shared viem clients / chain transports. |
| `packages/encryption` | Encryption utilities (e.g., for cyberSign agreement encryption). |
| `packages/dao-governance-utils` | Helpers for DAO / futarchy governance flows. |
| `packages/proposalManager` | Governance proposal lifecycle logic. |
| `packages/proposal-actions` | Encoders for executable governance proposal actions. |
| `packages/ethos` | Shared domain / reputation utilities. |
| `packages/utils` | Cross-cutting TypeScript utilities. |

## Tooling

| Tool | Role |
|---|---|
| [Bun](https://bun.sh/) `1.3.x` | Package manager and runtime. |
| [Turborepo](https://turbo.build/repo) | Task orchestration and caching across workspaces. |
| [Biome](https://biomejs.dev/) | Linting and formatting (replaces ESLint + Prettier). |
| [Syncpack](https://jamiemason.github.io/syncpack/) | Keeps dependency versions consistent across workspaces. |
| [Husky](https://typicode.github.io/husky/) | Git hooks (including environment-file branch handling). |
| [Drizzle ORM](https://orm.drizzle.team/) | Database schema and queries (Neon Postgres). |
| [Ponder](https://ponder.sh/) | Blockchain indexing (the `cybercorps-indexer` app). |
| [Vercel](https://vercel.com/) | Hosting for the Next.js apps. |

## Filtered dev scripts

The root `package.json` defines Turbo-filtered scripts so you only run the
workspaces you need. See [Local development setup](local-setup.md) for the
full list.

# web

**Workspace:** `@metalex-web/webapp` · **Type:** Next.js

The main MetaLeX webapp — the BORG OS surface. It is a separate app from
`cybercorps-web` (which is the cyberCORPs platform) and has its own database
package (`packages/db`).

## Run it

```bash
bun dev:web                 # web only
bun dev:web-and-db          # web + db
bun dev:web-stack           # web + db + snapshot-executor
```

Opens on <http://localhost:3000>.

## Setup notes

* The app is a standard `create-next-app` Next.js project run with Bun.
* It links to Vercel for hosting and env management (`vercel link`, then
  `bun pullenv`).
* It uses **Drizzle ORM** over Neon Postgres via `packages/db`. See
  [Database](../database.md) for migration workflow and Drizzle Studio.
* Authentication is **SIWE** via `next-auth` v5 — `NEXTAUTH_URL` must be set
  in production. See [Authentication](../authentication.md).

## Relationship to governance

The `web-stack` dev script runs `web` alongside the
[`snapshot-executor`](snapshot-executor.md), reflecting that this app is the
surface for BORG governance flows whose successful votes the executor carries
out on-chain.

> This page reflects the app's README and monorepo configuration. For a
> route-level map, browse `apps/web/src` in the repository.

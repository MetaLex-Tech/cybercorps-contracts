# Deployment

Audience: developers and operators shipping the `metalex-webapp` apps.

## Hosting

The Next.js apps (`cybercorps-web`, `web`, `lexchex-web`, `landing`) are
hosted on **Vercel**. The repository links to the Vercel project
`metalex-labs/metalex-webapp` via `vercel link`.

Turborepo handles the build graph; `vercel.json` at the repo root and each
app's `vercel.ts` configure how Vercel builds each app from the monorepo.

## Branch flow

The repo follows a three-stage promotion flow:

```
Develop  →  Staging  →  Production
```

Open PRs against the appropriate branch for the stage you are targeting.

## Build configuration

The Turbo `build` task (`turbo.json`) declares the env vars required at build
time, including `DATABASE_URL*`, `SNAPSHOT_ORACLE_PK`, the UploadThing keys,
`NEXT_PUBLIC_ALCHEMY_RPC_KEY`, and `NEXT_PUBLIC_WALLETCONNECT_APP_ID`. These
must be configured in the Vercel project for each environment.

Build outputs are `.next/**` (excluding `.next/cache/**`). Turbo caches builds;
`turbo link` connects local builds to Vercel remote caching.

## Environments and env vars

Environment variables are managed in Vercel and pulled locally with
`bun pullenv`. Production-only requirements:

* `NEXTAUTH_URL` **must** be set so SIWE messages verify against the correct
  host.
* `SIWE_ALLOWED_DOMAINS` must list every production host the app serves
  (including each product subdomain).

See [Environment variables](environment.md) for the full layered-resolution
model and the per-app variable lists.

## Subdomain routing

`cybercorps-web` serves multiple product surfaces under subdomains. In
production, set `NEXT_PUBLIC_USE_SUBDOMAIN_ROUTING=true`,
`NEXT_PUBLIC_APP_DOMAIN=metalex.tech`, and configure DNS for each subdomain
(`cybercorps.`, `cyberraise.`, `pump.`, `profile.`). The middleware
(`src/middleware.ts`) maps each host to the right surface.

## Database migrations

Schema changes ship as Drizzle migrations from the relevant `packages/*-db`
package. Generate and review migrations against a **forked** database, then
apply with `bun drizzle-kit migrate`. Never mutate the staging schema
directly. See [Database and Drizzle ORM](database.md).

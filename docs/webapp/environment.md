# Environment variables and secrets

Environment configuration is one of the easiest things to get wrong in this
repo. Read this before running anything beyond a single app.

## Pulling env vars

Environment variables live in Vercel. Pull them with:

```bash
bun pullenv          # vercel env pull .env.development
```

For a branch that needs its own (e.g. a forked database):

```bash
bun pullenv:branch-db   # pulls preview env for the current branch
```

## Layered .env resolution

Multiple `.env*` files load at once and merge, lowest priority first:

1. `.env` — lowest priority; fallback defaults only.
2. `.env.local` — overrides `.env` (not loaded when `NODE_ENV=test`).
3. `.env.<NODE_ENV>` — e.g. `.env.development`; overrides the above.
4. `.env.<NODE_ENV>.local` — e.g. `.env.development.local`; highest-priority
   file.
5. Variables already set in the shell beat everything in files.

By default development uses `.env.development`. When a branch needs its own
values, create `.env.development.local` — it takes precedence.

> **Do not commit `.env*` files.** The only exception is `.env` itself, which
> may serve as a committed example.

## The Husky branch hook

A Husky hook moves `.env.development.local` to
`.env.development.local.<branchname>` when you check out a branch — *unless*
the branch is `main` or `development`, which always use `.env.development`.

This keeps per-branch environments (e.g. branch-specific forked databases)
from leaking across branches. If your env "disappears" after a checkout, look
for a `.env.development.local.<branch>` file and rename it back.

## Notable variables by area

### Build / shared (`turbo.json` `build` task)

`DATABASE_URL*`, `SNAPSHOT_ORACLE_PK`, `UPLOADTHING_APP_ID`,
`UPLOADTHING_SECRET`, `NEXT_PUBLIC_ALCHEMY_RPC_KEY`,
`NEXT_PUBLIC_WALLETCONNECT_APP_ID`.

### cybercorps-web

* Subdomain routing: `NEXT_PUBLIC_USE_SUBDOMAIN_ROUTING`,
  `NEXT_PUBLIC_APP_DOMAIN`, `NEXT_PUBLIC_SUBDOMAIN`.
* Testnets: `NEXT_PUBLIC_SHOW_TESTNETS`.
* Safe multisig: `NEXT_PUBLIC_SAFE_API_KEY`.
* Auth: `NEXTAUTH_SECRET`, `NEXTAUTH_URL`,
  `SIWE_ALLOWED_DOMAINS` (comma-separated EIP-4361 hosts; include
  `localhost:3000` for dev).
* Twitter: `TWITTER_CLIENT_ID`, `TWITTER_CONSUMER_API_KEY`,
  `TWITTER_CONSUMER_API_SECRET`.
* Telegram: `NEXT_PUBLIC_TELEGRAM_BOT_ID`, `TELEGRAM_BOT_TOKEN`.
* Uploads: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`.

### cybercorps-indexer

`PONDER_RPC_URL_84532` (Base Sepolia RPC), `LOG_LEVEL`, `DATABASE_URL`
(optional; SQLite is used if absent), `ENABLE_GRAPHQL_ENDPOINT`.

### notifier

`API_URL` (optional in dev), `DATABASE_URL`, `TELEGRAM_BOT_TOKEN`,
`TELEGRAM_BROADCAST_CHAT_ID`, `TELEGRAM_BROADCAST_THREAD_ID`.

### snapshot-executor

`EXECUTOR_PK` (executor account private key), `DATABASE_URL`,
`DATABASE_URL_UNPOOLED`.

### lexchex-web

`NEXT_PUBLIC_MINT_CHAIN_ID` (defaults to `1`), `NEXT_PUBLIC_TEST_MODE`.

> **Secrets are real keys.** `SNAPSHOT_ORACLE_PK`, `EXECUTOR_PK`, AWS keys,
> and bot tokens are live credentials. Never commit them, never paste them
> into logs or issues, and rotate them through Vercel if exposed.

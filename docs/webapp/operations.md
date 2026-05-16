# Running the backend services

Beyond the Next.js apps, the monorepo has three standalone services that run
continuously. This page covers operating them. Audience: internal operators.

## cybercorps-indexer

**What it does:** indexes protocol events and serves them over REST/GraphQL.

* **Runtime:** Node (`v22.14.0` known-good), not Bun.
* **Start:** `bun start` from `apps/cybercorps-indexer` (dev: `bun dev`,
  serves on `:42069`).
* **Store:** Postgres when `DATABASE_URL` is set; SQLite otherwise. Use
  Postgres in production.
* **GraphQL:** keep `/graphql` disabled in production unless
  `ENABLE_GRAPHQL_ENDPOINT=true` is intentionally set.
* **Operational notes:** the indexer must stay caught up for
  `cybercorps-web` listings and `notifier` to be correct. Monitor lag
  against chain head; on RPC failures it will fall behind.

See [cybercorps-indexer](apps/cybercorps-indexer.md).

## notifier

**What it does:** cron jobs that poll the indexer DB and send Telegram
notifications.

* **Cadence:** deals and EOIs every minute, rounds every 2 minutes.
* **Depends on:** a populated indexer database (`DATABASE_URL` must point at
  the indexer's Postgres store) and a valid `TELEGRAM_BOT_TOKEN`.
* **Operational notes:** each cron job tracks its own state to detect new
  records. If the notifier is down, missed events are picked up on restart
  via that state, but timing guarantees are lost while it is down.

See [notifier](apps/notifier.md).

## snapshot-executor

**What it does:** executes passed Snapshot/BORG governance votes on-chain.

* **Start:** `bun run src/index.ts` from `apps/snapshot-executor`.
* **Depends on:** the BORG web API, the BORG OS database
  (`DATABASE_URL` + `DATABASE_URL_UNPOOLED`), and a funded executor account
  (`EXECUTOR_PK`).
* **Operational notes:** the executor account must hold gas on the relevant
  chain or payload execution will fail. `EXECUTOR_PK` is a high-value secret
  — see below.

See [snapshot-executor](apps/snapshot-executor.md).

## Secrets

These services hold live credentials — `EXECUTOR_PK`, `SNAPSHOT_ORACLE_PK`,
database URLs, `TELEGRAM_BOT_TOKEN`. Keep them only in Vercel / your secrets
manager. If any leaks, rotate immediately: generate a new key/token, update
the environment, and (for executor/oracle keys) move any funds from the
compromised account.

## Health checklist

* Indexer lag vs. chain head is near zero.
* Notifier cron jobs are firing on schedule (watch the MetaLeX activity
  channel for the broadcast copies).
* Executor account gas balance is above your alert threshold.
* Database connections are healthy (pooled and unpooled).

# cybercorps-indexer

**Workspace:** `@metalex-web/cybercorps-indexer` · **Type:**
[Ponder](https://ponder.sh/) service

A blockchain indexer that tracks cyberCORPs deployments and their related data
and exposes it over REST and GraphQL. The webapp uses it for aggregate reads
(cap tables, round lists) that would be slow or impossible as direct
on-chain calls.

## What it indexes

* cyberCORP deployments.
* Roles and permissions for deployed cyberCORPs.

(It currently indexes on the **Base Sepolia** network.)

## Run it

```bash
bun dev                     # from apps/cybercorps-indexer; serves on :42069
bun start                   # production mode
```

Or as part of the cyberCORPs stack: `bun dev:cybercorps`.

> **Node version:** Ponder needs Node (not Bun) for parts of its runtime.
> `v22.14.0` is known-good; older versions break on some Ponder dependencies.

## Configuration

```dotenv
PONDER_RPC_URL_84532=https://sepolia.base.org   # Base Sepolia RPC
LOG_LEVEL=info                                  # trace|debug|info|warn|error|fatal
DATABASE_URL=                                    # optional; SQLite if unset
ENABLE_GRAPHQL_ENDPOINT=false                    # expose /graphql in prod
```

## API

### `GET /cybercorps`

Returns all indexed cyberCORPs. Optional `owner` query parameter filters by
owner address. Each record includes `address`, `name`, `auth`,
`issuanceManager`, `agreementFactory`, `owners`, and `allRoles` (level + user).

### GraphQL

A GraphQL API is served at `/graphql` in development. In production it is
disabled unless `ENABLE_GRAPHQL_ENDPOINT=true`.

## Consumers

* [`cybercorps-web`](cybercorps-web.md) — cap-table and listing views.
* [`notifier`](notifier.md) — polls the indexer's database for activity.

# Database and Drizzle ORM

The webapp uses [Drizzle ORM](https://orm.drizzle.team/) over
[Neon](https://neon.tech/) Postgres. There are three database packages, one
per product domain.

| Package | Database for |
|---|---|
| `packages/db` | The main `web` app. |
| `packages/cybercorps-db` | The cyberCORPs platform (`cybercorps-web`, `notifier`). |
| `packages/lexchex-db` | LeXcheX (`lexchex-web`, `lexchex-oracle`). |

Each package owns a Drizzle schema (`src/schema.ts`), generated migrations
(`drizzle/`), and a client.

## Working with the schema

All schema changes go through migrations — **do not** edit a deployed
(staging) schema directly.

From the relevant `packages/*-db` directory:

```bash
# 1. Edit src/schema.ts

# 2. Generate a migration
bun drizzle-kit generate      # writes a file into drizzle/

# 3. Review the generated SQL, then apply
bun drizzle-kit migrate
```

> **Always generate migrations against a forked database**, not staging. If
> you accidentally change the staging schema, you can revert in the Neon
> console — but only within a limited time window.

### Other commands

| Command | Effect |
|---|---|
| `bun push-schema` | Push the schema directly to the DB (rapid dev; forked DB only — skips migration files). |
| `bun drizzle-kit drop` | Drop a migration. |
| `bun drizzle-kit generate --custom` | Create an empty migration to fill in by hand. |
| `bun studio` | Open Drizzle Studio to browse data. |

Never hand-edit files in a `drizzle/` directory.

## Forked databases per branch

For schema work, create a database branch (Neon CLI: `brew install neonctl`,
then `neonctl auth`) and point your `.env.development.local` at it. Combined
with the Husky branch hook (see [Environment variables](environment.md)),
this keeps each working branch isolated from staging.

## The indexer's store is separate

The `cybercorps-indexer` (Ponder) maintains its **own** store — SQLite by
default, or Postgres if `DATABASE_URL` is set. It is not a Drizzle package;
see [cybercorps-indexer](apps/cybercorps-indexer.md).

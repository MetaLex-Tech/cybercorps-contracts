# snapshot-executor

**Workspace:** `@metalex-web/snapshot-executor` · **Type:** standalone
service

A service that bridges off-chain governance to on-chain execution. It watches
for Snapshot votes that carry an execution payload and, once a vote passes,
executes that payload on-chain.

## How it works

1. The executor polls the **BORG web API** for new Snapshot votes that were
   configured with an execution payload.
2. For each, it sets up a task to check whether the vote succeeded.
3. If the vote passed, it executes the payload on-chain using the executor
   account.

## Run it

```bash
bun run src/index.ts        # from apps/snapshot-executor
```

Or alongside the main webapp: `bun dev:web-stack`.

## Configuration

| Variable | Description |
|---|---|
| `EXECUTOR_PK` | Private key of the executor account that submits the on-chain transactions. |
| `DATABASE_URL` | BORG OS database URL. |
| `DATABASE_URL_UNPOOLED` | BORG OS database URL for unpooled connections. |

> `EXECUTOR_PK` is a live private key controlling an account that can execute
> governance payloads. Treat it as a high-value secret — store it only in
> Vercel / your secrets manager, never in a committed file.

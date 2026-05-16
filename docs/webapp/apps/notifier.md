# notifier

**Workspace:** `@metalex-web/notifier` · **Type:** cron-based service

A notification service that monitors cyberCORPs / cyberRAISE activity and
sends real-time **Telegram** notifications to the relevant stakeholders —
investors and founders — when deals, funding rounds, and Expressions of
Interest (EOIs) change.

## How it works

The notifier runs scheduled cron jobs that poll the
[`cybercorps-indexer`](cybercorps-indexer.md) database for changes. Each job
keeps its own state to detect new or updated records, then sends targeted
Telegram messages to users based on their association with a given
cyberCORP, deal, or round. A copy of every notification is also sent to
MetaLeX's private Telegram activity channel.

### Cron schedules

| Job | Frequency |
|---|---|
| Deals | every minute |
| EOIs | every minute |
| Rounds | every 2 minutes |

## Run it

```bash
bun dev:notifier            # cybercorps-indexer + cybercorps-db + notifier
```

The notifier needs the indexer's database to be populated, hence the combined
script.

## Configuration

```dotenv
API_URL=                      # optional in dev
DATABASE_URL=                  # postgres://user:password@host:port/dbname
TELEGRAM_BOT_TOKEN=
TELEGRAM_BROADCAST_CHAT_ID=
TELEGRAM_BROADCAST_THREAD_ID=
```

# cybercorps-web

**Workspace:** `@metalex-web/cybercorps-web` · **Type:** Next.js (App Router)

The cyberCORPs platform UI. This is the app that surfaces the issuer
**Mainframe**, **cyberRAISE**, **ACE**, **MetaDAO**, and investor profiles. It
is the closest thing in the monorepo to "the cyberCORPs app."

## Run it

```bash
bun dev:cybercorps          # web + cybercorps-db + indexer
# or just the UI:
bun dev:cybercorps-web
```

Opens on <http://localhost:3000>.

## Product surfaces (routes)

| Route | Surface |
|---|---|
| `(frame-layout)/cybercorps` | The **Mainframe** — cap table / holder register, rounds, deals, agreements, scripification, roles, threshold monitoring. |
| `(frame-layout)/cyberraise` | **cyberRAISE** primary fundraising. |
| `(frame-layout)/metadao` | **MetaDAO** futarchy governance. |
| `(frame-layout)/profile` | Investor / user profiles. |
| `(frame-layout)/umia` | UMIA surface. |
| `(frame-layout)/experiments` | Experimental routes. |
| `ace` | **ACE** (Asset Conversion to Equity), incl. `bridge-to-solana` / `bridge-from-solana`. |
| `api` | Route handlers (server-side endpoints). |
| `auth` | Sign-in pages. |

## Feature modules

Under `src/features/`: `api`, `auth`, `caching`, `certificates`,
`conditions`, `cybercorp`, `deals`, `forms`, `help`, `integrations`,
`multisig`, `notifications`, `profile`, `providers`, `pump`, `rounds`,
`signatures`, `transactions`, `ui`, `upgradability`, `zkpassport`.

## Integrations

* **Wallets:** injected (MetaMask, Rabby) + WalletConnect.
* **Safe multisig:** for issuer governance actions (`NEXT_PUBLIC_SAFE_API_KEY`).
* **Indexer:** reads cap-table / round data from `cybercorps-indexer`.
* **Database:** `packages/cybercorps-db`.
* **Auth:** SIWE via `next-auth` v5.
* **Social:** Twitter/X profile linking; Telegram bot for notifications.
* **Uploads:** AWS S3 for profile images.

## Subdomain routing

The app can serve different product surfaces under different subdomains
(`cybercorps.`, `cyberraise.`, `pump.`, `profile.metalex.tech`) controlled by
`NEXT_PUBLIC_USE_SUBDOMAIN_ROUTING`, `NEXT_PUBLIC_APP_DOMAIN`, and
`NEXT_PUBLIC_SUBDOMAIN`, with routing logic in `src/middleware.ts`. Every
served host must be listed in `SIWE_ALLOWED_DOMAINS` — see
[Authentication](../authentication.md).

## Key environment variables

See [Environment variables](../environment.md#cybercorps-web). Notable:
subdomain routing vars, `NEXT_PUBLIC_SHOW_TESTNETS`, `NEXT_PUBLIC_SAFE_API_KEY`,
`NEXTAUTH_SECRET` / `NEXTAUTH_URL`, `SIWE_ALLOWED_DOMAINS`, Twitter and
Telegram credentials, AWS upload keys.

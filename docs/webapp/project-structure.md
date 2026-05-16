# Monorepo structure and conventions

```
metalex-webapp/
├─ apps/
│  ├─ cybercorps-web/      Next.js — cyberCORPs platform UI
│  ├─ web/                 Next.js — main MetaLeX webapp
│  ├─ lexchex-web/         Next.js — LeXcheX accreditation app
│  ├─ landing/             Next.js — marketing site
│  ├─ cybercorps-indexer/  Ponder — protocol event indexer
│  ├─ lexchex-oracle/      service — LeXcheX verification backend
│  ├─ notifier/            service — Telegram notifications
│  └─ snapshot-executor/   service — governance vote execution
├─ packages/
│  ├─ abis/  config/  db/  cybercorps-db/  lexchex-db/
│  ├─ design-system/  evmClients/  encryption/  utils/  ethos/
│  └─ dao-governance-utils/  proposalManager/  proposal-actions/
├─ turbo.json               Turborepo task graph
├─ biome.json               lint + format config
├─ package.json             root scripts, workspaces, tooling
└─ AGENTS.md                contributor / agent conventions
```

## Inside a Next.js app (cybercorps-web)

`cybercorps-web` uses the **App Router**. Its `src/` is organised as:

```
src/
├─ app/                 App Router routes
│  ├─ (frame-layout)/   routes inside the main app frame
│  │  ├─ cybercorps/    the Mainframe
│  │  ├─ cyberraise/    primary fundraising
│  │  ├─ metadao/       futarchy governance
│  │  ├─ profile/       user / investor profiles
│  │  └─ umia/
│  ├─ (form-layout)/    routes inside the form-style layout
│  ├─ ace/             ACE product (+ Solana bridge routes)
│  ├─ api/             route handlers
│  └─ auth/            auth pages
├─ features/            feature modules (see below)
├─ hooks/  helpers/  data/  types/  assets/
└─ middleware.ts        subdomain routing + auth middleware
```

### Feature modules

App logic is grouped under `src/features/` by domain rather than by technical
layer. Notable modules in `cybercorps-web`:

`api`, `auth`, `caching`, `certificates`, `conditions`, `cybercorp`, `deals`,
`forms`, `help`, `integrations`, `multisig`, `notifications`, `profile`,
`providers`, `pump`, `rounds`, `signatures`, `transactions`, `ui`,
`upgradability`, `zkpassport`.

A feature module typically owns its components, hooks, and helpers for that
domain. Route files under `app/` stay thin and compose feature modules.

## Conventions

From `AGENTS.md` and observed patterns:

* **TypeScript style** — import React types directly (`ReactNode`, not
  `React.ReactNode`); prefer plain function components over `FC`; inline
  props typing at the declaration when practical.
* **Components** — avoid over-abstraction; keep small low-reuse components
  whole; extract subcomponents only when it clearly helps reuse or
  readability.
* **Forms** — reuse existing form components; `useState` is fine for simple
  forms; use [TanStack Form](https://tanstack.com/form) for larger forms with
  complex validation or workflow logic.
* **UI** — align with the shared [`design-system`](design-system.md) package
  and existing app patterns.
* **Lint/format** — Biome. **Typecheck** — `bun run tsc --noEmit` from the
  edited app.
* **Per-developer agent instructions** — a gitignored `AGENTS.local.md` may
  exist alongside `AGENTS.md`.

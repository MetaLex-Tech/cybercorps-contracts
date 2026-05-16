# Add a feature to cybercorps-web

A worked recipe for adding a new feature to the `cybercorps-web` app, using
its established conventions. Audience: developers contributing to the repo.

## Before you start

* Read [Monorepo structure](project-structure.md) and
  [The design system](design-system.md).
* Run the app: `bun dev:cybercorps` (see [Local setup](local-setup.md)).
* Decide which **feature module** your work belongs to (`rounds`, `deals`,
  `certificates`, `cybercorp`, `pump`, etc.) or whether it needs a new one.

## 1. Create or locate the feature module

Feature code lives under `src/features/<domain>/`. A module owns the
components, hooks, and helpers for its domain. If your feature is a new
domain, create `src/features/<your-domain>/` rather than scattering files.

## 2. Add the route

Routes live under `src/app/`. Pick the right layout group:

* `(frame-layout)/` — pages inside the main app frame (most issuer/investor
  pages: `cybercorps`, `cyberraise`, `metadao`, `profile`).
* `(form-layout)/` — pages using the form-style layout.
* top-level (e.g. `ace/`) — product surfaces with their own layout.

Keep the route file (`page.tsx`) thin: it should compose components from your
feature module, not contain business logic.

## 3. Wire up data

* **On-chain reads:** wagmi hooks with ABIs from `@metalex-web/abis` — see
  [Calling the protocol](contract-integration.md).
* **Aggregate reads** (lists, cap tables): query the
  [`cybercorps-indexer`](apps/cybercorps-indexer.md), not the chain directly.
* **App data:** the cyberCORPs database via `packages/cybercorps-db`
  (Drizzle) — see [Database](database.md).
* **Transactions:** reuse the `transactions` feature module's wrappers.

## 4. Build the UI

* Reuse `packages/design-system` and `features/ui` components first.
* Forms: reuse the `forms` module; use TanStack Form for complex forms.
* Follow the `ui-design-system` skill and existing patterns.

## 5. Handle auth and gating

* Gate by session via `next-auth` (the `auth` module) — see
  [Authentication](authentication.md).
* Gate issuer actions by **on-chain BorgAuth roles**; show/hide UI from the
  role read, but never assume the UI is the enforcement point.
* If a protocol `ICondition` applies (accreditation, zkPassport), use the
  `conditions` / `zkpassport` modules to guide the user.

## 6. Verify

```bash
bun run tsc --noEmit         # from apps/cybercorps-web
bunx biome check --write .   # lint + format
```

Exercise the feature in the browser — golden path and edge cases — and check
you have not regressed neighbouring routes.

## 7. Commit

Follow the repo's branch flow: **Develop → Staging → Production**. Open your
PR against the appropriate branch and keep env files out of the commit.

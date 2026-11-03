# Private Agreements web app (Aztec PoC)

The web app of the PoC, on the same stack as the cyberSign web app: TanStack Start (React 19) on Vite 8, Nitro with
the Vercel preset, Tailwind, Drizzle ORM on Postgres (Neon on Vercel), bun.

- **Browser (the user device):** each role page runs an Aztec wallet and PXE in the browser. The signing key stays in
  the browser (`localStorage`). The browser makes the salt, encrypts the document, signs authwits, checks proofs and
  reads the status from the Aztec node.
- **Server (MetaLeX):** server functions with Postgres hold the vault, the signature collector, the data key store
  and the settlements. When the last party signs, the server answers at once and the settler sends `finalize` in the
  background (`waitUntil`), with `NO_WAIT`. The browser waits for the tx.

| Path | Content |
| --- | --- |
| `src/client/` | The pages and the browser wallet (`aztec.ts`) |
| `src/server/metalex.ts` | MetaLeX server functions |
| `src/server/settler.ts` | The settler: proves and sends `finalize` |
| `src/server/db/` | Drizzle schema and client |
| `src/shared/` | Agreement model, crypto (WebCrypto) and account data, used by both sides |
| `src/artifacts/` | The compiled registry artifact (`bun run artifacts` copies it from `../target`) |
| `drizzle/` | SQL migrations |
| `journey/` | Playwright journey |

## Run locally

Use Node 24 and bun. Start Postgres, for example in Docker, and apply the migrations:

```shell
docker run -d --name aztec-poc-postgres -e POSTGRES_PASSWORD=poc -e POSTGRES_DB=agreements -p 5434:5432 postgres:17
```
```shell
bun install && DATABASE_URL=postgres://postgres:poc@localhost:5434/agreements bunx drizzle-kit migrate
```

Copy `.env.example` to `.env.local` and fill it in. Then build and start:

```shell
bun run build && PORT=3001 node --env-file=.env.local .output/server/index.mjs
```

Open http://localhost:3001/bob once (Bob onboards), then http://localhost:3001/alice.

Journey, against a running app. Each run onboards a new Alice and Bob, so run it against an app on its own
database (here `agreements_journey`), not the one you play with:

```shell
docker exec aztec-poc-postgres psql -U postgres -c "create database agreements_journey;"
```
```shell
DATABASE_URL=postgres://postgres:poc@localhost:5434/agreements_journey bunx drizzle-kit migrate
```
```shell
PORT=3003 DATABASE_URL=postgres://postgres:poc@localhost:5434/agreements_journey node --env-file=.env.testnet .output/server/index.mjs
```
```shell
APP_URL=http://localhost:3003 bun run journey
```

## Deploy to Vercel

1. Install and log in: `vercel login`.
2. In this folder, link a new project: `vercel link`. Pick your personal scope and "create a new project".
3. Add a Neon Postgres database: Vercel dashboard > the project > Storage > Create Database > Neon. Connect it to
   the project. It sets `DATABASE_URL`.
4. Apply the migrations to it once, from this folder: `vercel env pull .env.vercel`, then
   `bunx drizzle-kit migrate` with that `DATABASE_URL`.
5. Add the other variables of `.env.example` (Production and Preview): `vercel env add <NAME>`. Mark
   `SETTLER_SIGNING_KEY` and `ENCRYPTION_KEY` as sensitive.
6. Deploy: `vercel deploy --prod`.

The settler runs in the app's function: about 120 MB with the Linux prover, under Vercel's 250 MB limit. Each
`finalize` runs for about 15 to 30 s in the background, under the 300 s limit of the Hobby plan.

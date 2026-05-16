# Authentication (SIWE)

The browser apps authenticate users with their wallet via
**Sign-In With Ethereum** (EIP-4361), wired through
[`next-auth` v5](https://authjs.dev/) and the
[`siwe`](https://docs.login.xyz/) library.

## How it works

1. The user connects a wallet.
2. The app builds an EIP-4361 message and asks the wallet to sign it.
3. `next-auth` verifies the signature and issues a session.
4. Session state is consumed by route handlers and server components.

## Key environment variables

| Variable | Role |
|---|---|
| `NEXTAUTH_SECRET` | Signs/encrypts the session token. |
| `NEXTAUTH_URL` | The canonical app URL. **Must be set in production** so SIWE messages verify against the right host. |
| `SIWE_ALLOWED_DOMAINS` | Comma-separated list of EIP-4361 hosts allowed in the signed message. Include `localhost:3000` for dev. |

`SIWE_ALLOWED_DOMAINS` matters because `cybercorps-web` serves multiple
product surfaces under different subdomains (see [Deployment](deployment.md)).
The `siwe` check uses `window.location.host`, so every host the app is served
from — `cybercorps.metalex.tech`, `cyberraise.metalex.tech`,
`pump.metalex.tech`, `profile.metalex.tech`, `localhost:3000` — must appear in
the list or sign-in will fail on that host.

## Social connections

`cybercorps-web` also supports linking a Twitter/X profile (used on investor
profiles). This needs `TWITTER_CLIENT_ID` for the OAuth flow and
`TWITTER_CONSUMER_API_KEY` / `TWITTER_CONSUMER_API_SECRET` for refreshing
profile images.

## Where the code lives

In `cybercorps-web`, authentication is the `src/features/auth` module plus
`src/app/auth/` routes and `src/middleware.ts`. The middleware also handles
subdomain routing, so auth and routing are intertwined there.

## Authorization

Authentication proves *who* a wallet is. Authorization — *what* that wallet
may do on a given cyberCORP — is enforced **on-chain** by BorgAuth roles
(see the protocol [Access control](../reference/access-control.md) page). The
app reads on-chain roles to decide which UI actions to show, but the contract
is the source of truth: a spoofed UI cannot grant authority the chain does
not recognise.

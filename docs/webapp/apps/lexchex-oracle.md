# lexchex-oracle

**Workspace:** `@metalex-web/lexchex-oracle` · **Type:** backend service

The backend oracle for [LeXcheX](lexchex-web.md). It performs the
identity and wealth verification that underpins an accreditation credential,
so that the front end never has to be trusted with that determination.

## Role in the flow

When a user completes the LeXcheX flow in `lexchex-web`, the oracle:

* validates wallet-ownership signatures,
* evaluates portfolio value across the user's verified wallets,
* backs the identity / financial-institution checks behind the
  questionnaire.

The result feeds the minting of the soulbound accreditation certificate that
the protocol's `lexchexCondition` later checks on-chain.

## Run it

```bash
bun dev:lexchex             # runs lexchex-web + lexchex-oracle together
```

## Test-mode flags

For local testing against Base Sepolia, the oracle honours:

* `BYPASS_PLAID=true` — skip the Plaid-based financial-institution checks.
* `SKIP_SIGNATURE_CHECKS=true` — skip wallet-ownership signature
  verification.

These pair with `lexchex-web`'s test mode (`NEXT_PUBLIC_TEST_MODE=true`,
`NEXT_PUBLIC_MINT_CHAIN_ID=84532`). **Never enable them outside local
testing** — they disable the checks that make a credential meaningful.

> This page is assembled from the `lexchex-web` README and monorepo
> configuration; the oracle does not ship its own README. For exact
> endpoints and providers, browse `apps/lexchex-oracle/src` in the
> repository.

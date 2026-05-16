# lexchex-web

**Workspace:** `@metalex-web/lexchex-web` · **Type:** Next.js

The **LeXcheX** app: unlocking onchain accreditation. It lets individuals and
legal entities prove accredited-investor status using wallet-based assets and
mint accredited-investor certificates as non-transferable, wallet-bound NFTs.

These credentials are what the protocol's
[`lexchexCondition`](../../reference/conditions.md#lexchexcondition) checks.

## The user flow

1. **Questionnaire** — the user states investor type (individual or legal
   entity) and completes SEC Rule 501(a) compliance forms.
2. **Evaluation** — the user connects and verifies wallet addresses;
   onchain wealth is evaluated (target: $1M+ individuals, $5M+ entities).
3. **Sign agreement** — the user signs the LeXcheX agreement from their
   wallet and mints the accredited-investor certificate.

## Features

* Multi-wallet verification with cryptographic ownership signatures.
* Real-time portfolio valuation (Zapper API integration).
* SEC-compliant forms for individuals and legal entities.
* Soulbound (non-transferable, wallet-bound) NFT certificates.
* Onchain, auditable accreditation records.

## Run it

```bash
bun dev:lexchex             # lexchex-web + lexchex-oracle
```

Needs Node for the oracle side; `v22.14.0` is known-good.

## Configuration

* `NEXT_PUBLIC_MINT_CHAIN_ID` — mint chain; defaults to `1` (mainnet).
* `NEXT_PUBLIC_TEST_MODE` — enables a local test mode.

### Test mode

When `NEXT_PUBLIC_MINT_CHAIN_ID=84532` (Base Sepolia) and
`NEXT_PUBLIC_TEST_MODE=true`, pressing `]` repeatedly unlocks test shortcuts:

* once — skip the questionnaire,
* twice — allow signing any address,
* three times — simulate a $5M portfolio.

The paired `lexchex-oracle` must also have `BYPASS_PLAID=true` and
`SKIP_SIGNATURE_CHECKS=true`.

## Paired service

`lexchex-web` is the front end; [`lexchex-oracle`](lexchex-oracle.md) is the
backend that performs identity and portfolio verification.

# Integrate from a frontend

This guide covers calling the protocol from a TypeScript / React app. The
reference UIs live in
[`metalex-webapp`](https://github.com/MetaLex-Tech/metalex-webapp).

## Recommended stack

* **wagmi + viem** for contract calls and typed ABIs.
* A wallet connector (injected wallets, WalletConnect).
* An **indexer** for list/aggregate reads (cap tables, rounds) rather than
  many direct contract reads.

## Reading contract state

```ts
import { useReadContract } from "wagmi";
import { cyberCorpAbi } from "@/abis";

const { data: name } = useReadContract({
  abi: cyberCorpAbi,
  address: cyberCorpAddress,
  functionName: "cyberCORPName",
});
```

Note the real getters: `cyberCORPName`, `cyberCORPType`,
`cyberCORPJurisdiction` on `CyberCorp`; `legalOwnerOf` vs `ownerOf` on
the cert printer (the `LedgerEntryToken` contract, formerly
`CyberCertPrinter` — the rename did not change the ABI).

## Writing transactions

Use `useWriteContract`. State-changing calls go through the cyberCORP's
manager contracts — `IssuanceManager`, `DealManager`, `RoundManager` — not
directly to `LedgerEntryToken` / `CyberScrip` (those are mostly
`onlyIssuanceManager`, with some admin-gated exceptions on the cert
printer). The DealManager's secondary-trade entry points (`postOffer`,
`acceptOffer`, `cancelOffer`) each have a relayed overload
`(…, forAddr, nonce, sig)` for gasless UX; `voidSecondaryTradeAgreement`'s
relayed form differs — `(agreementId, signer, voidSignature, nonce,
authSig)`.

## EIP-712 signatures

cyberRAISE EOIs, deal counter-signatures, and cyberSign agreements are
EIP-712 typed-data signatures, produced with `viem`'s `signTypedData`. The
`CyberAgreementRegistry` underlies all of them — a round EOI and a deal both
resolve to a registry contract identified by a `bytes32` id.

## Rendering a cyberCERT

`tokenURI(tokenId)` on the cert printer returns a base64 `data:` JSON whose
`image` is an onchain-rendered SVG. Decode the JSON, then render the SVG.
(`tokenURIJson(tokenId)` returns the JSON un-encoded.)

## ABIs

Keep your ABIs in sync with the deployed contracts. Each contract exposes
its own `DEPLOY_VERSION` — at time of writing `"4.1"` for
`IssuanceManager`, `"4.0.1"` for `DealManager`, and `"4"` for `CyberCorp`,
`RoundManager`, `LedgerEntryToken`, and `CyberScrip`. The protocol is under
active development; regenerate ABIs when implementations change.

## Related

* [Application stack](../explanation/application-stack.md).
* The Web App section of these docs covers the live apps from a user's
  perspective.

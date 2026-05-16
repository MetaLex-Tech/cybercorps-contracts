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
`CyberCertPrinter`.

## Writing transactions

Use `useWriteContract`. State-changing calls go through the cyberCORP's
manager contracts — `IssuanceManager`, `DealManager`, `RoundManager` — not
directly to `CyberCertPrinter` / `CyberScrip` (those are
`onlyIssuanceManager`).

## EIP-712 signatures

cyberRAISE EOIs, deal counter-signatures, and cyberSign agreements are
EIP-712 typed-data signatures, produced with `viem`'s `signTypedData`. The
`CyberAgreementRegistry` underlies all of them — a round EOI and a deal both
resolve to a registry contract identified by a `bytes32` id.

## Rendering a cyberCERT

`CyberCertPrinter.tokenURI(tokenId)` returns a base64 `data:` JSON whose
`image` is an onchain-rendered SVG. Decode the JSON, then render the SVG.

## ABIs

Keep your ABIs in sync with the deployed contracts (`DEPLOY_VERSION` `"4"`
at time of writing). The protocol is under active development; regenerate
ABIs when implementations change.

## Related

* [Application stack](../explanation/application-stack.md).
* The Web App section of these docs covers the live apps from a user's
  perspective.

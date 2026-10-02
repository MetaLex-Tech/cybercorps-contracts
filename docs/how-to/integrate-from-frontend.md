---
description: Wire a dApp frontend to the cyberCORPs contracts
---

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
`CyberCertPrinter`; the rename itself did not change the ABI, but the v5
printer did, see [ABIs and versions](#abis-and-versions)).

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

## Atomic fee + formation via Multicall3

A USDC platform fee and a `CyberCorpFactory` deployment can be batched into
one transaction through the canonical Multicall3
(`0xcA11bde05977b3631167028862bE2a173976CA11`): the fee travels as an
EIP-3009 `transferWithAuthorization` (the user signs typed data naming the
recipient, amount, validity window, and a random nonce), and the formation
call takes the owner as a parameter — so neither inner call depends on
`msg.sender`, and Multicall3 being the sender of both is harmless.

The batch is all-or-nothing **only if you set `allowFailure: false` on both
`Call3` entries** — that is what makes `aggregate3` revert the whole
transaction when either call fails. With `allowFailure: true`, Multicall3
continues past a failed call: the suite's
`test_frontRunAuthorizationToleratedWithAllowFailure` shows formation
succeeding while the fee call fails, which as a frontend default would
deploy the corp without collecting the fee.

The strictness is scoped to the batch, not to the signed authorization: an
EIP-3009 authorization is submittable by anyone, so a front-runner can
mine it directly before your batch, transferring the fee to its named
recipient and leaving the strict batch to revert on the consumed nonce
with nothing deployed (`test_frontRunAuthorizationRevertsTheStrictBatch`).
Handle that case explicitly — detect the used nonce, verify where the fee
went, and reconcile before asking the user to sign a fresh authorization —
rather than treating a batch revert as "nothing happened". See
[`test/MulticallFormationFeeForkTest.t.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/test/MulticallFormationFeeForkTest.t.sol)
for a worked Base-mainnet example, including the
`TransferWithAuthorization` typed-data struct.

## EIP-712 signatures

cyberRAISE EOIs, deal counter-signatures, and cyberSign agreements are
EIP-712 typed-data signatures, produced with `viem`'s `signTypedData`. The
`CyberAgreementRegistry` underlies all of them — a round EOI and a deal both
resolve to a registry contract identified by a `bytes32` id, and the party
signs the registry's `SignatureData` under the domain
`{ name: "CyberAgreementRegistry", version: "1", chainId, verifyingContract: registry }`.

The `SignatureData` type depends on the registry implementation, not on the
company's version. Read it before building the typed data:

```ts
const typeHash = await publicClient.readContract({
  address: registry,
  abi: cyberAgreementRegistryAbi,
  functionName: "SIGNATUREDATA_TYPEHASH",
});
// 0xe37d17c3ab7740aee31093101f9d27d139a5c3b35324b266efe5d085d6486f05
//   current type: SignatureData(bytes32 contractId,address signer,string legalContractUri,
//   string[] globalFields,string[] partyFields,string[] globalValues,string[] partyValues)
// 0x49ba7af1fd9b42077b5e2bf090b7deb0f443e9ae99b46ce66b4859e28d670da4
//   older type: the same struct without `signer`
// anything else: refuse rather than guess
```

On 2026-10-02 the registry at `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`
returned the current type on Ethereum, Base, and Arbitrum; the separate
zkSync Era registry returned the older one. With the current type, set
`signer` to the party the signature counts for (the delegator when a
delegate signs). Where the flow allows, take agreement ids from the
`ContractCreated` event or a simulated `createContract`; when a party must
sign first, hash the id with the formula for that registry version (see
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md#data-model)).

Other signatures use their own domains, each with version `"1"`, the chain
id, and the verifying contract:

| Signature | Domain name | Verifying contract |
|---|---|---|
| Officer's escrowed round signature (`EscrowedSignatureData`) | `"RoundManager"` | the RoundManager |
| Relayed `postOffer` / `acceptOffer` / `cancelOffer` / void authorizations | `"DealManager"` | the DealManager |
| Officer's deployment-metadata signature (`RoundSupplementalData`) for `deployCyberCorpAndCreateRound` | `"CyberCorpFactory"` (or `"PumpCorpFactory"`) | the factory |

## Rendering a cyberCERT

`tokenURI(tokenId)` on the cert printer returns a base64 `data:` JSON whose
`image` is an onchain-rendered SVG. Decode the JSON, then render the SVG.
(There is no un-encoded JSON getter on the printer — base64-decode the
`data:` payload for the raw JSON.)

## ABIs and versions

v4 and v5 companies coexist on the same chains. Since the v5 upgrade of
the Ethereum, Base, and Arbitrum factories, new companies are created
with v5 components (the four component factories' reference
implementations all reported `DEPLOY_VERSION` `"5"` on 2026-10-02), while
an existing company keeps its deployed version until its owners upgrade
it. Pick the ABI per company and per component, never per chain:

* Read `DEPLOY_VERSION()` on the contract you are about to call:
  `CyberCorp`, `IssuanceManager`, `DealManager`, `RoundManager`,
  `LedgerEntryToken`, or `CyberScrip`. v5 components report `"5"`; v4
  components report `"4"`, `"4.1"` (`IssuanceManager`), or `"4.0.1"`
  (`DealManager`). Compare the major version, and refuse a version your
  ABIs do not cover instead of falling back to one.
* Each component is upgraded on its own and nothing onchain forces a
  company to upgrade them together, so do not infer one component's
  version from another's.
* Selectors change between versions wherever a struct gained a field. For
  example, `CyberCertData` and `IssuanceManager.createCertPrinter` gained
  the extension's `seriesData` in v5: `createCertPrinter` is `0x6cf6f4b0`
  on a v4 IssuanceManager and `0xfe197ea2` on a v5 one. A call with the
  other version's selector reverts.
* The agreement registry is a single proxy per chain, shared by v4 and v5
  companies; select its signature type as described in
  [EIP-712 signatures](#eip-712-signatures).
* `CyberCorpFactory.deployCyberCorpAndCreateRound` takes a second officer
  signature (`metadataSignature`, see the table above) on the upgraded
  factories; its selector there is `0x80d78d40`.

Regenerate ABIs from the source when implementations change.

## Related

* [Application stack](../explanation/application-stack.md).
* The Web App section of these docs covers the live apps from a user's
  perspective.

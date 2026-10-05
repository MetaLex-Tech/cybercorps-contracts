---
description: Read and write the cyberCORPs contracts from a TypeScript or React app, build EIP-712 signatures, and pick the right ABI for v4 and v5 companies
---

# Integrate from a frontend

This guide covers calling the protocol from a TypeScript or React app.
MetaLeX's reference front ends are in
[`metalex-webapp`](https://github.com/MetaLex-Tech/metalex-webapp).

## Use wagmi, viem and an indexer

* **wagmi and viem** for contract calls and typed ABIs.
* A wallet connector (injected wallets, WalletConnect).
* An **indexer** for list and aggregate reads such as cap tables and rounds,
  instead of many direct contract reads.

## Read contract state

```ts
import { useReadContract } from "wagmi";
import { cyberCorpAbi } from "@/abis";

const { data: name } = useReadContract({
  abi: cyberCorpAbi,
  address: cyberCorpAddress,
  functionName: "cyberCORPName",
});
```

`CyberCorp`'s getters are `cyberCORPName`, `cyberCORPType` and
`cyberCORPJurisdiction`. On a Ledger Entry Token (LET) contract
(`LedgerEntryToken`), `legalOwnerOf` returns a LET's registered owner and
`ownerOf` the wallet holding it. v4 and v5 LET contracts have different
ABIs; see [Pick the ABI for each company and
component](#pick-the-abi-for-each-company-and-component).

## Send transactions through the manager contracts

Use `useWriteContract`. State-changing calls go to the company's manager
contracts: `IssuanceManager`, `DealManager` and `RoundManager`. Most
`LedgerEntryToken` and `CyberScrip` functions are `onlyIssuanceManager`,
with some admin-gated exceptions on the LET contract. The DealManager's
secondary-trade entry points (`postOffer`, `acceptOffer`, `cancelOffer`)
each have a relayed overload `(…, forAddr, nonce, sig)` for gasless
trading. `voidSecondaryTradeAgreement`'s relayed form takes
`(agreementId, signer, voidSignature, nonce, authSig)` instead.

## Batch the formation fee and deployment with Multicall3

A USDC platform fee and a `CyberCorpFactory` deployment can go in one
transaction through the canonical Multicall3
(`0xcA11bde05977b3631167028862bE2a173976CA11`). The fee travels as an
EIP-3009 `transferWithAuthorization` (the user signs typed data naming the
recipient, amount, validity window and a random nonce), and the formation
call takes the owner as a parameter. Neither inner call depends on
`msg.sender`, so Multicall3 being the sender of both is harmless.

The batch is all-or-nothing **only if you set `allowFailure: false` on both
`Call3` entries**, which makes `aggregate3` revert the whole transaction
when either call fails. With `allowFailure: true`, Multicall3 continues
past a failed call. The suite's
`test_frontRunAuthorizationToleratedWithAllowFailure` shows formation
succeeding while the fee call fails, which as a frontend default would
deploy the company without collecting the fee.

Anyone can submit an EIP-3009 authorization, including a front-runner who
mines it directly before your batch. The fee then reaches its named
recipient, and the strict batch reverts on the consumed nonce with nothing
deployed (`test_frontRunAuthorizationRevertsTheStrictBatch`). A reverted
batch can therefore still have moved the fee, so detect the used nonce,
verify where the fee went, and reconcile before asking the user to sign a
fresh authorization.
[`test/MulticallFormationFeeForkTest.t.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/test/MulticallFormationFeeForkTest.t.sol)
is a worked Base-mainnet example, including the
`TransferWithAuthorization` typed-data struct.

## Build EIP-712 signatures

cyberRAISE EOIs, deal countersignatures and cyberSign agreements are
EIP-712 typed-data signatures, produced with viem's `signTypedData`. The
`CyberAgreementRegistry` underlies all of them. A round EOI and a deal both
resolve to a registry contract identified by a `bytes32` id, and the party
signs the registry's `SignatureData` under the domain
`{ name: "CyberAgreementRegistry", version: "1", chainId, verifyingContract: registry }`.

The `SignatureData` type comes from the registry implementation and is
independent of the company's version. Read it before building the typed
data:

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

The registry at `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134` on Ethereum,
Base and Arbitrum uses the current type, and the separate zkSync Era
registry uses the older one. With the current type, set `signer` to the
party the signature counts for (the delegator when a delegate signs). Where
the flow allows, take agreement ids from the `ContractCreated` event or a
simulated `createContract`. When a party must sign first, hash the id with
the formula for that registry's type, given in [Sign a
cyberAgreement](sign-a-cyberagreement.md) and
[CyberAgreementRegistry](../reference/contracts/CyberAgreementRegistry.md).

Other signatures use their own domains, each with version `"1"`, the chain
id and the verifying contract:

| Signature | Domain name | Verifying contract |
|---|---|---|
| Officer's escrowed round signature (`EscrowedSignatureData`) | `"RoundManager"` | the RoundManager |
| Relayed `postOffer` / `acceptOffer` / `cancelOffer` / void authorizations | `"DealManager"` | the DealManager |
| Officer's deployment-metadata signature (`RoundSupplementalData`) for `deployCyberCorpAndCreateRound` | `"CyberCorpFactory"` (or `"PumpCorpFactory"`) | the factory |

## Render a LET

`tokenURI(tokenId)` on the LET contract returns a base64 `data:` JSON whose
`image` is an onchain-rendered SVG. Decode the JSON, then render the SVG.
The LET contract has no getter for the raw JSON, so base64-decode the
`data:` payload to get it. Amounts in the metadata are formatted for
display, so read exact amounts with `getCertificateDetails(tokenId)` on the
LET contract.
[CertificateUriBuilder](../reference/contracts/CertificateUriBuilder.md)
documents the JSON fields, the certificate image and how amounts are
formatted.

## Pick the ABI for each company and component

v4 and v5 companies run side by side on the same chains. The factories on
Ethereum, Base and Arbitrum create v5 companies, and an existing company
keeps its deployed version until its owners upgrade it. Pick the ABI per
company and per component, never per chain:

* Read `DEPLOY_VERSION()` on the contract you are about to call:
  `CyberCorp`, `IssuanceManager`, `DealManager`, `RoundManager`,
  `LedgerEntryToken` or `CyberScrip`. v5 components report `"5"`. v4
  components report `"4"`, `"4.1"` (`IssuanceManager`) or `"4.0.1"`
  (`DealManager`). Compare the major version, and refuse a version your
  ABIs do not cover instead of falling back to another.
* Each component upgrades on its own, and nothing onchain forces a company
  to upgrade them together, so do not infer one component's version from
  another's.
* Selectors differ between versions wherever a struct differs. In v5,
  `CyberCertData` and `IssuanceManager.createCertPrinter` carry the
  extension's `seriesData`: `createCertPrinter` is `0x6cf6f4b0` on a v4
  IssuanceManager and `0xfe197ea2` on a v5 one. A call with the other
  version's selector reverts.
* The agreement registry is a single proxy per chain, shared by v4 and v5
  companies. Select its signature type as in [Build EIP-712
  signatures](#build-eip-712-signatures).
* On a v5 factory, `CyberCorpFactory.deployCyberCorpAndCreateRound` takes a
  second officer signature (`metadataSignature`, signed under the
  `"CyberCorpFactory"` domain) and its selector is `0x80d78d40`.

Regenerate ABIs from the source when implementations change.

[Building on the protocol](README.md) maps each MetaLeX product to the
contracts it calls, and [Using the apps](../webapp/README.md) covers the
live apps from a user's side.

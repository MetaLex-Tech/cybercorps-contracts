# mlx_safo_reg_s_v1_1

Status: approved v0.22 substance plus the common Blockchain Notices clause. Both dark and light PDFs are pinned and CID-verified. Browser retrieval verified every PDF byte hash. Registration, compatible runtime acceptance and activation remain pending.

Template ID: `0x6d6c785f7361666f5f7265675f735f76315f3100000000000000000000000000` (`bytes32(bytes("mlx_safo_reg_s_v1_1"))`).
Title: `mlx_safo_reg_s_v1_1`.
Agreement URI: `ipfs://bafybeihq7knnav6watytknp7yf6bm4wsnkzlvsiqoey4kanisbn3x5gf5i`.
Agreement PDF SHA-256: `2a19e1978f71cbc5a1b436e4ad29271834b5a5f4af8f0e4fe0e4524a799245fb`.
Standalone LET instrument URI: `ipfs://bafybeibhk5dbgjmxdqma6p2zepeqmfysyh4pgghwmsxklsrphu3ge53gqm`.
Standalone PDF SHA-256: `0083ea8b4aeb14e0cebb7b406578173fa04985221de44e80920e27e139e0b27b`.

Do not substitute placeholder URIs in a registry or LET. The exact document hashes, legends, CIDs and per-chain receipts belong in the reviewed release manifest. No redline is included in the signed or LET-linked PDFs.

## Global fields (ordered)

| Index | Field |
| --- | --- |
| 0 | `purchaseAmount` |
| 1 | `projectValuation` |
| 2 | `governingJurisdiction` |
| 3 | `disputeResolution` |
| 4 | `schemaVersion` |
| 5 | `minProjectReserve` |
| 6 | `maxUnlockingCliffPeriod` |
| 7 | `maxUnlockingPeriod` |
| 8 | `requiresTokenholderGovernance` |
| 9 | `outsideDateEnabled` |
| 10 | `outsideDate` |
| 11 | `hasUnlockParameters` |
| 12 | `unlockStartTimeType` |
| 13 | `unlockStartTime` |
| 14 | `unlockingPeriod` |
| 15 | `unlockingCliffPeriod` |
| 16 | `unlockingCliffPercentage` |
| 17 | `unlockingIntervalType` |
| 18 | `customProvisions` |

## Party fields (ordered)

| Index | Field |
| --- | --- |
| 0 | `name` |
| 1 | `evmAddress` |
| 2 | `contactDetails` |
| 3 | `investorType` |
| 4 | `investorJurisdiction` |

## Mapping, encoding and runtime

Native SecurityClass 14 is SAFO; earlier enum numbers remain unchanged. This is not a SAFE or SAFTE twin. `seriesData` is empty bytes. Each LET contains the complete version-1 SAFO payload described in [the extension specification](../docs/reference/safo-extension.md).

`purchaseAmount` and `projectValuation` are plain decimal U.S.-dollar strings. Core `investmentAmountUSD` and `issuerUSDValuationAtTimeOfInvestment` store the same values at 18 decimals. The remaining 15 fields follow the extension ABI order: integer fields are raw integer strings, flags are `true`/`false`, and custom provisions are unencoded text. The first two values are not extension fields. Governing law and dispute resolution also populate the existing legalDetails fields.

A founder-approved EOI signs `between <minimum> and <maximum> USD` as purchaseAmount. Allocation writes the actual gross investment into the LET, with unused escrow refunded. FCFS signs its exact amount. SAFO round pricePerUnit is 1e18; nominal dollar units equal actual principal, never shares. Unit Percentage is derived from Purchase Amount divided by Project Valuation. Initial supported payment asset is the configured USDC with six decimals; do not reinterpret other payment assets as USD.

Explicit false and zero are binding values. A disabled Outside Date stores zero; enabled zero means the original Issue Date. Absent unlock parameters are all zero; specified zero parameters remain present. Outside Date is measured in whole calendar years. Original Issue Date is original LET creation: proposal for tickets, allocation for rounds. Settlement/transfer does not restart it. Replacement/migration must preserve original evidence and is outside the initial application flow.

Structure Election, Launch Configuration notices and later conversion administration remain offchain. Native SAFO records an outstanding future ownership instrument; it is not automatically included in SAFE equity dilution, token entitlement or waterfall calculations.

Before activation, verify actual deployed company managers, LET beacon, URI/image builders, SAFO extension proxy/implementation/AUTH, exact registered document/field arrays, payment asset and applicable conditions. A reported version 5 alone is insufficient. New companies also require the coordinated compatible factory references. Preserve legacy/v4/v5 non-SAFO flows. Publication, deployment/upgrades, registry registration, hosted indexing rollout and frontend activation require separate approval and the prescribed develop → staging → production sequence.

## Legal revision

The common Blockchain Notices clause supplements existing delivery methods and permits uniquely associated metadata posting without a duplicate address message. The v1.1 registry name versions the legal packet; schema version 1 and the 19 global / 5 party fields remain unchanged. Existing v1.0 documents retain their identity. Light copies have identical normalized text; see `releases/cyberforms-notices-presentation.json`.

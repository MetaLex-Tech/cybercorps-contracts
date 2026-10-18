# mlx_safe_tw_reg_s_v1_5

Status: approved PDFs pinned; uploaded CIDs match the frozen local bytes. Browser retrieval verified every PDF byte hash; Ethereum, Base and Arbitrum registrations are verified; app release remains pending.

Template ID: `0x6d6c785f736166655f74775f7265675f735f76315f3500000000000000000000` (`bytes32(bytes("mlx_safe_tw_reg_s_v1_5"))`).
Title: `mlx_safe_tw_reg_s_v1_5`.
Agreement URI: `ipfs://bafybeiefrg3mdwoa2vp4ugzs2agbzhfftv3h4zthvsjqrg3eu6j2jsiq4e`.
Agreement PDF SHA-256: `de15d6e2a23d6a551322aba7a08ee2a6585d67cbfa74a31c618d711795c270bd`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFE - Reg S | `ipfs://bafkreibham7rtjgt5ai6axazqrsdwi75ry3wu2iajkue7b6cbk6h4h3odi` | `27033f19a4d3e811e05c1984643b23fd8e376a69004aa84f87c20abc7e1f6e1a` |
| cyberTokenWarrant - Reg S | `ipfs://bafybeiajsjnno3o7l24rcrfoxpt4fgiqddnu45n36vn27grun5roumbr5y` | `113b3c85028b50f9fc6d19fc989c1f8f3d6d2c5e25371bcfecb347d86a12f495` |

## Global fields (ordered)

| Index | Field |
| --- | --- |
| 0 | `purchaseAmount` |
| 1 | `postMoneyValuationCap` |
| 2 | `expirationTime` |
| 3 | `governingJurisdiction` |
| 4 | `disputeResolution` |
| 5 | `exercisePriceMethod` |
| 6 | `exercisePrice` |
| 7 | `unlockStartTimeType` |
| 8 | `unlockStartTime` |
| 9 | `unlockingPeriod` |
| 10 | `latestExpirationTime` |
| 11 | `unlockingCliffPeriod` |
| 12 | `unlockingCliffPercentage` |
| 13 | `unlockingIntervalType` |
| 14 | `tokenCalculationMethod` |
| 15 | `minCompanyReserve` |
| 16 | `tokenPremiumMultiplier` |

## Party fields (ordered)

| Index | Field |
| --- | --- |
| 0 | `name` |
| 1 | `evmAddress` |
| 2 | `contactDetails` |
| 3 | `investorType` |
| 4 | `investorJurisdiction` |

## Encoding and compatibility

Field names, order and plain-text value encoding remain the same as the corresponding v1.4 template. This release adds the approved common Blockchain Notices clause. Metadata posting may constitute delivery without a separate address message. It adds no core contract capability, storage field, agreement-identity rule or signature change.

Use the existing instrument-specific extension for the actual company/LET runtime: legacy/V2 or the supported V3 series/class layout as applicable. This specification does not attest that an extension is deployed on a particular chain. Resolve and verify the implementation, ABI and extension there before issuance. The legal URI and restrictive legends must match the clean instrument in the release manifest.

Core monetary fields retain their existing 18-decimal USD convention. Token scheduling and calculation fields retain the selected extension’s encoding; the notice addition does not authorize changing those units.

The v1.5 registry name versions the agreement packet. It does not renumber the approved Word masters or imply a new protocol version. Existing v1.3/v1.4/custom registrations and their legal URIs remain unchanged.

See `releases/let-v1.5.json` for exact registration arguments. All eight templates are registered and verified on Ethereum, Base and Arbitrum as of October 18, 2026. See [registration readbacks](releases/let-v1.5-registrations.json). The ordered fields match v1.4. Testnets retain their existing forms.

## Presentation copies

The dark PDF is the canonical registration document. Its light copy has identical normalized legal text. Appearance selection must not substitute v1.5 text for an earlier signed agreement. Exact CID pairs and byte hashes are in `releases/cyberforms-notices-presentation.json`. The clean documents contain no redlines or drafting notes.

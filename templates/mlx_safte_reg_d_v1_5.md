# mlx_safte_reg_d_v1_5

Status: approved PDFs pinned; uploaded CIDs match the frozen local bytes. Browser retrieval verified every PDF byte hash; onchain registration remains pending. Do not select these templates for new agreements until registry readbacks pass on the target chain.

Template ID: `0x6d6c785f73616674655f7265675f645f76315f35000000000000000000000000` (`bytes32(bytes("mlx_safte_reg_d_v1_5"))`).
Title: `mlx_safte_reg_d_v1_5`.
Agreement URI: `ipfs://bafybeihxkjefb7oe2tp7k5q2moiare7j62hgiu6xke2elfmzigxcww45uy`.
Agreement PDF SHA-256: `663cdf1847e19058df4da535c8176a59d9bd994e0b3a7c4724085707e77e9138`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFTE - Reg D | `ipfs://bafybeiflnu4w6dw7seec6u7ij73euerxj754pft2rm7tod7u5sfimofbjq` | `f67a4133ee62a6d1c9d1f568e75b254f8e86ae36abc9678d930a59ba25de061a` |

## Global fields (ordered)

| Index | Field |
| --- | --- |
| 0 | `purchaseAmount` |
| 1 | `postMoneyValuationCap` |
| 2 | `protocolUSDValuationAtTimeofInvestment` |
| 3 | `expirationTime` |
| 4 | `governingJurisdiction` |
| 5 | `disputeResolution` |
| 6 | `unlockStartTimeType` |
| 7 | `unlockStartTime` |
| 8 | `unlockingPeriod` |
| 9 | `unlockingCliffPeriod` |
| 10 | `unlockingCliffPercentage` |
| 11 | `unlockingIntervalType` |
| 12 | `tokenCalculationMethod` |
| 13 | `minCompanyReserve` |
| 14 | `tokenPremiumMultiplier` |

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

Core monetary fields retain their existing 18-decimal USD convention. Token scheduling and calculation fields retain the selected extension’s encoding; the notice addition do not authorize changing those units.

The v1.5 registry name versions the agreement packet. It does not renumber the approved Word masters or imply a new protocol version. Existing v1.3/v1.4/custom registrations and their legal URIs remain unchanged.

See `releases/let-v1.5.json` for exact registration arguments. All eight new IDs are unregistered on Ethereum, Base and Arbitrum as of the read-only checks on October 18, 2026. The ordered fields match v1.4. Testnets retain their existing forms.

## Presentation copies

The dark PDF is the canonical registration document. Its light copy has identical normalized legal text. Appearance selection must not substitute v1.5 text for an earlier signed agreement. Exact CID pairs and byte hashes are in `releases/cyberforms-notices-presentation.json`. The clean documents contain no redlines or drafting notes.

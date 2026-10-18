# mlx_safe_tw_reg_d_v1_5

Status: approved PDFs pinned; uploaded CIDs match the frozen local bytes. Browser retrieval verified every PDF byte hash; onchain registration remains pending. Do not select these templates for new agreements until registry readbacks pass on the target chain.

Template ID: `0x6d6c785f736166655f74775f7265675f645f76315f3500000000000000000000` (`bytes32(bytes("mlx_safe_tw_reg_d_v1_5"))`).
Title: `mlx_safe_tw_reg_d_v1_5`.
Agreement URI: `ipfs://bafybeiflv6kiiqbqvdql6hett3yfy5u42pshyuzj7spiziqvfbexnkf2pi`.
Agreement PDF SHA-256: `c7fbfe961ce27cb6f129e033a33ceafb8cb6ee3ed36fa007ac97e25e6c6697e0`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFE - Reg D | `ipfs://bafkreigxkcwvogsvmt6bt52iv6efmubvyopromfjjfbvj5nebokrj5zkey` | `d750ad571a5564fc19f748af88565035c39f1730a9494354f5a40b9514f72a26` |
| cyberTokenWarrant - Reg D | `ipfs://bafybeiaerv4o3kye7ylmf6drzz56p264zs54rwjf37lt2yl535f34cwfwu` | `78b2aee7f8cc0cdba75382d6d1c405c02e3edc1a273d9a2d7a97c126c83abd03` |

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

Core monetary fields retain their existing 18-decimal USD convention. Token scheduling and calculation fields retain the selected extension’s encoding; the notice addition do not authorize changing those units.

The v1.5 registry name versions the agreement packet. It does not renumber the approved Word masters or imply a new protocol version. Existing v1.3/v1.4/custom registrations and their legal URIs remain unchanged.

See `releases/let-v1.5.json` for exact registration arguments. All eight new IDs are unregistered on Ethereum, Base and Arbitrum as of the read-only checks on October 18, 2026. The ordered fields match v1.4. Testnets retain their existing forms.

## Presentation copies

The dark PDF is the canonical registration document. Its light copy has identical normalized legal text. Appearance selection must not substitute v1.5 text for an earlier signed agreement. Exact CID pairs and byte hashes are in `releases/cyberforms-notices-presentation.json`. The clean documents contain no redlines or drafting notes.

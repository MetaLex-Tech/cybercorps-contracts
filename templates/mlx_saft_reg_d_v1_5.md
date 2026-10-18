# mlx_saft_reg_d_v1_5

Status: approved PDFs pinned; uploaded CIDs match the frozen local bytes. Browser retrieval verified every PDF byte hash; Ethereum and Base registrations are verified; Arbitrum registration and app activation remain pending.

Template ID: `0x6d6c785f736166745f7265675f645f76315f3500000000000000000000000000` (`bytes32(bytes("mlx_saft_reg_d_v1_5"))`).
Title: `mlx_saft_reg_d_v1_5`.
Agreement URI: `ipfs://bafybeibnwbcxyvny7uyjuyddhxttqa7kflvx2zjnpmoqc2wwgsjgtmaiua`.
Agreement PDF SHA-256: `ecb6d8bf72c6d0640620c21d6bc5712182f5bfc616ba9aef6327eb7923ab66cc`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFT - Reg D | `ipfs://bafybeiecxy3xuwhamqdeepd3vn4n46p7vy7jn2n4slcsaezxtphwzpet6q` | `a526fa740193476a9b7a6aa47bb4b2964be39d625c9142a4235e80444f085d59` |

## Global fields (ordered)

| Index | Field |
| --- | --- |
| 0 | `purchaseAmount` |
| 1 | `protocolValuationCap` |
| 2 | `governingJurisdiction` |
| 3 | `disputeResolution` |
| 4 | `unlockStartTimeType` |
| 5 | `unlockStartTime` |
| 6 | `unlockingPeriod` |
| 7 | `unlockingCliffPeriod` |
| 8 | `unlockingCliffPercentage` |
| 9 | `unlockingIntervalType` |

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

See `releases/let-v1.5.json` for exact registration arguments. All eight templates are registered and verified on Ethereum and Base as of October 18, 2026. Arbitrum remains pending. See [registration readbacks](releases/let-v1.5-registrations.json). The ordered fields match v1.4. Testnets retain their existing forms.

## Presentation copies

The dark PDF is the canonical registration document. Its light copy has identical normalized legal text. Appearance selection must not substitute v1.5 text for an earlier signed agreement. Exact CID pairs and byte hashes are in `releases/cyberforms-notices-presentation.json`. The clean documents contain no redlines or drafting notes.

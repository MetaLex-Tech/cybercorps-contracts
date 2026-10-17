# mlx_saft_reg_s_v1_4

Status: PDF published and hash-verified; registered on Ethereum, Base and Arbitrum. Full title, URI and ordered field readbacks match. See `releases/let-v1.4.json` for transaction receipts and blocks.

Template ID: `0x6d6c785f736166745f7265675f735f76315f3400000000000000000000000000` (`bytes32(bytes("mlx_saft_reg_s_v1_4"))`).
Title: `mlx_saft_reg_s_v1_4`.
Agreement URI: `ipfs://bafybeiecsg2k26yfzajbirs4mqveyk5se3elv3tqft3mo3br4nl4xt7hcm`.
Agreement PDF SHA-256: `e8a69deff0d5b88a0bc8ec336e7ee6a8a4a186587f0ec47ff936285777df3763`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFT - Reg S | `ipfs://bafybeibgpx4gjuf2ddgnn6eayelepvtknccefnumrwhl3ebhr63j5dv6xq` | `b5af81ea3c21aae7ee7762f40f3b8b30194d741a50839a040346bfd4651900b0` |

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

Field names, order and plain-text value encoding remain the same as the corresponding v1.3 template. This legal-text release adds no core contract capability, storage field, agreement-identity rule or signature change.

Use the existing instrument-specific extension for the actual company/LET runtime: legacy/V2 or the supported V3 series/class layout as applicable. This specification does not attest that an extension is deployed on a particular chain. Resolve and verify the implementation, ABI and extension there before issuance. The legal URI and restrictive legends must match the clean instrument in the release manifest.

Core monetary fields retain their existing 18-decimal USD convention. Token scheduling and calculation fields retain the selected extension’s encoding; the legal Mapping corrections do not authorize changing those units.

The v1.4 registry name versions the agreement packet. It does not renumber the approved Word masters or imply a new protocol version. Existing v1.3/custom registrations and their legal URIs remain unchanged.

See `releases/let-v1.4.json` for the exact approved registration arguments and the release package for the offline CAR roots. Registration is per chain. All three production chains passed full registry readbacks, and the PDFs passed pin and fetch verification. Testnet registration is not included.

# mlx_safte_reg_s_v1_4

Status: PDF published and hash-verified; registered on Ethereum, Base and Arbitrum. Full title, URI and ordered field readbacks match. See `releases/let-v1.4.json` for transaction receipts and blocks.

Template ID: `0x6d6c785f73616674655f7265675f735f76315f34000000000000000000000000` (`bytes32(bytes("mlx_safte_reg_s_v1_4"))`).
Title: `mlx_safte_reg_s_v1_4`.
Agreement URI: `ipfs://bafybeih2kkairhmeud33qu4ks3e47kzwgn3eqgpqzwluxumnwcs2q6k7qy`.
Agreement PDF SHA-256: `f90018a197abffe21ce5d98d56c26038c8f3b84747eb8d60a91703a95738fd99`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFTE - Reg S | `ipfs://bafybeifyfhfbors2casddsimrtg633dripjc5v37itgjetiph5xwjhzmoy` | `769f2fbb562a0a3ae60ba461826fa5fe068869b8c56302ec110f65cdd0205d06` |

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

Field names, order and plain-text value encoding remain the same as the corresponding v1.3 template. This legal-text release adds no core contract capability, storage field, agreement-identity rule or signature change.

Use the existing instrument-specific extension for the actual company/LET runtime: legacy/V2 or the supported V3 series/class layout as applicable. This specification does not attest that an extension is deployed on a particular chain. Resolve and verify the implementation, ABI and extension there before issuance. The legal URI and restrictive legends must match the clean instrument in the release manifest.

Core monetary fields retain their existing 18-decimal USD convention. Token scheduling and calculation fields retain the selected extension’s encoding; the legal Mapping corrections do not authorize changing those units.

The v1.4 registry name versions the agreement packet. It does not renumber the approved Word masters or imply a new protocol version. Existing v1.3/custom registrations and their legal URIs remain unchanged.

See `releases/let-v1.4.json` for the exact approved registration arguments and the release package for the offline CAR roots. Registration is per chain. All three production chains passed full registry readbacks, and the PDFs passed pin and fetch verification. Testnet registration is not included.

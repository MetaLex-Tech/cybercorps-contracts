# mlx_safte_reg_d_v1_4

Status: PDF published on IPFS and verified against the approved SHA-256; template registration pending on Ethereum, Base and Arbitrum.

Template ID: `0x6d6c785f73616674655f7265675f645f76315f34000000000000000000000000` (`bytes32(bytes("mlx_safte_reg_d_v1_4"))`).
Title: `mlx_safte_reg_d_v1_4`.
Agreement URI: `ipfs://bafybeid7pq7j3t24kw5cd5cyjr76nlsa3syenoemah3hm64umc34zhwwa4`.
Agreement PDF SHA-256: `0e5c4851d738909c26d339c9c75596363c989aba97861d19a4ef35aba1bab265`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFTE - Reg D | `ipfs://bafybeidpzvosnjjrng7qjbetnwfmolx3eq3pmji743bhy265adxh2e4qgq` | `3f6bb2dc52468008df33d8937184c766719d84a0d415c5990b1eb97a4f3b36f3` |

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

See `releases/let-v1.4.json` for the exact approved registration arguments and the release package for the offline CAR roots. Registration is per chain. The PDFs passed pin and fetch verification. Compare all registry fields on each target chain before enabling this version.

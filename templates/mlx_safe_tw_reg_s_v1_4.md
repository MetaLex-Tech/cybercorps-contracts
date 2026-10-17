# mlx_safe_tw_reg_s_v1_4

Status: prepared locally; PDF not pinned and template not registered.

Template ID: `0x6d6c785f736166655f74775f7265675f735f76315f3400000000000000000000` (`bytes32(bytes("mlx_safe_tw_reg_s_v1_4"))`).
Title: `mlx_safe_tw_reg_s_v1_4`.
Agreement URI: `ipfs://bafybeibq73gmxouxjdoqzvuk5nuu5d4i4gmdyuncps3o736v6ehjjzymsu`.
Agreement PDF SHA-256: `f0c83538e0b2c2da79cb5c4a9b3e8efd69bc676df45939129feb65a9cc589685`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFE - Reg S | `ipfs://bafkreidp4t7h6xirl7e4lenuywtpauvsmkcgle4exe6xqfid4pfzdcxg4i` | `6fe4fe7f5d115fc9c591b4c5a6f052b26284659384b93d781503e3cb918ae6e2` |
| cyberTokenWarrant - Reg S | `ipfs://bafybeiezzfyd5chdsdmakkdmdqgzulf5yjafvl7egbs5f2hrmc5mlmqqvu` | `20129f33a49ddaea9dc90e6f886cdbee064424917e75764bc5684c07d41b3fb7` |

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

Field names, order and plain-text value encoding remain the same as the corresponding v1.3 template. This legal-text release adds no core contract capability, storage field, agreement-identity rule or signature change.

Use the existing instrument-specific extension for the actual company/LET runtime: legacy/V2 or the supported V3 series/class layout as applicable. This specification does not attest that an extension is deployed on a particular chain. Resolve and verify the implementation, ABI and extension there before issuance. The legal URI and restrictive legends must match the clean instrument in the release manifest.

Core monetary fields retain their existing 18-decimal USD convention. Token scheduling and calculation fields retain the selected extension’s encoding; the legal Mapping corrections do not authorize changing those units.

The v1.4 registry name versions the agreement packet. It does not renumber the approved Word masters or imply a new protocol version. Existing v1.3/custom registrations and their legal URIs remain unchanged.

See `releases/let-v1.4.json` for the exact proposed registration arguments and the release package for the offline CAR roots. Registration is per chain. Pin and fetch-verify every referenced document, then compare all registry fields before enabling this version.

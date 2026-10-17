# mlx_saft_reg_d_v1_4

Status: prepared locally; PDF not pinned and template not registered.

Template ID: `0x6d6c785f736166745f7265675f645f76315f3400000000000000000000000000` (`bytes32(bytes("mlx_saft_reg_d_v1_4"))`).
Title: `mlx_saft_reg_d_v1_4`.
Agreement URI: `ipfs://bafybeihtu4tsfei7hm54gfscfcjqy4hf47l3nlplaza2tt4xgzituxxs5i`.
Agreement PDF SHA-256: `1d7168622ac6542f77c8a4a9f287c39db6a307005296ade473c116667b52a8be`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFT - Reg D | `ipfs://bafybeigdj4enukctao6wuqockermxzpb7wivs2xta2ppgnazyb7qgogqri` | `ce9611df4699728d57b999e2376b36744b6db4a09232ed1b0cc7dc1bbdf606a6` |

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

See `releases/let-v1.4.json` for the exact proposed registration arguments and the release package for the offline CAR roots. Registration is per chain. Pin and fetch-verify every referenced document, then compare all registry fields before enabling this version.

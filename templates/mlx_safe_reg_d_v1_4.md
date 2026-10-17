# mlx_safe_reg_d_v1_4

Status: prepared locally; PDF not pinned and template not registered.

Template ID: `0x6d6c785f736166655f7265675f645f76315f3400000000000000000000000000` (`bytes32(bytes("mlx_safe_reg_d_v1_4"))`).
Title: `mlx_safe_reg_d_v1_4`.
Agreement URI: `ipfs://bafybeibemqrqlcorwqyt5z5sfxuw3mnmptchuudjbetddwqsl4vwuc52ba`.
Agreement PDF SHA-256: `dabff827e54475ea9dabd621b61d54fb71625ea2cd73a5da96ef590cc58ad31b`.

The combined PDF contains the reusable cyberSPA and its attached Exhibit A instrument(s). Standalone instrument URIs below are the LET legalContractUri values. No redline is part of either document.

| LET instrument | legalContractUri | PDF SHA-256 |
| --- | --- | --- |
| cyberSAFE - Reg D | `ipfs://bafkreigvdb3tl4gqjhl4kltitwx2ap6oggpusn7tfe6g5eadoozyc4kq34` | `d5187735f0d049d7c52e689dafa03fce319f4937f3293c6e900373b3817150df` |

## Global fields (ordered)

| Index | Field |
| --- | --- |
| 0 | `purchaseAmount` |
| 1 | `postMoneyValuationCap` |
| 2 | `expirationTime` |
| 3 | `governingJurisdiction` |
| 4 | `disputeResolution` |

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

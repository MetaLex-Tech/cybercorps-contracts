# SAFO extension field specification

The schema implements the metadata fields for the Simple Agreement for Future
Ownership based on legal draft v0.22. It is an implementation specification,
not a registered agreement template. The prepared Reg D and Reg S template
specifications assign their IDs; publication CIDs and live extension addresses
remain pending a separately approved release.

## Storage and decoding

`SAFOExtension` decodes `abi.encode(SAFOData)` from each LET's
`CertificateDetails.extensionData`. It implements `ICertificateExtension`,
identifies itself with `keccak256("SAFO")`, and emits a `SAFODetails` JSON
fragment. It does not read or inherit series/class terms. Its typed encoder,
decoder, validator and renderer all reject unsupported schema versions or
inconsistent optional fields. The URI builder skips an empty payload, so these
helpers are not an issuance-time enforcement hook.

| Field in ABI order | Solidity type | Meaning and encoding |
|---|---|---|
| `schemaVersion` | `uint8` | Must be `1`. |
| `minProjectReserve` | `uint256` | Percentage points with four decimals: `200000` = 20%; range 0–1000000. Mandatory presence; no invented positive minimum. |
| `maxUnlockingCliffPeriod` | `uint256` | Maximum cliff/delay/suspension duration in seconds. |
| `maxUnlockingPeriod` | `uint256` | Maximum duration in seconds after the Token Launch Event to full unlocking. |
| `requiresTokenholderGovernance` | `bool` | Whether the additional governance condition in Qualifying Launch clause (b) applies. |
| `outsideDateEnabled` | `bool` | Express issuance-time choice whether §1.7 applies. |
| `outsideDate` | `uint256` | Whole calendar years after the original Issue Date. Must be zero when disabled. Enabled zero means the Issue Date itself. Calendar anniversaries are not approximated by 365-day seconds. |
| `hasUnlockParameters` | `bool` | Whether the following six fields record the offchain Launch Configuration's schedule. |
| `unlockStartTimeType` | `UnlockStartTimeType` | 0 = agreement execution, 1 = Token Launch Event, 2 = specified time. Existing enum member 0 is named `tokenWarrantTime`; SAFO JSON labels it `agreementExecutionTime`. |
| `unlockStartTime` | `uint256` | Unix seconds for type 2; zero for other types. |
| `unlockingPeriod` | `uint256` | Whole intervals of `unlockingIntervalType`. |
| `unlockingCliffPeriod` | `uint256` | Whole intervals of `unlockingIntervalType`. |
| `unlockingCliffPercentage` | `uint256` | Percentage points with four decimals; range 0–1000000. |
| `unlockingIntervalType` | `UnlockingIntervalType` | 0 blocks, 1 seconds, 2 hours, 3 days, 4 months. |
| `customProvisions` | `string` | Per-LET legal provisions; JSON escaped on rendering. |

When `hasUnlockParameters` is false, all six schedule values must be raw zero,
including both enums. When true, zero values are actual recorded values, not
absence. The renderer emits presence flags and governance as JSON booleans,
all numeric values as strings of their raw integers, and enum labels as
strings. It omits the disabled Outside Date and absent schedule fields.

Purchase Amount and Project Valuation remain 18-decimal U.S. dollar amounts
in core `CertificateDetails`. The SAFO does not use `unitsRepresented` to
calculate Unit Percentage. `minProjectReserve` has no separate presence flag:
a valid versioned payload is required even where the expressly agreed floor
is zero. Empty bytes are not a valid SAFO payload.

## Legal facts outside the payload

Structure Election and the Launch Configuration are evidenced by offchain
notices. The applicable Token Calculation Method is derived from the Selected
Structure, never from the existing SAFTE/TokenWarrant calculation enum. A
copied schedule does not replace the notice or the constraints in §3. The
original Issue Date survives transfers, replacement, void/reissue and migration.

Company identity comes from the associated CyberCorp. The original issuance
endorsement identifies the investor and links to the agreement registry and
agreement ID, whose party fields supply contact details, investor entity type
and jurisdiction. Governing Jurisdiction is the value labeled `Governing law`
in core `legalDetails`. Aggregate Unit Percentages require the applicable
Mappings, company ledger records and Structure Election Notices.

## Validation limits and release gates

The extension validates encoding and local bounds. It does not enforce the
SAFO's issuance, payment, launch, transfer, amendment or conversion rules and
does not determine whether a proposed schedule complies with the agreement.
Opaque bytes can still be written through existing core entry points. Issuance
tooling must validate every payload and require explicit user selection of
the optional terms before signing.

The implementation follows the existing UUPS/BorgAuth pattern: implementation
initialization is disabled; the proxy is initialized once with nonzero AUTH;
only an owner authorized by that AUTH can upgrade it. Deploy a separate SAFO
proxy. Do not point existing instrument payloads at this decoder or upgrade a
SAFE/SAFTE proxy to it. Schema tags are layout guards, not proof of instrument
identity or authorization to bind an extension.

Before live issuance, separately complete and approve native SAFO security
classification and application support, any required component upgrades,
deployment with verified proxy/AUTH/runtime versions, legal PDF/IPFS upload,
per-chain registry registration, and end-to-end issuance/rendering tests
against the target company's deployed versions. The implementation branch appends native `SecurityClass.SAFO` (14) and tests its actual issuance, rendering, ticket settlement and round allocation. Deployed contracts still require separate capability verification and upgrades; source support is not live acceptance. Both [Reg D](../../templates/mlx_safo_reg_d_v1_0.md) and [Reg S](../../templates/mlx_safo_reg_s_v1_0.md) have prepared 19-field template specifications.

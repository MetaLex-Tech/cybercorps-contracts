# Agreement templates

Reusable legal-instrument templates live in the
[`/templates`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/templates)
directory. Registration in `CyberAgreementRegistry` is per chain, so a
template can exist on one chain and not another: the cyberSTOCK template
below is registered on Ethereum and Base Sepolia but not on Base or
Arbitrum. Call `getTemplateDetails(templateId)` on the target chain before
relying on a template; it reverts `TemplateDoesNotExist` for an
unregistered id.

## cyberSAFE

| Template | Style | Filing path |
|---|---|---|
| `MetaLeX cyberSAFE US style Reg D v 1.0.md` | YC post-money | Reg D (US) |
| `MetaLeX cyberSAFE UK Cayman style Reg S v 1.0.md` | YC post-money | Reg S (UK / Cayman) |
| `MetaLeX cyberSAFE jx-neutral-style Reg D raise v 1.0.md` | Jurisdiction-neutral | Reg D (US) |
| `MetaLeX cyberSAFE jx-neutral-style Reg S raise v 1.0.md` | Jurisdiction-neutral | Reg S |
| `mlx_safe_reg_d_v1_3.md` / `mlx_safe_reg_s_v1_3.md` | v1.3 series | Reg D / Reg S |

## cyberSAFT

| Template | Filing path |
|---|---|
| `MetaLeX cyberSAFT reg D v.1.0.md` | Reg D |
| `MetaLeX cyberSAFT Reg S raise v 1.0.md` | Reg S |
| `mlx_saft_reg_d_v1_3.md` / `mlx_saft_reg_s_v1_3.md` | v1.3 series |

## cyberSAFTE

* `mlx_safte_reg_d_v1_3.md`: Reg D, v1.3.

## cyberSTOCK

* `mlx_cyberstock_reg_d_v1_0.md`: a tokenized-share subscription
  agreement, Reg D, v1.0, with template id
  `bytes32(bytes("metalex_cyberstock_reg_d_v1_0"))`.

## cyberTokenWarrant

| Template | Filing path |
|---|---|
| `MetaLeX cyberTokenWarrant a16z US style reg D v 1.0.md` | a16z-derived, Reg D (US) |
| `MetaLeX cyberTokenWarrant a16z jx-neutral-style-issuer Reg D raise v 1.0.md` | jx-neutral, Reg D |
| `MetaLeX cyberTokenWarrant a16z-jx-neutral-style-issuer Reg S raise v 1.0.md` | jx-neutral, Reg S |
| `MetaLeX cyberTokenWarrant non-US Reg S v 1.0.md` | Reg S |
| `mlx_safe_tw_reg_d_v1_3.md` / `mlx_safe_tw_reg_s_v1_3.md` | v1.3 series |

## MetaDAO Futarchy Governance SPC

* `MetaDAO Futarchy Governance SPC - Board Consent - Approval of SegCo v 1.0.md`
* `MetaDAO Futarchy Governance SPC - SegCo combined v 1.0.md`

## LeXcheX agreement

* `MetaLeX LeXCheX Agreement.md`, which a credential subject countersigns
  on receiving a LeXcheX credential.

## Custom templates

Anyone can register a template with
`CyberAgreementRegistry.createTemplate(templateId, title,
legalContractUri, globalFields, partyFields)`. Template ids are
caller-chosen `bytes32` values (by convention, `bytes32(bytes("<name>"))`)
and must be unused, and a template's fields cannot be overwritten once
created. The directory also holds a combined cyberSAFE and
cyberTokenWarrant template prepared for one issuer, as an example of a
custom variant.

Standalone agreements (`createStandaloneContractAndSign`) skip this step.
The registry derives the template id from
`keccak256(abi.encode(title, legalContractUri, globalFields, partyFields))`
and registers the template on first use.

The two `DEPRECATED-*` files in the directory (`SAFE-version-0-1`,
`SAFEplusT-version-0-1`) are not for new agreements.

## LET legal release v1.4

These eight packets and eight standalone instruments are published on IPFS.
Their CIDs and fetched bytes match the approved release manifest. Registration
and full field readbacks are complete on Ethereum, Base and Arbitrum.
Each packet combines the reusable cyberSPA with its Exhibit A instrument(s).
The registry URI identifies that packet; each LET uses its matching standalone
instrument URI. Existing v1.3 and custom templates remain unchanged.

| Instrument | Reg D specification | Reg S specification |
|---|---|---|
| SAFE | [mlx_safe_reg_d_v1_4](../../templates/mlx_safe_reg_d_v1_4.md) | [mlx_safe_reg_s_v1_4](../../templates/mlx_safe_reg_s_v1_4.md) |
| SAFE + Token Warrant | [mlx_safe_tw_reg_d_v1_4](../../templates/mlx_safe_tw_reg_d_v1_4.md) | [mlx_safe_tw_reg_s_v1_4](../../templates/mlx_safe_tw_reg_s_v1_4.md) |
| SAFT | [mlx_saft_reg_d_v1_4](../../templates/mlx_saft_reg_d_v1_4.md) | [mlx_saft_reg_s_v1_4](../../templates/mlx_saft_reg_s_v1_4.md) |
| SAFTE | [mlx_safte_reg_d_v1_4](../../templates/mlx_safte_reg_d_v1_4.md) | [mlx_safte_reg_s_v1_4](../../templates/mlx_safte_reg_s_v1_4.md) |

[Exact approved registration arguments](../../templates/releases/let-v1.4.json)
preserve predecessor field order and encoding. The release package includes
offline CAR roots, PDF hashes and successful gateway verification receipts.
The manifest records confirmed transactions and receipt blocks for all three chains.
Testnets retain their existing templates. The release requires no existing-family core protocol change.
SAFO integration and upgrades are a separate review; no SAFO registration is
included in this release manifest.

## See also

* [Sign a cyberAgreement](../how-to/sign-a-cyberagreement.md)
* [`CyberAgreementRegistry`](contracts/CyberAgreementRegistry.md)

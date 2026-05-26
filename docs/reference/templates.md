# Agreement templates

Reusable legal-instrument templates live in the
[`/templates`](https://github.com/MetaLex-Tech/cybercorps-contracts/tree/develop/templates)
directory and are pre-registered in `CyberAgreementRegistry`.

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

* `mlx_safte_reg_d_v1_3.md` — Reg D, v1.3.

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

* `MetaLeX LeXCheX Agreement.md` — countersigned by a credential subject when
  receiving a LeXcheX credential.

## Custom templates

Issuers can register their own templates with
`CyberAgreementRegistry.registerTemplate(...)`. For example, the
`Three Prime Custom cyberSAFE and cyberTokenWarrant.md` template demonstrates
a custom variant.

## See also

* [How-to: Sign a cyberAgreement](../how-to/sign-a-cyberagreement.md)
* [`CyberAgreementRegistry`](contracts/CyberAgreementRegistry.md)

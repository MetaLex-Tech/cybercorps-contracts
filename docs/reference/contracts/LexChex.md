# LexChex / LexChexMinter

**LeXcheX** is MetaLeX's onchain accreditation / KYC-AML credential layer.
It manages soulbound credentials that downstream conditions (e.g.,
`lexchexCondition`) can check.

* **Sources:**
  [`src/creds/lexchex.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/lexchex.sol),
  [`src/creds/lexchexMinter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/lexchexMinter.sol)
* **Reference consumer UI:**
  [`apps/lexchex-web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/lexchex-web)
  (`lexchex.metalex.tech`).

## Credential dimensions

* **KYC/AML** — identity verification (individual or legal entity).
* **Accreditation** — SEC Rule 501(a) status. The reference UI supports both
  traditional documentation flows and onchain net-worth proof using
  wallet-bound assets (target $1M for individuals, $5M for entities).
* **Qualified-purchaser** — Investment Company Act §3(c)(7) status.
* **Jurisdiction tags** — for Reg S / non-US gating, complementing the
  zkPassport-based `NonUSNationalityCondition`.

## Minting

The `LexChexMinter` mints a soulbound (non-transferable, wallet-bound) NFT
certificate to the credentialed address. The user must countersign the
LeXcheX agreement (see [Templates](../templates.md)) onchain.

## Selected public interface

```solidity
function mint(address subject, CredentialData calldata) external; // ORACLE_AUTHORITY
function revoke(uint256 tokenId) external;
function credentialOf(address subject) external view returns (CredentialData memory);
function hasAccreditation(address subject) external view returns (bool);
function hasKyc(address subject) external view returns (bool);
function isNonUs(address subject) external view returns (bool);
```

## See also

* [Conditions → `lexchexCondition`](../conditions.md#lexchexcondition)
* [LeXcheX agreement template](../templates.md#lexchex-agreement)

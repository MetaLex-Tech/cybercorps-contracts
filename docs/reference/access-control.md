# Access control (BorgAuth)

All contracts use **BorgAuth** role-based access control with multi-authority
requirements. BorgAuth lives in [borg-core](https://github.com/MetaLex-Tech/borg-core).

Roles map cleanly to the governance roles defined in the entity's
constitutional documents (officers, managers, general partners, directors,
or analogues).

## Roles used by the protocol

| Role | Held by (typical) | Permits |
|---|---|---|
| `ADMIN_AUTHORITY` | Board / managers (Safe multisig) | Grant and revoke all other roles. |
| `ISSUER_AUTHORITY` | Officer | Mint and revoke cyberCERTs. Manage scripify/descripify conditions. Reserve / release shares. |
| `OFFICER_AUTHORITY` | Officer | Approve registrations. Sign agreements on behalf of the entity. Manage transfer hooks. Open / close rounds. Approve deals. |
| `DIRECTOR_AUTHORITY` | Director | Authorise share classes (`setAuthorized`). Register extensions on `CyberCertPrinter`. Set max holders. |
| `SECRETARY_AUTHORITY` | Secretary | Endorse cyberCERTs. Update legends. |
| `UPGRADE_AUTHORITY` | Board / managers | Co-approve UUPS implementation upgrades for this cyberCORP. |
| `COMPLIANCE_AUTHORITY` | Officer / compliance team | Operate force-transfer / force-burn / freeze / blocklist (if not renounced). |
| `METALEX_ADMIN` | MetaLeX (factories only) | Set reference implementations on factories. Never applies to deployed cyberCORPs. |

## Granting / revoking

```solidity
IBorgAuth auth = IBorgAuth(cyberCorp.auth());
auth.grantRole(OFFICER_AUTHORITY, newCfo);
auth.revokeRole(OFFICER_AUTHORITY, oldCfo);
```

Most role mutations themselves require `ADMIN_AUTHORITY` (typically a board
multisig).

## Multi-authority requirements

Some state transitions are gated on the *conjunction* of two roles. For
example, an `OFFICER_AUTHORITY` + `SECRETARY_AUTHORITY` co-signature may be
required to endorse a cert in some configurations (mirroring corporate
formalities).

## See also

* [How-to: Configure BorgAuth roles](../how-to/configure-roles.md)
* [borg-core](https://github.com/MetaLex-Tech/borg-core)

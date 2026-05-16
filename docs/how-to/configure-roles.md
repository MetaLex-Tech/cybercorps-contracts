# Configure BorgAuth roles

All authority on a cyberCORP flows through **BorgAuth**, a multi-authority
role-based access control framework (see
[borg-core](https://github.com/MetaLex-Tech/borg-core)).

Roles correspond to governance roles in the entity's constitutional documents
(officers, directors, secretary, manager, general partner, etc.). The cyberCORP
makes no assumption about which roles exist — you wire them.

## When to use this guide

You need to grant, revoke, or rotate authority on an existing cyberCORP.

## Steps

### 1. Identify the role

Common BorgAuth role identifiers used by the protocol:

| Role | Permitted actions |
|---|---|
| `ISSUER_AUTHORITY` | Mint and revoke cyberCERTs via `IssuanceManager`. |
| `OFFICER_AUTHORITY` | Co-sign on registration approvals, sign agreements on the entity's behalf. |
| `DIRECTOR_AUTHORITY` | Approve resolutions, change officers, authorise share classes. |
| `SECRETARY_AUTHORITY` | Endorse cyberCERTs (e.g., legend updates). |
| `UPGRADE_AUTHORITY` | Co-approve UUPS implementation upgrades for this cyberCORP. |
| `COMPLIANCE_AUTHORITY` | Operate force-transfer / force-burn / freeze / blocklist powers on cyberSCRIP (if not renounced). |

See [Access control reference](../reference/access-control.md) for the
authoritative list.

### 2. Grant a role

```solidity
IBorgAuth auth = IBorgAuth(cyberCorp.auth());
auth.grantRole(ISSUER_AUTHORITY, newOfficer);
```

The call requires the existing `ADMIN_AUTHORITY` (typically the board /
managers, often a multisig).

### 3. Revoke a role

```solidity
auth.revokeRole(ISSUER_AUTHORITY, departedOfficer);
```

### 4. Rotate (atomic)

For a clean swap, batch into one transaction (e.g., from a Safe multisig):

```solidity
auth.grantRole(OFFICER_AUTHORITY, newCfo);
auth.revokeRole(OFFICER_AUTHORITY, oldCfo);
```

## Verification

```solidity
bool hasIt = auth.hasRole(OFFICER_AUTHORITY, newCfo);
```

## Related

* [Access control reference](../reference/access-control.md)
* [The role of MetaLeX](../explanation/role-of-metalex.md) — why no
  protocol-level admin keys exist over your roles.

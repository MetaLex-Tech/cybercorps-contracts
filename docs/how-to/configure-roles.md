---
description: Add and remove officers, set BorgAuth levels directly, and transfer or renounce ownership of a cyberCORP's ACL
---

# Configure BorgAuth roles

A cyberCORP holds its authority in a BorgAuth ACL. Roles are numeric levels,
and a check passes for any level at or above the one it requires. The full
model is in [Access control](../reference/access-control.md).

## Role levels on a cyberCORP

| Level | Meaning |
|---|---|
| `99` (`OWNER_ROLE`) | Owner. Can grant and revoke roles and approve upgrades. Held by the suite's manager contracts and, from deployment, by the deploying factory. |
| `98` (`ADMIN_ROLE`) | Admin. Gates operational functions such as scrip compliance actions, hook updates and opening a Ledger Entry Token (LET) contract's transfer switches. Any level `≥ 98` passes. |
| `200` | Company officer. Set for an officer's address. Because `200 ≥ 99`, officers also pass `onlyOwner`. |
| `0` | No authority. |

## Manage officers through the CyberCorp

`CyberCorp.addOfficer` records an officer and grants their address level
`200` in one call:

```solidity
import {CompanyOfficer} from "src/CyberCorpConstants.sol";

CyberCorp(cyberCorp).addOfficer(CompanyOfficer({
    eoa:     newOfficer,
    name:    "Sam Officer",
    contact: "sam@acme.example",
    title:   "Chief Financial Officer"
}));
```

Adding an address already listed as an officer reverts `DuplicateOfficer`.
An address that already holds a level above `200` keeps it, so the grant
never downgrades a custom role.

`updateOfficer` replaces the record at an index with a new title, contact
or address. When the address changes, the old address loses its level-`200`
grant and the new one receives it under the same rules as `addOfficer`:

```solidity
CyberCorp(cyberCorp).updateOfficer(2, CompanyOfficer({
    eoa:     replacementOfficer,
    name:    "Pat Officer",
    contact: "pat@acme.example",
    title:   "Chief Financial Officer"
}));
```

`removeOfficer` and `removeOfficerAt` each delete the officer record and
revoke the level-`200` grant:

```solidity
CyberCorp(cyberCorp).removeOfficer(departedOfficer);
// or by index:
CyberCorp(cyberCorp).removeOfficerAt(2);
```

Removal zeroes a level only when it is exactly `200`, so a custom level
granted directly on the BorgAuth survives the officer's removal.
`addOfficer` refuses duplicates, but an existing company's officer list can
still hold one address at several indexes. In that case the address keeps
its role while any entry still lists it, and only removing or updating away
its last entry revokes it.

## Set a level directly on the BorgAuth

`updateRole` on the BorgAuth contract sets any level. The caller must hold
`OWNER_ROLE`.

```solidity
BorgAuth auth = BorgAuth(BorgAuthACL(cyberCorp).AUTH());
auth.updateRole(someAddress, 200);   // grant officer level
auth.updateRole(someAddress, 0);     // revoke
```

The factory that deployed the company starts with level `99` on its
BorgAuth and does not give it up on its own. `auth.userRoles(factory)`
shows whether your company still grants it. [Access
control](../reference/access-control.md) lists every role the protocol
assigns.

## Transfer ownership in two steps

```solidity
auth.initTransferOwnership(newOwner);   // by current owner
// then, as newOwner:
auth.acceptOwnership();
```

## Renounce your own level

`auth.zeroOwner()` sets the caller's level to `0` and permanently removes
its admin control.

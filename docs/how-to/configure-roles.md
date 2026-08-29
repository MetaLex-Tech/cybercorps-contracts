---
description: Grant and revoke BorgAuth authority levels on a cyberCORP suite
---

# Configure BorgAuth roles

Authority on a cyberCORP is held in its **BorgAuth** ACL. Roles are numeric
levels in a hierarchy — see [Access control](../reference/access-control.md).

## The levels you'll use

| Level | Meaning |
|---|---|
| `99` (`OWNER_ROLE`) | Owner. Can grant/revoke roles. Held by the suite's manager contracts. |
| `98` (`ADMIN_ROLE`) | Admin. Gates operational functions (e.g. scrip compliance actions, hook updates). Any level `≥ 98` passes. |
| `200` | Company officer. Set for an officer's address; `200 ≥ 99`, so officers also pass `onlyOwner`. |
| `0` | No authority. |

## Grant an officer

The simplest path is `CyberCorp.addOfficer`, which records the officer **and**
grants their address level `200`:

```solidity
import {CompanyOfficer} from "src/CyberCorpConstants.sol";

CyberCorp(cyberCorp).addOfficer(CompanyOfficer({
    eoa:     newOfficer,
    name:    "Sam Officer",
    contact: "sam@acme.example",
    title:   "Chief Financial Officer"
}));
```

Adding an address already listed as an officer reverts (`DuplicateOfficer`),
and an address already holding a level *above* `200` keeps it — the grant
never downgrades a custom role.

## Update an officer

`updateOfficer` replaces the record at an index — new title, contact, or a
new address. When the address changes, the old one's level-`200` grant is
revoked and the new one is granted under the same rules as `addOfficer`:

```solidity
CyberCorp(cyberCorp).updateOfficer(2, CompanyOfficer({
    eoa:     replacementOfficer,
    name:    "Pat Officer",
    contact: "pat@acme.example",
    title:   "Chief Financial Officer"
}));
```

## Remove an officer

Either removes the officer record and revokes the level-`200` grant:

```solidity
CyberCorp(cyberCorp).removeOfficer(departedOfficer);
// or by index:
CyberCorp(cyberCorp).removeOfficerAt(2);
```

Removal only zeroes a level that is exactly `200` — a custom level granted
directly on the BorgAuth survives the officer's removal.

## Grant or revoke a role directly

To set any level directly, call `updateRole` on the BorgAuth contract. The
caller must hold `OWNER_ROLE`.

```solidity
BorgAuth auth = BorgAuth(BorgAuthACL(cyberCorp).AUTH());
auth.updateRole(someAddress, 200);   // grant officer level
auth.updateRole(someAddress, 0);     // revoke
```

## Transfer ownership

Two-step, on the BorgAuth contract:

```solidity
auth.initTransferOwnership(newOwner);   // by current owner
// then, as newOwner:
auth.acceptOwnership();
```

## Renounce

`auth.zeroOwner()` sets the caller's level to `0`, permanently removing its
admin control.

## Related

* [Access control reference](../reference/access-control.md)

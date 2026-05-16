# Configure BorgAuth roles

Authority on a cyberCORP is held in its **BorgAuth** ACL. Roles are numeric
levels in a hierarchy — see [Access control](../reference/access-control.md).

## The levels you'll use

| Level | Meaning |
|---|---|
| `99` (`OWNER_ROLE`) | Owner. Can grant/revoke roles. Held by the suite's manager contracts. |
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

## Remove an officer

Either removes the officer record and sets their level back to `0`:

```solidity
CyberCorp(cyberCorp).removeOfficer(departedOfficer);
// or by index:
CyberCorp(cyberCorp).removeOfficerAt(2);
```

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

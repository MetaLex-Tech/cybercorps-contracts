---
description: BorgAuth numeric authority levels and who can call what
---

# Access control (BorgAuth)

Every access check in the protocol runs through **BorgAuth**, one ACL
contract per cyberCORP. BorgAuth uses **numeric role levels in a
hierarchy** instead of named roles.

* **Source:** [`src/libs/auth.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/auth.sol)

## The role model

A role is a `uint256`, and higher numbers outrank lower ones.
`onlyRole(role)` **passes when `userRoles[user] >= role`**. It is a
threshold check; `matchRole` is the exact-match variant.

### Built-in role constants

| Constant | Value |
|---|---|
| `OWNER_ROLE` | `99` |
| `ADMIN_ROLE` | `98` |
| `PRIVILEGED_ROLE` | `97` |

### Roles the protocol assigns

The `CyberCorpFactory` and `CyberCorp` set these levels when a cyberCORP
is deployed:

| Holder | Level | Why |
|---|---|---|
| Company officer (`CompanyOfficer.eoa`) | `200` | Set by `CyberCorp.addOfficer` / `updateOfficer` and by the factory, never lowering a higher custom level; removal zeroes only an exact `200`. `200 ≥ 99`, so officers also pass `onlyOwner`. |
| `CyberCorp` contract | `200` | So the corp can act on its own auth. |
| `IssuanceManager`, `DealManager`, `RoundManager` | `99` (`OWNER_ROLE`) | So the manager contracts can call owner-gated functions on the suite. |
| The deploying factory (`CyberCorpFactory`, or the specialised factory used) | `99` (`OWNER_ROLE`) | The BorgAuth constructor makes its deployer the owner, and the factory does not renounce the level after deployment. |

The factory's level is a standing owner grant from the company to a
contract MetaLeX can upgrade. Some companies, v5 companies among them,
still grant it, and others do not. Check `userRoles(<factory address>)` on
your company's BorgAuth; an owner can remove the grant with
`updateRole(factory, 0)`.

Authority is the numeric level a function requires. BorgAuth defines no
named roles such as `ISSUER_AUTHORITY` or `OFFICER_AUTHORITY`, and `200`
is the level a human officer holds.

## BorgAuth functions

```solidity
uint256 public constant OWNER_ROLE = 99;
uint256 public constant ADMIN_ROLE = 98;
uint256 public constant PRIVILEGED_ROLE = 97;

mapping(address => uint256) public userRoles;
mapping(uint256 => address) public roleAdapters;

function updateRole(address user, uint256 role) external;       // caller must hold OWNER_ROLE
function initTransferOwnership(address newOwner) external;      // caller must hold OWNER_ROLE
function acceptOwnership() external;                            // caller must be pendingOwner
function zeroOwner() external;                                  // caller renounces to role 0
function setRoleAdapter(uint256 role, address adapter) external;// caller must hold OWNER_ROLE
function onlyRole(uint256 role, address user) public view;      // reverts if under-authorized
function matchRole(uint256 role, address user) public view;     // reverts unless exactly equal
```

* **`updateRole`** is the single grant and revoke entry point. It sets a
  user's level up or down and requires `OWNER_ROLE`.
* **`zeroOwner`** renounces the owner's own level to `0`, permanently
  removing its admin control from contracts using this auth.
* **Role adapters.** `setRoleAdapter` plugs in an `IAuthAdapter`, so custom
  logic (a credential check, for example) can satisfy a role instead of,
  or as well as, a stored level.
* **Ownership transfer** takes two steps: `initTransferOwnership`, then
  `acceptOwnership`.

## Using BorgAuth in a contract: `BorgAuthACL`

Protocol contracts inherit `BorgAuthACL`, which holds the `AUTH` reference
and provides modifiers:

| Modifier | Passes when the caller's level is… |
|---|---|
| `onlyOwner` | `≥ OWNER_ROLE` (99) |
| `onlyAdmin` | `≥ ADMIN_ROLE` (98) |
| `onlyPriv` | `≥ PRIVILEGED_ROLE` (97) |
| `onlyRole(n)` | `≥ n` |
| `matchRole(n)` | exactly `n` |

Example: `CyberCorp.addEscrowedOfficerSignature` is `onlyRole(200)`, so
only an officer (level 200) can call it; most other `CyberCorp` functions
are `onlyOwner` (level 99 or above).

## `onlyIssuanceManager` and the token contracts

`onlyIssuanceManager` checks that `msg.sender` *is* the IssuanceManager
contract; it is not a BorgAuth role check. End users act through the
IssuanceManager, which BorgAuth authorizes. `CyberShares` gates its mint,
burn and configuration functions this way.

`CyberScrip` has **two** surfaces:

* **Strictly `onlyIssuanceManager`:** `mint`, `burnFrom` and `forceBurn`.
  Force burn also moves vault backing, so admins use
  `IssuanceManager.forceScripBurn`.
* **`onlyIssuanceManagerOrAdmin`:** `setRestrictionHook`, `setFrozen`,
  `forceTransfer`, `setMaxHolderCount` and the three one-way `disable*`
  switches, callable directly by a BorgAuth `ADMIN_ROLE` (98) holder. On
  v4 scrip, `setMaxHolderCount` is `onlyIssuanceManager` and the v4
  IssuanceManager has no wrapper for it, so a v4 company cannot set a
  holder cap.

`LedgerEntryToken`, the LET contract, also has **two** surfaces:

* **Strictly `onlyIssuanceManager`:** minting and assignment (`safeMint`,
  both `safeMintAndAssign` overloads, `safeMintFromAndAssign`,
  `assignCert`), `updateCertificateDetails`, `setExtension` and
  `updateIssuanceManager`.
* **`onlyIssuanceManagerOrAdmin`:** the administrative surface, callable
  directly on the LET contract by a BorgAuth `ADMIN_ROLE` (98) holder (the
  modifier resolves the IssuanceManager's `AUTH()` and checks the role):
  restriction hooks, the delivery and registration transferability
  switches, default and per-LET legends, `voidCert` / `unvoidCert`,
  `addIssuerSignature` and `endorseCertificate`, issue and acquisition
  timestamps (and the tacking anchor), reserved units, `setSeriesData`,
  the look-through badge, and `initializeHolderCount`.

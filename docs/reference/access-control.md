# Access control (BorgAuth)

All access control in the protocol runs through **BorgAuth** — a single ACL
contract per cyberCORP. BorgAuth uses **numeric role levels in a hierarchy**,
not named roles.

* **Source:** [`src/libs/auth.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/auth.sol)

## The role model

A role is a `uint256`. Higher numbers outrank lower ones.
`onlyRole(role)` **passes when `userRoles[user] >= role`** — it is a
threshold check, not an exact match.

### Built-in role constants

| Constant | Value |
|---|---|
| `OWNER_ROLE` | `99` |
| `ADMIN_ROLE` | `98` |
| `PRIVILEGED_ROLE` | `97` |

### Roles the protocol assigns

The `CyberCorpFactory` and `CyberCorp` set these levels when a cyberCORP is
deployed:

| Holder | Level | Why |
|---|---|---|
| Company officer (`CompanyOfficer.eoa`) | `200` | Set by `CyberCorp.addOfficer` / by the factory. `200 ≥ 99`, so officers also satisfy `onlyOwner`. |
| `CyberCorp` contract | `200` | So the corp can act on its own auth. |
| `IssuanceManager`, `DealManager`, `RoundManager` | `99` (`OWNER_ROLE`) | So the manager contracts can call owner-gated functions on the suite. |

> There are **no named roles** such as `ISSUER_AUTHORITY` or
> `OFFICER_AUTHORITY`. Authority is the numeric level a contract requires at
> a given function. Officer = `200` is the level a human officer holds.

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
function onlyRole(uint256 role, address user) public view;      // reverts if under-authorised
function matchRole(uint256 role, address user) public view;     // reverts unless exactly equal
```

* **`updateRole`** — the single grant/revoke entry point. Set a user's level
  up or down. Requires `OWNER_ROLE`.
* **`zeroOwner`** — the owner renounces itself to level `0`, permanently
  removing admin control from contracts using this auth.
* **Role adapters** — `setRoleAdapter` plugs in an `IAuthAdapter` so a role
  can be satisfied by custom logic (e.g. a credential check) instead of, or
  in addition to, a stored level.
* Ownership transfer is two-step: `initTransferOwnership` then
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

Example: `CyberCorp.addEscrowedOfficerSignature` is `onlyRole(200)` — only an
officer (level 200) can call it; most other `CyberCorp` functions are
`onlyOwner` (level ≥ 99).

## A note on `onlyIssuanceManager`

`CyberScrip`, `LedgerEntryToken` (formerly `CyberCertPrinter`), and
`CyberShares` gate their mutating functions with `onlyIssuanceManager` — a
check that `msg.sender` *is* the IssuanceManager contract, **not** a
BorgAuth role check. End users act through the IssuanceManager, which
itself is authorised via BorgAuth.

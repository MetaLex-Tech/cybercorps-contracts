# CyberShares

**CyberShares** is the accounting layer for share counts on a cyberCORP. It
tracks outstanding, authorized, and reserved units per share class.

* **Source:** [`src/CyberShares.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberShares.sol)

## Responsibilities

* Track `authorized(shareClass)` and `outstanding(shareClass)`.
* Track reservations (e.g., shares promised to convert from SAFEs / options).
* Refuse issuance that would exceed authorized.
* Provide cap-table snapshots for SAFE conversion and other point-in-time uses.

## Selected public interface

```solidity
function authorized(bytes32 shareClass) external view returns (uint256);
function outstanding(bytes32 shareClass) external view returns (uint256);
function reserved(bytes32 shareClass) external view returns (uint256);

function setAuthorized(bytes32 shareClass, uint256) external; // DIRECTOR_AUTHORITY
function reserve(bytes32 shareClass, uint256) external;       // ISSUER_AUTHORITY
function release(bytes32 shareClass, uint256) external;       // ISSUER_AUTHORITY

function snapshot() external returns (bytes32);
```

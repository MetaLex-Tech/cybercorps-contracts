# CyberShares

* **Source:** [`src/CyberShares.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberShares.sol)
* **Inherits:** `ERC20Upgradeable`

> **In-progress contract.** `CyberShares` is partly implemented: several
> functions — including `safeMint` and `certificateTokenURI` — have their
> bodies commented out or return empty values in the current source. Treat
> this page as a description of the *intended* shape and verify against the
> source before relying on it.

## Purpose

`CyberShares` is an ERC-20 share token for a single security class that also
carries certificate-formation logic — a model where fungible shares can be
formed into, and voided back from, individual certificates.

## Functions (current source)

```solidity
function mint(address to, uint256 amount) external onlyIssuanceManager;
function burn(address from, uint256 amount) external onlyIssuanceManager;
function voidToShares(uint256 certId) external;          // burn a cert back to shares
function formCertificateFromShares(uint256 amount, CertificateDetails details) external;
function setGlobalRestrictionHook(address hookAddress) external onlyIssuanceManager;
function setTransferable(bool _transferable) external onlyIssuanceManager;
function setCertThreshold(uint256 _threshold) external onlyIssuanceManager;
function decimals() public view returns (uint8);
function certThreshold() public view returns (uint256);
function sharesUri() public view returns (string);
```

It also exposes `certificate*` helpers (`certificateOwnerOf`,
`certificateApprove`, `certificateTransferFrom`, etc.) that mirror an ERC-721
surface for the formed certificates.

## Events

`SharesMinted`, `SharesBurned`, `CertificateFormed`, `SharesFromCertificate`,
`SharesFromVoidedCertificate`, `GlobalRestrictionHookSet`, `TransferableSet`,
`CertThresholdSet`, plus `Certificate*` events.

> `CyberShares` is **not** a cap-table accounting layer with
> `authorized` / `outstanding` / `reserved` counters. The register of
> holders is the set of [LedgerEntryToken](LedgerEntryToken.md) certificates;
> share counts are read from there.

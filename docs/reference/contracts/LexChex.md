# LexChex / LexChexMinter

MetaLeX's onchain accreditation-credential system. A LeXcheX credential is a
**soulbound** (non-transferable) NFT implementing
[ERC-5484](https://eips.ethereum.org/EIPS/eip-5484).

* **Sources:** [`src/creds/lexchex.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/lexchex.sol),
  [`src/creds/lexchexMinter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/lexchexMinter.sol)
* **Interface:** [`ILexChex.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILexChex.sol)

## ERC-5484 (soulbound)

`ILexChex` extends `IERC5484`, which defines `burnAuth(tokenId)` returning a
`BurnAuth` enum (`IssuerOnly`, `OwnerOnly`, `Both`, `Neither`) and an
`Issued` event. The credential cannot be transferred between wallets.

## Interface

```solidity
function mint(address to, Accreditation acc) external returns (uint256);
function burn(uint256 tokenId) external;
function setAccreditation(uint256 tokenId, Accreditation acc) external;
function accreditations(uint256 tokenId) external view returns (Accreditation);
function getAccreditation(uint256 tokenId) external view returns (Accreditation);
function getAccreditationByOwner(address owner) external view returns (uint256);
function getTokenIdsByOwner(address owner) external view returns (uint256[]);
function hasValidLexCheX(address owner) external view returns (bool);
function isValid(uint256 tokenId) external view returns (bool);
function balanceOf(address owner) external view returns (uint256);
function burnAuth(uint256 tokenId) external view returns (BurnAuth);
```

The `Accreditation` struct is defined in
[`src/creds/storage/lexchexStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/creds/storage/lexchexStorage.sol).

## How it's used

* `hasValidLexCheX(owner)` is the headline check — it answers "does this
  address hold a currently-valid credential?"
* A `lexchexCondition` (see [Conditions](../conditions.md)) wraps this check
  so it can gate issuance, rounds, scripification, and deals.
* The `LexChexMinter` issues credentials; the LeXcheX app and oracle
  ([metalex-webapp](https://github.com/MetaLex-Tech/metalex-webapp)) drive
  the off-chain verification that backs a mint.

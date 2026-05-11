# CyberScrip

**CyberScrip** is the ERC-20 fungible form of a cyberCORP security. It is
minted by `IssuanceManager.scripifyCert` and burned by `convertScripToCert`.
It is itself a security in scrip form (e.g., DGCL §155), with limited
contingent rights specified in its Terms of Service and a deterministic
in-protocol tieback to the cyberCERTs it was minted from.

* **Source:** [`src/CyberScrip.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/CyberScrip.sol)
* **Proxy pattern:** beacon proxy (owned by the cyberCORP's `IssuanceManager`)

## Compliance powers (USDC-style)

| Power | Effect | Renounceable |
|---|---|---|
| Force transfer | Compel a transfer between any two addresses. | ✅ (`permanentlyDisableForceTransfer`) |
| Force burn | Burn from any address. | ✅ (`permanentlyDisableForceBurn`) |
| Freeze | Lock an address. | ✅ (`permanentlyDisableFreeze`) |
| Blocklist | Reject transfers to/from an address. | ✅ (`permanentlyDisableBlocklist`) |

Each disable toggle is **independent and irreversible**. Once an issuer
renounces a power, no party — including MetaLeX — can restore it. This lets
an issuer harden toward the "open" end of the compliance spectrum as the
security matures, without redeploying.

## Transfer hooks

`CyberScrip` consults an optional transfer hook on every transfer. See
[Hooks](../hooks.md) for `WhitelistTransferHook`, `ToggleTransferHook`, and
the base classes.

## Selected public interface

```solidity
function mint(address to, uint256 amount) external;     // IssuanceManager only
function burn(address from, uint256 amount) external;   // IssuanceManager only

function setTransferHook(address) external;             // OFFICER_AUTHORITY
function setMaxHolders(uint256) external;               // DIRECTOR_AUTHORITY

function forceTransfer(address from, address to, uint256 amount) external;
function forceBurn(address from, uint256 amount) external;
function freeze(address account) external;
function blocklist(address account, bool) external;

function permanentlyDisableForceTransfer() external;
function permanentlyDisableForceBurn() external;
function permanentlyDisableFreeze() external;
function permanentlyDisableBlocklist() external;
```

## See also

* [`IssuanceManager`](IssuanceManager.md)
* [Hooks](../hooks.md)
* [The dual-token model](../../explanation/dual-token-model.md)

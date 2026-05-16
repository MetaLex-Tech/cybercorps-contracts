# RoundManager

**RoundManager** runs multi-investor primary fundraising rounds. It is the
backend of cyberRAISE.

* **Source:** [`src/RoundManager.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/RoundManager.sol)
* **Proxy pattern:** UUPS (v3)

## Round modes

| Mode | Behaviour |
|---|---|
| `FIRST_COME` | First valid EOI is accepted automatically; cap fills in submission order. |
| `ADMISSION` | Issuer must explicitly `acceptEOI` for each EOI. |

## Round configuration

* Security type (SAFE / SAFT / SAFTE / Token Warrant / priced equity round).
* Payment token (typically USDC).
* Raise cap, min ticket, max ticket.
* Open / close timestamps.
* Per-round `ICondition` (composed via `OrCondition` if needed).
* Agreement template URI for the round's standard form.

## Selected public interface

```solidity
function createRound(RoundConfig calldata) external returns (uint256 roundId); // OFFICER_AUTHORITY
function submitEOI(uint256 roundId, EOI calldata, bytes calldata sig) external;
function acceptEOI(uint256 roundId, uint256 eoiId) external;                    // OFFICER_AUTHORITY
function rejectEOI(uint256 roundId, uint256 eoiId) external;                    // OFFICER_AUTHORITY
function closeRound(uint256 roundId) external;

function totalRaised(uint256 roundId) external view returns (uint256);
function certsMinted(uint256 roundId) external view returns (uint256[] memory);
```

## See also

* [`DealManager`](DealManager.md), [`IssuanceManager`](IssuanceManager.md)
* [Tutorial: Run a cyberRAISE round](../../tutorials/run-a-cyberraise-round.md)

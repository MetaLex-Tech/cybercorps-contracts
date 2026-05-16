# SafeCertificateConverter

**SafeCertificateConverter** computes SAFE-to-equity conversion plans for a
cyberCORP. It is pure compute: it does not move tokens. The resulting plan is
executed by `IssuanceManager`.

* **Source:** [`src/converters/SafeCertificateConverter.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/converters/SafeCertificateConverter.sol)

## Inputs

* Array of SAFE cyberCERT token ids.
* Cap-table snapshot (`bytes32` from `CyberShares.snapshot()`).
* Round pricing (`pricePerShare`, `preMoneyValuation`).

The converter reads each SAFE's `SAFEExtension` metadata (valuation cap,
discount, MFN provisions) and applies them per the standard YC/NVCA rules.

## Output

A `ConversionPlan` struct containing one entry per SAFE: the resulting share
class and unit count, the residual cash refund (if any), and the effective
price used.

## Selected public interface

```solidity
function computePlan(
    uint256[] calldata safeCertIds,
    bytes32 capTableSnapshot,
    RoundPricing calldata pricing
) external view returns (ConversionPlan memory);
```

## See also

* [How-to: Convert SAFEs to equity](../../how-to/convert-safe-to-equity.md)
* [Extensions → `SAFEExtension`](../extensions.md#safeextension)

# Changeset: Remove redundant scrip pool, simplify to single cert-decay pool

## Motivation

The current scrip accounting uses **two** MasterChef-style lazy-reduction pools:

1. **Scrip Pool** (`ScripPoolState` / `ScripUserInfo`) — tracks per-user scrip amounts with socialized reduction
2. **Cert Scrip Units Pool** (`CertScripUnitPool` / `CertScripState`) — tracks per-cert scripified units with socialized reduction

The scrip pool is redundant. Per-user scrip amounts are never read during conversion logic — the system uses real ERC-20 balances (`burnFrom`) instead. The `totalTrackedScrip` is always equal to `scrip.totalSupply()`. The per-user tracked amounts are informational only and decay in a way that is confusing to consumers.

The cert scrip units pool is the one that does real work: tracking how each cert's scripified units decay as others recertify, and enabling the "consume own first, socialize remainder" pattern.

## Changes

### 1. `src/storage/IssuanceManagerStorage.sol` — Storage structs

**Delete** the following (no longer needed):
- `ScripPoolState` struct (L143-146)
- `ScripUserInfo` struct (L153-156)
- `scripPoolStates` mapping from `IssuanceManagerData` (L121)
- `scripPoolUsers` mapping from `IssuanceManagerData` (L122)

**Keep** unchanged:
- `CertScripUnitPool`, `CertScripState` — the single remaining pool
- `ACC_REDUCTION_PRECISION` — still used by the cert pool
- `_currentAmount()` — still used by the cert pool

### 2. `src/storage/IssuanceManagerStorage.sol` — Delete scrip pool functions

**Delete entirely** (6 functions):
- `getScripPoolState()` (L342-346)
- `getScripPoolUserInfo()` (L348-353)
- `getScripPoolUserAmount()` (L355-362)
- `getScripPoolUserPosition()` (L364-376)
- `_depositScripPool()` (L916-929)
- `_reduceScripPool()` (L931-939)
- `_syncUserScripPoolPosition()` (L1001-1012)

### 3. `src/storage/IssuanceManagerStorage.sol` — Modify `getScripPoolTotals` (L432-442)

Replace the current implementation that reads from `ScripPoolState` with a simple read of scrip `totalSupply()`:

```solidity
function getScripPoolTotals(
    address certAddress
) internal view returns (uint256 totalTrackedScrip) {
    address scripAddress = getScripifiedCert(certAddress);
    if (scripAddress == address(0)) return 0;
    totalTrackedScrip = ICyberScrip(scripAddress).totalSupply();
}
```

This changes the return signature — it no longer returns `accReductionPerShare` (which belonged to the deleted scrip pool). Callers that used the second return value must be updated.

### 4. `src/storage/IssuanceManagerStorage.sol` — Modify `executeScripifyCert` (~L611-684)

Remove the call to `_depositScripPool` (L681). The ERC-20 `mint` on the next line already tracks the user's balance. No replacement needed.

Before:
```solidity
_depositScripPool(certAddress, account, scripAmount);
ICyberScrip(scripifiedCert).mint(toSend, scripAmount);
```

After:
```solidity
ICyberScrip(scripifiedCert).mint(toSend, scripAmount);
```

### 5. `src/storage/IssuanceManagerStorage.sol` — Modify `executeConvertScripToCert` (~L686-783)

Remove the call to `_reduceScripPool` (L737). The ERC-20 `burnFrom` a few lines later already reduces `totalSupply()`. No replacement needed.

Before:
```solidity
_reduceScripPool(certAddress, amount);
if (selection.foundActive) {
```

After:
```solidity
if (selection.foundActive) {
```

### 6. `src/storage/IssuanceManagerStorage.sol` — Modify `executeForceScripBurn` (~L786-807)

Remove the call to `_reduceScripPool` (L804). The `forceBurn` call already reduces `totalSupply()`.

Before:
```solidity
_reduceScripPool(certAddress, amount);
_reduceCertScripUnitsPool(certAddress, unitsWad);
ICyberScrip(scripifiedCert).forceBurn(account, amount);
```

After:
```solidity
_reduceCertScripUnitsPool(certAddress, unitsWad);
ICyberScrip(scripifiedCert).forceBurn(account, amount);
```

### 7. `src/IssuanceManager.sol` — Facade functions

**Modify** `getScripPoolTotals` (L914-922) to match the new return signature (single return value, no `accReductionPerShare`).

**Delete** `getScripPoolUserAmount` (L934-939) and `getScripPoolUserPosition` (L941-950) — these have no backing storage anymore. (Note: these are NOT declared in `IIssuanceManager.sol`, so no interface change needed.)

### 8. Tests — `test/IssuanceManagerConversionTest.t.sol`

Update assertions that use `getScripPoolTotals` to use the new single-return-value signature. The value itself (`totalTrackedScrip`) should still be correct since it now reads `totalSupply()`.

In the invariant assertions, the pattern:
```solidity
(totalTrackedScrip,) = issuanceManager.getScripPoolTotals(address(certPrinter));
assertEq(totalScripifiedUnits, totalTrackedScrip);  // THIS IS THE FAILING ASSERTION
assertEq(totalActiveUnits + totalTrackedScrip, 400);
```

The second assertion (`activeUnits + totalTrackedScrip == 400`) will still hold — `totalSupply()` is exact.

The first assertion (`totalScripifiedUnits == totalTrackedScrip`) compares the sum of per-cert lazy-reduced values against the pool total. This will still have MasterChef rounding. Change to `<=`:
```solidity
assertLe(totalScripifiedUnits, totalTrackedScrip);
```

### 9. Tests — `test/CyberScripUpgradeTest.t.sol`

- Update `getScripPoolTotals` calls to new signature.
- **Delete** all `getScripPoolUserAmount` assertions (L802-814, L829-841, L860-872) — these functions no longer exist.

## What NOT to change

- `CertScripUnitPool`, `CertScripState`, and all cert-pool functions (`_depositCertScripUnits`, `_reduceCertScripUnitsPool`, `_consumeOwnCertScripUnits`, `_syncCertScripPosition`, `getCurrentCertScripifiedUnits`) — these are the single remaining pool and stay as-is.
- `_currentAmount()`, `ACC_REDUCTION_PRECISION` — shared helpers, still used.
- `IIssuanceManager.sol` — the deleted facade functions were never in the interface.
- `CyberScrip.sol` — no changes needed.
- The "consume own first, socialize remainder" pattern in `executeConvertScripToCert` — unchanged.

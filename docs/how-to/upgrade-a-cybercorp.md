# Upgrade a cyberCORP

All contracts use UUPS upgradeable proxies (with beacon proxies for
`CyberCertPrinter` and `CyberScrip` instances) and ERC-7201 namespaced
storage. Upgrades use a **co-approval** model: MetaLeX publishes new
implementations, but each cyberCORP independently opts in. No unilateral
pushes.

For architecture detail, see [Upgrade model](../reference/upgrade-model.md)
and [Co-approval upgradeability](../explanation/co-approval-upgradeability.md).

## Steps

### 1. Confirm a MetaLeX-published implementation

MetaLeX publishes implementation addresses (and a release note) to
[the official Substack](https://metalex.substack.com/) and the contracts
repository. For v3 architectures, the published address is registered on the
relevant factory (e.g., `IssuanceManagerFactory.setRefImplementation`).

Verify the address you intend to upgrade to:

```solidity
address published = issuanceManagerFactory.refImplementation();
```

### 2. Call `upgradeToAndCall` from the issuer's `UPGRADE_AUTHORITY`

```solidity
UUPSUpgradeable(yourCyberCorp).upgradeToAndCall(published, "");
```

For downstream beacon-proxied contracts (`CyberCertPrinter`, `CyberScrip`),
upgrade the cyberCORP's *own* beacon — this batches all instances of that
type owned by your `IssuanceManager`:

```solidity
issuanceManager.upgradeCertPrinterBeaconImplementation(publishedPrinter);
issuanceManager.upgradeScripBeaconImplementation(publishedScrip);
```

### 3. Verify the new implementation pointer

For a UUPS proxy:

```solidity
bytes32 SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
address impl = address(uint160(uint256(vm.load(yourCyberCorp, SLOT))));
assert(impl == published);
```

## What you can and cannot do

* ✅ You can stay on your original implementation indefinitely. There is no
  forced migration.
* ✅ You can roll back to an earlier MetaLeX-approved implementation if it
  is still set on the factory.
* ❌ You cannot upgrade to an arbitrary implementation. The reference
  implementation gate ensures MetaLeX and the issuer must both agree.
* ❌ MetaLeX cannot upgrade your contracts. The upgrade transaction is
  signed by your `UPGRADE_AUTHORITY`.

## Related

* Reference: [Upgrade model](../reference/upgrade-model.md).
* Explanation:
  [Co-approval upgradeability](../explanation/co-approval-upgradeability.md),
  [The role of MetaLeX](../explanation/role-of-metalex.md).

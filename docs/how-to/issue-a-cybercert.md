# Issue a cyberCERT

This is the canonical way to mint a new entry on a cyberCORP's register of
holders — whether that entry represents Common Stock, Preferred Stock, a SAFE,
a SAFT, a SAFTE, a Token Warrant, an LLC membership interest, or any other
supported security type.

## Prerequisites

* The caller has the `ISSUER_AUTHORITY` BorgAuth role.
* The relevant `CertificateExtension` (e.g., `ShareExtension`,
  `SAFEExtension`) is registered on the `CyberCertPrinter`.
* If the security is a share, the share class is authorised in `CyberShares`
  with sufficient headroom (`authorized - outstanding ≥ units`).

## Steps

### 1. Build the `CertIssuance`

The struct varies by extension. See [extensions](../reference/extensions.md)
for the per-extension metadata. A Preferred Stock example:

```solidity
CertIssuance memory cert = CertIssuance({
    holderName: "Alice Investor LLC",
    holderAddress: 0xAaA...,
    units: 1_000_000,
    shareClass: SHARE_CLASS_PREFERRED,
    series: "Series A",
    legend: STANDARD_RESTRICTIVE_LEGEND,
    agreementUri: "ipfs://series-a-spa-v1",
    acquisitionPriceUsd: 2_500_000e6,
    extensionData: abi.encode(ShareExtensionParams({
        liquidationPreference: 1e18,
        conversionRatio: 1e18,
        antiDilution: AntiDilution.BROAD_BASED_WEIGHTED_AVG,
        votingPower: 1
    }))
});
```

### 2. Call `IssuanceManager.issueCert`

```solidity
uint256 tokenId = issuanceManager.issueCert(cert);
```

### 3. Verify

```solidity
string memory uri = certPrinter.tokenURI(tokenId);
// renders the SVG share certificate inline

uint256 outstanding = cyberShares.outstanding(SHARE_CLASS_PREFERRED);
```

## Common variations

* **Endorsement** (record an event on an existing cert) —
  `issuanceManager.endorseCert(tokenId, endorsementData)`.
* **Revoke** — `issuanceManager.revokeCert(tokenId)` (requires the relevant
  legal grounds; the extension can enforce them).
* **Pre-set registration approval** for a new holder receiving cyberSCRIP —
  see [Run a secondary trade](run-a-secondary-trade.md).

## Related

* Reference: [`IssuanceManager`](../reference/contracts/IssuanceManager.md),
  [`CyberCertPrinter`](../reference/contracts/CyberCertPrinter.md),
  [Certificate extensions](../reference/extensions.md).

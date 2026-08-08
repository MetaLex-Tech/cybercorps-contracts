# Tutorial: Scripify and settle a secondary trade

In this tutorial you make part of a cyberCERT tradable as fungible
**cyberSCRIP**, transfer it to a buyer, and convert it back into a cyberCERT.

> Code is **illustrative of the flow** and uses the real signatures from
> `cybercorps-contracts` (`develop`).

## Prerequisites

A cyberCERT from [Tutorial 1](incorporate-a-cybercorp.md) — say `tokenId = 1`
on the Common Stock printer at `commonPrinter`, held by `alice`. You also
need the `issuanceManager` address.

## 1. Deploy a CyberScrip for the printer

A CyberScrip is deployed per cert printer via `deployCyberScrip`. This
is also where you set the scrip ratio, conversion conditions, and which
compliance powers exist.

```solidity
address cyberScrip = IIssuanceManager(issuanceManager).deployCyberScrip(
    commonPrinter,
    typeRestrictionHooks,   // ITransferRestrictionHook[]
    certToScripConditions,  // ICondition[] gating scripification
    scripToCertConditions,  // ICondition[] gating de-scripification
    1e18,                   // scripToCertMinimum (in scrip, i.e. 1 unit here)
    1e18,                   // scripRatioNumerator
    1,                      // scripRatioDenominator
    new uint256[](0),       // scripifyWhitelistIds
    false,                  // scripifyWhitelistEnabled
    true,                   // enableForceTransfer
    true,                   // enableForceBurn
    true                    // enableFreeze
);
```

Scrip minted = units × `scripRatioNumerator / scripRatioDenominator`. The
cyberSCRIP ERC-20 uses 18 decimals, so a `1e18 : 1` ratio makes one cert
unit read as one whole scrip token in wallets. (The deploy call is
`onlyOwner` — an officer runs it.)

## 2. Scripify part of the cert

Alice — the cert's registered owner — calls `scripifyCert` herself
(`legalOwnerOf` is checked against the caller):

```solidity
IIssuanceManager(issuanceManager).scripifyCert(
    commonPrinter,   // certAddress
    1,               // id (the cyberCERT token id)
    1_000_000,       // amount of units to scripify
    alice            // recipient of the cyberSCRIP
);
```

This reduces the cert's `unitsRepresented`, records the scripified units in
the scrip pool, and mints cyberSCRIP to Alice (1_000_000e18 at the `1e18:1`
ratio above). Units reserved for pending deals cannot be scripified.
The cyberSCRIP is the *same security in fungible form* — see
[the dual-token model](../explanation/dual-token-model.md).

## 3. Sell the scrip

```solidity
CyberScrip(cyberScrip).transfer(bob, 1_000_000e18);
```

If a transfer hook is installed, the transfer must satisfy it (see
[Restrict cyberSCRIP transfers](../how-to/restrict-transfers.md)).

## 4. (New holder) issuer pre-approves recertification

Because Bob is not yet a registered holder, an officer pre-sets the
certificate metadata he will receive on de-scripification:

```solidity
IIssuanceManager(issuanceManager).setRecertificationApproval(
    commonPrinter,
    bob,
    "Bob Buyer",
    bobCertDetails,    // CertificateDetails
    officerSignature   // bytes
);
```

## 5. Convert scrip back to a cyberCERT

Bob presents his cyberSCRIP:

```solidity
IIssuanceManager(issuanceManager).convertScripToCert(
    commonPrinter,   // certAddress
    1_000_000e18     // amount of cyberSCRIP to present
);
```

This burns Bob's cyberSCRIP, withdraws the units from the scrip pool, and —
using the approved metadata — puts Bob on the register. The approval
requirement for new holders is enforced by the conversion flow itself: if
the caller holds no active cert on that printer, the call reverts
`RecertificationApprovalRequired` unless an officer approval from step 4 is
on file. (If the caller already has an active cert, the units are added to
it instead.) An `IssuerApprovalRecertificationCondition` can additionally be
included among the `scripToCertConditions` as an opt-in, admin-managed
approval list.

## What you just did

* Deployed a cyberSCRIP and scripified part of a cyberCERT.
* Traded the security in fungible form.
* Recertified a new holder back onto the register, under issuer approval.

## Next

* How-to: [Restrict cyberSCRIP transfers](../how-to/restrict-transfers.md).
* Reference: [CyberScrip](../reference/contracts/CyberScrip.md),
  [IssuanceManager](../reference/contracts/IssuanceManager.md).

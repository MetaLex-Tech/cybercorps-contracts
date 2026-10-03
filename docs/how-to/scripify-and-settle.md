---
description: Turn part of a LET into scrip, trade the scrip, and convert it back into a LET in the buyer's name
---

# Scripify and settle a secondary trade

This guide converts part of a Ledger Entry Token (LET) into scrip, the
fungible ERC-20 token that tracks the LET's units, transfers the scrip to a buyer,
and converts it back into a LET in the buyer's name. To settle on the LET
itself through the DealManager's offer flow, see [Run a secondary
trade](run-a-secondary-trade.md).

The example starts from the LET issued in [Incorporate a
cyberCORP](incorporate-a-cybercorp.md): `tokenId = 1` on the Common Stock
LET contract at `commonPrinter`, held by `alice`. You also need the
company's `issuanceManager` address.

## 1. Deploy the CyberScrip for the LET contract

Each LET contract gets its own `CyberScrip`, deployed with
`deployCyberScrip`. The same call sets the scrip ratio, the conditions on
conversion in each direction, and which compliance powers exist. The call
is `onlyOwner`, so an officer runs it.

```solidity
address cyberScrip = IIssuanceManager(issuanceManager).deployCyberScrip(
    commonPrinter,
    typeRestrictionHooks,   // ITransferRestrictionHook[]
    certToScripConditions,  // ICondition[] gating scripification
    scripToCertConditions,  // ICondition[] gating de-scripification
    1e18,                   // scripToCertMinimum (in scrip, one whole token)
    1,                      // scripRatioNumerator
    1,                      // scripRatioDenominator
    new uint256[](0),       // scripifyWhitelistIds
    false,                  // scripifyWhitelistEnabled
    true,                   // enableForceTransfer
    true,                   // enableForceBurn
    true                    // enableFreeze
);
```

Scrip minted = units × `scripRatioNumerator / scripRatioDenominator`, with
no implicit rescaling, so the `1 : 1` ratio makes one share's worth of LET
units read as one whole scrip token in wallets.

{% hint style="warning" %}
All LET unit quantities are **18-decimal fixed point** (one share = `1e18`
units), and scrip is an 18-decimal ERC-20. Passing raw share counts
(`1_000_000` instead of `1_000_000e18`) under-scales by a factor of 10¹⁸.
{% endhint %}

## 2. Scripify part of Alice's LET

Alice, the LET's registered owner, calls `scripifyCert` herself. The
IssuanceManager checks `legalOwnerOf` against the caller.

```solidity
IIssuanceManager(issuanceManager).scripifyCert(
    commonPrinter,   // certAddress
    1,               // id (the LET's token id)
    1_000_000e18,    // units to scripify (1,000,000 shares, 18-decimal)
    alice            // recipient of the scrip
);
```

The call reduces the LET's `unitsRepresented`, records the scripified units
in the scrip pool, and mints scrip to Alice: `1_000_000e18` base units, or
1,000,000 whole tokens at the `1:1` ratio. Units reserved for pending deals
cannot be scripified, and neither can a void LET. The scrip's transfer
hooks also apply to this mint, so with a `WhitelistTransferHook` installed,
Alice must be whitelisted first. What rights scrip carries is set by the company's governing
documents; [LETs and scrip](../explanation/lets-and-scrip.md) explains how the
two forms relate.

## 3. Transfer the scrip to the buyer

```solidity
CyberScrip(cyberScrip).transfer(bob, 1_000_000e18);
```

The transfer must pass every installed transfer hook; see [Restrict scrip
and LET transfers](restrict-transfers.md).

## 4. Pre-approve the buyer's recertification

Bob holds no LET on this contract yet, so an officer sets the details of
the LET he will receive when he converts his scrip:

```solidity
IIssuanceManager(issuanceManager).setRecertificationApproval(
    commonPrinter,
    bob,
    "Bob Buyer",
    bobCertDetails,    // CertificateDetails
    officerSignature   // bytes
);
```

## 5. Convert the scrip back into a LET

Bob presents his scrip:

```solidity
IIssuanceManager(issuanceManager).convertScripToCert(
    commonPrinter,   // certAddress
    1_000_000e18     // amount of scrip to present
);
```

The call burns Bob's scrip, withdraws the units from the scrip pool, and
registers Bob as holder of record on a LET with the approved details. The
conversion enforces the approval itself: if the caller holds no active LET
on that contract, the call reverts `RecertificationApprovalRequired` unless
an officer's `setRecertificationApproval` for the caller is on file. If the
caller already holds an active LET, the units are added to it instead. An
issuer that wants an admin-managed approval list as well can add an
`IssuerApprovalRecertificationCondition` to the `scripToCertConditions`.

Function-level detail is in
[CyberScrip](../reference/contracts/CyberScrip.md) and
[IssuanceManager](../reference/contracts/IssuanceManager.md).

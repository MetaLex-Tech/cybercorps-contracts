# Tutorial: Scripify and settle a secondary trade

In this tutorial you will:

1. take an existing cyberCERT (a Common Stock entry) and *scripify* part of
   it, producing fungible cyberSCRIP,
2. transfer that scrip to a buyer, and
3. settle the buyer back onto the register via *de-scripification*, with
   issuer approval gating.

This is the core flow that powers **cyberTRADE**'s "scrip path" and any
AMM-native LiquiLeX pool.

## Prerequisites

You have a cyberCERT from Tutorial 1, say `tokenId = 1` representing 8,000,000
shares of Common, owned by `alice`. Take note of the `issuanceManagerAddr` and
the `cyberScripAddr` that the IssuanceManager deployed for the Common class.

## 1. Scripify part of the cert

Alice wants to make 1,000,000 units tradable while keeping the rest on her
cert.

```solidity
IIssuanceManager im = IIssuanceManager(issuanceManagerAddr);

im.scripifyCert(
    tokenId,             // the cert to (partially) scripify
    1_000_000,           // units to scripify
    alice                // recipient of the resulting cyberSCRIP
);
```

The call will:

* check that `tokenId` is eligible (via the optional per-cert scripify
  whitelist) and that scripification conditions are satisfied,
* reduce `tokenId`'s `units` from 8,000,000 to 7,000,000 (partial
  scripification leaves the cert active),
* record 1,000,000 units in the **Scripified Share Pool** (ERC-4626-style
  vault) crediting Alice as the underlying registered holder,
* mint `1_000_000 * scripRatioNumerator / scripRatioDenominator` cyberSCRIP
  ERC-20 tokens to Alice.

> 🛈 **Same security, different form.** The cyberSCRIP is *itself* a security
> in scrip form (DGCL §155, or the equivalent under your governing law). It is
> not a wrapper. See
> [the dual-token model](../explanation/dual-token-model.md).

## 2. Sell the scrip

Alice transfers her cyberSCRIP to Bob.

```solidity
CyberScrip(cyberScripAddr).transfer(bob, 1_000_000e18);
```

If the cyberSCRIP has a `WhitelistTransferHook` or other
[transfer hook](../reference/hooks.md) installed, the transfer will only
succeed if Bob's address passes. For an open LiquiLeX pool, no whitelist is
required; compliance is enforced *at the de-scripification boundary*.

## 3. Bob requests recertification

Bob does not want to hold scrip indefinitely; he wants to be a registered
holder of record. He calls:

```solidity
im.requestRecertification(cyberScripAddr, 1_000_000e18);
```

Because Bob is not yet a registered holder, this enters the **new-holder
path**: it does *not* mint a cert yet. It records his request.

## 4. Issuer approves the new holder

An officer of Acme CyberCo reviews Bob's KYC/AML credentials (potentially via
an onchain `lexchexCondition`) and pre-sets the certificate metadata:

```solidity
im.approveRegistration(bob, RegistrationData({
    holderName: "Bob Buyer",
    legend: "...",
    officerSignature: officerSig,
    // ...
}));
```

Now Bob can present his scrip:

```solidity
uint256 newTokenId = im.convertScripToCert(cyberScripAddr, 1_000_000e18);
```

The call will:

* burn 1,000,000e18 cyberSCRIP from Bob,
* withdraw 1,000,000 units from the Scripified Share Pool (Alice's vault
  balance decreases),
* mint a fresh cyberCERT to Bob with the approved metadata and a pre-set
  officer signature.

Bob is now on Acme's register. The chain state transition *is* the legal state
transition.

> If Bob were *already* a registered holder, the existing-holder path applies:
> `convertScripToCert` would merge the units onto his existing cyberCERT for
> the same class without requiring further issuer approval.

## 5. What you just did

* Used the **scrip layer** to make Common Stock tradable like an ERC-20 while
  the cert layer remained the authoritative register.
* Routed the buyer through the **new-holder recertification path**, with
  explicit issuer approval — the moment that matters for §158 / §219 / §202
  compliance under Delaware law (and analogues elsewhere).
* Kept the entire flow onchain. There was no transfer agent, no Carta, no
  paper certificate.

## Next

* How-to: [Restrict cyberSCRIP transfers](../how-to/restrict-transfers.md) to
  add a whitelist or per-cert toggle.
* How-to: [Deploy a LiquiLeX pool](../how-to/deploy-liquilex-pool.md) for
  AMM-native settlement.
* Reference: [`CyberScrip`](../reference/contracts/CyberScrip.md),
  [`IssuanceManager`](../reference/contracts/IssuanceManager.md).

# Run a secondary trade

There are two settlement paths for a secondary trade of cyberCORP securities,
both supported by the same contracts. cyberTRADE is the issuer-facing app
surface; the contracts are agnostic.

* **Registered ledger path** — edit the existing cyberCERT (or burn-and-mint
  with new metadata) under issuer approval. Best when both parties want to be
  registered holders of record.
* **Scrip path** — settle at the cyberSCRIP layer, with deferred
  de-scripification, including AMM-native trades through LiquiLeX.

## Registered ledger path

### 1. Negotiate off-chain or off-protocol

Discovery, KYC, price discovery and bilateral negotiation happen wherever
they happen. The cyberCORP suite does not opinionate. You arrive at this step
with a willing seller, a willing buyer, a price, and an asset description.

### 2. Open a deal in the cyberCORP's `DealManager`

```solidity
uint256 dealId = dealManager.proposeDeal(DealParams({
    sellerCertId: 42,
    units: 100_000,
    buyer: bob,
    paymentToken: USDC,
    price: 200_000e6,
    conditions: dealConditions,    // e.g. buyer accreditation + issuer approval
    agreementHash: keccak256(spa)
}));
```

### 3. Both parties countersign

Each party signs an EIP-712 deal payload. Seller approves transfer of the
cert (or of the units to be moved), buyer approves USDC to `LeXscroWLite`.

### 4. The escrow settles atomically on conditions

When every `ICondition` returns true (e.g., `lexchexCondition` passes for
both, and the issuer has called `dealManager.approveDeal(dealId)`),
`LeXscroWLite` releases:

* USDC to seller,
* either an edited cyberCERT or a freshly minted cert to buyer (depending on
  `DealParams.settlementMode`),
* an endorsement is added to the cert recording the trade.

The atomic step **is** the legal transfer.

## Scrip path

If both parties accept the scrip form of the security, the deal can settle in
cyberSCRIP. Subsequent de-scripification onto the buyer's register entry can
be deferred (or never happen — many cyberSCRIP holders just hold the scrip).

This is the path used by AMM trades through a
[LiquiLeX pool](deploy-liquilex-pool.md). Compliance is enforced either:

* on every swap, via a whitelisted-pool model with full credential checks, or
* at the de-scripification boundary, with a lighter zkPassport gate at swap
  for sanctions and Reg S screening.

See Tutorial 3 for the full mechanics of
[scripify and settle](../tutorials/scripify-and-settle.md).

## Related

* Reference: [`DealManager`](../reference/contracts/DealManager.md),
  [`LeXscroWLite`](../reference/contracts/LeXscroWLite.md).
* Explanation:
  [Application stack — cyberTRADE](../explanation/application-stack.md#cybertrade).

# Tutorial: Run a cyberRAISE round

In this tutorial you will configure a SAFE round, accept signed Expressions of
Interest (EOIs) from two investors, escrow their USDC, and close the round —
minting two SAFE cyberCERTs.

This is exactly what the [`cybercorps-web` `cyberraise` route](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web/src/app/%28frame-layout%29/cyberraise)
does from a UI; here we drive it from Solidity.

## Prerequisites

You have completed [Tutorial 1](incorporate-a-cybercorp.md) and have the
addresses of a fresh cyberCORP. Take note of `roundManagerAddr`,
`issuanceManagerAddr`, and `dealManagerAddr`.

## 1. Configure the round

A round is created on the cyberCORP's own `RoundManager`. You choose:

* **Security type** — `SecurityType.SAFE`
* **Round mode** — `RoundMode.ADMISSION` (issuer approves each EOI) or
  `RoundMode.FIRST_COME` (first valid EOI fills the cap)
* **Payment token** — typically the canonical USDC on your chain
* **Raise cap** — e.g. `2_000_000e6` for $2M
* **Min / max ticket** — e.g. `25_000e6` / `500_000e6`
* **Open / close timestamps** — Unix seconds
* **Per-round conditions** — e.g. require a valid LeXcheX accreditation
  credential ([`lexchexCondition`](../reference/conditions.md)).
* **Agreement template** — the URI of the `MetaLeX cyberSAFE US style Reg D`
  template you intend to use

```solidity
IRoundManager rm = IRoundManager(roundManagerAddr);
uint256 roundId = rm.createRound(RoundConfig({
    securityType: SecurityType.SAFE,
    mode: RoundMode.ADMISSION,
    paymentToken: USDC,
    raiseCap: 2_000_000e6,
    minTicket: 25_000e6,
    maxTicket: 500_000e6,
    opensAt: block.timestamp,
    closesAt: block.timestamp + 30 days,
    conditions: lexchexCond,
    agreementTemplate: "ipfs://cybersafe-regd-v1"
    /* ... */
}));
```

## 2. Investors submit signed EOIs

Each investor signs an EIP-712 EOI message off-chain (a `RoundManager`-typed
payload) declaring their intent to invest a specific amount at the round's
price / cap and agreeing to the linked SAFE template.

The EOI is then submitted on-chain (by the investor or by your front-end as a
relayer):

```solidity
rm.submitEOI(roundId, EOI({
    investor: alice,
    amount: 100_000e6,
    agreementHash: keccak256(safeText),
    /* ... */
}), aliceSignature);
```

In `ADMISSION` mode the issuer must then call `rm.acceptEOI(roundId, eoiId)`.
In `FIRST_COME` mode acceptance is implicit on submission.

## 3. Investors fund the escrow

On acceptance, the round creates a deal in the cyberCORP's `DealManager` and a
`LeXscroWLite` escrow. The investor approves USDC to the escrow and calls:

```solidity
dealManager.deposit(dealId);
```

The escrow holds the funds until *all* conditions on the deal evaluate true.
For a standard SAFE round this is typically:

* the round is closed or its cap is hit,
* the investor has a valid LeXcheX credential at close-time,
* a `NonUSNationalityCondition` (Reg S only) or other configured gates.

## 4. Close the round

Once conditions are met (or you call `rm.closeRound(roundId)` after the close
time), the `RoundManager`:

1. Releases USDC from each accepted investor's escrow to the cyberCORP's
   designated receiving address.
2. Calls `IssuanceManager.issueCert(...)` for each filled ticket, minting a
   SAFE cyberCERT to each investor. The cert's `tokenURI` embeds the SAFE
   parameters (valuation cap, discount, MFN) via the
   [SAFEExtension](../reference/extensions.md).
3. Adds endorsements to each cyberCERT recording the deal-close event.
4. Emits `RoundClosed(roundId)`.

MetaLeX never custodies funds; the escrow contract is the only intermediary,
and it has no admin keys.

## 5. Inspect what happened

```solidity
uint256 raised = rm.totalRaised(roundId);          // 200,000e6 if two $100k
uint256[] memory tokens = rm.certsMinted(roundId); // two token ids
string memory aliceCert = CyberCertPrinter(certPrinter).tokenURI(tokens[0]);
```

The SAFE certs are now part of Acme's official register. They are bound to the
specific SAFE legal instrument (anchored in `CyberAgreementRegistry`) and will
later convert to preferred stock via the
[`SafeCertificateConverter`](../reference/contracts/SafeCertificateConverter.md)
when Acme runs its priced round.

## Next

* Tutorial 3: [Scripify and settle](scripify-and-settle.md) — give your
  investors a tradable form of their security.
* How-to: [Convert SAFEs to equity](../how-to/convert-safe-to-equity.md).
* Reference: [`RoundManager`](../reference/contracts/RoundManager.md).
* Explanation:
  [Compliance architecture](../explanation/compliance-architecture.md).

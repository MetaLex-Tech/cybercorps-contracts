---
description: Create a SAFE round on a cyberCORP, take an investor's Expression of Interest, allocate it and close the round
---

# Run a cyberRAISE round

This guide creates a SAFE round on a cyberCORP's `RoundManager`, takes an
investor's Expression of Interest (EOI), allocates it and closes the round.
Allocation issues the investor's SAFE as a Ledger Entry Token (LET). The
`Round` and `EOI` structs are large, and the snippets show only the fields
this flow sets, so check the source for every field.

```mermaid
flowchart TD
    A["Officer builds the Round<br/>draft · setTickets · setAgreement"] --> B["createRound<br/>(officer's escrowed EIP-712 signature)"]
    B --> C["Round live"]
    C --> D["Investor submits EOI<br/>payment escrowed (not yet gated)"]
    D --> E{Round type}
    E -- "FCFS, automatic in<br/>the same transaction" --> G["Allocation<br/>conditions checked here · LET issued ·<br/>agreement executed with the escrowed officer signature ·<br/>escrow finalized and payment released to the issuer"]
    E -- "FounderApproved,<br/>officer calls allocate" --> G
    D -. "officer rejects<br/>(any time before allocation)" .-> R["Refund to investor"]
    D -. "investor recalls<br/>(after EOI expiry or round end)" .-> R
    G --> I["Round closes<br/>closeRoundNow or endTime"]
```

You need a cyberCORP from [Incorporate a cyberCORP](incorporate-a-cybercorp.md):
its `roundManager` address and an officer key.

## 1. Build the round

A round is a `Round` struct
([`RoundLib.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/libs/RoundLib.sol)).
Build it by chaining the `RoundLib` builder's `draft()`, `setTickets` and
`setAgreement`.

```solidity
import {RoundLib, Round, RoundType} from "src/libs/RoundLib.sol";
import {SecuritySeries} from "src/CyberCorpConstants.sol";
using RoundLib for Round;

Round memory round = RoundLib.draft()
    .setTickets(
        SecuritySeries.NA,        // seriesType
        RoundType.FounderApproved,// FCFS or FounderApproved
        false,                    // publicRound
        true,                     // allowTimedOffers
        false,                    // restrictEndTimeReduction
        2_000_000e18,             // raiseCap   (USD, 18 decimals)
        25_000e18,                // minTicket
        500_000e18,               // maxTicket
        USDC,                     // paymentToken
        1e18,                     // pricePerUnit (USD, 18 decimals)
        20_000_000e18,            // valuation
        block.timestamp,          // startTime
        block.timestamp + 30 days // endTime
    )
    .setAgreement(
        TEMPLATE_ID,              // agreement template id
        officer,                  // authorityOfficer
        "Jane Founder",           // officerName
        "Chief Executive Officer",// officerTitle
        legalDetails,             // string[] (one per LET contract)
        roundPartyValues,         // string[]
        extensionData,            // bytes[]  (one per LET contract)
        conditions,               // address[] of ICondition gates
        escrowedSignature         // bytes, the officer's escrowed signature
    );
```

`RoundType.FCFS` accepts EOIs first-come. `RoundType.FounderApproved`
requires the officer to allocate each one.

The `escrowedSignature` is the `authorityOfficer`'s EIP-712 signature over
the round's economic parameters (the `EscrowedSignatureData` struct in
[`RoundManagerStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/RoundManagerStorage.sol)),
under the domain `"RoundManager"`, version `"1"`, with the RoundManager as
verifying contract. `createRound` recomputes the hash from the draft and
reverts `InvalidEscrowedSignature` if the signature does not verify.

## 2. Create the round

`createRound` also creates a LET contract for each
`CyberCertData` entry you pass.

```solidity
import {CyberCertData, SecurityClass} from "src/CyberCorpConstants.sol";

CyberCertData[] memory certData = new CyberCertData[](1);
certData[0] = CyberCertData({
    name:           "SAFE",
    symbol:         "ACME-SAFE",
    uri:            "ipfs://acme-safe-art",
    securityClass:  SecurityClass.SAFE,
    securitySeries: SecuritySeries.NA,
    extension:      SAFE_EXTENSION_ADDR,
    seriesData:     "",       // series-scope payload encoded by `extension`
    defaultLegend:  legend
});

bytes32 roundId = IRoundManager(roundManager).createRound(round, certData);
```

## 3. Submit the investor's EOI

The investor signs the round's agreement offchain and submits an `EOI`
struct
([`RoundManagerStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/RoundManagerStorage.sol)).
The signature is the agreement registry's EIP-712 `SignatureData` for the
EOI agreement that `submitEOI` creates (the round's template, the investor's
`salt` and `secretHash`, and the RoundManager as finalizer), with the
investor as `signer`. [Sign a cyberAgreement](sign-a-cyberagreement.md)
gives the typed data. The registry verifies the signature inside
`submitEOI`, so a signature over the wrong id or type reverts the whole
call.

```solidity
import {EOI} from "src/storage/RoundManagerStorage.sol";

EOI memory eoi = EOI({
    name:          "Alice Investor LLC",
    investorType:  "entity",
    jurisdiction:  "USA",
    contact:       "alice@example.com",
    minAmount:     100_000e6,    // in payment-token decimals
    maxAmount:     100_000e6,
    expiry:        block.timestamp + 14 days,
    naturalPerson: false,
    lexchexDetails: lexchexDetails    // see LexChexDetails in the source
});

(bytes32 agreementId, uint256 tokenId) = IRoundManager(roundManager).submitEOI(
    roundId,
    eoi,
    globalValues,     // string[]
    partyValues,      // string[]
    investorSignature,// bytes (EIP-712)
    salt,             // uint256
    eoiConditions,    // address[]
    secretHash        // bytes32
);
```

## 4. Allocate the EOI

In a founder-approved round the officer allocates each accepted EOI. An
FCFS round allocates inside `submitEOI`, so it skips this step. `allocate`
prices the ticket, mints a SAFE LET from each of the round's LET contracts,
attaches the officer's escrowed signature and an endorsement, and refunds
any rounding dust.

```solidity
uint256 certTokenId = IRoundManager(roundManager).allocate(
    agreementId,
    100_000e6        // allocatedAmount, in payment-token decimals
);
```

## 5. Close the round

`closeRoundNow` closes the round before its `endTime`. Without it, the round
closes at `endTime`.

```solidity
IRoundManager(roundManager).closeRoundNow(roundId);
```

The investor now holds a SAFE LET. To trade it, [run a secondary
trade](run-a-secondary-trade.md) through the DealManager or [scripify it and
settle in scrip](scripify-and-settle.md). Function-level detail is in
[RoundManager](../reference/contracts/RoundManager.md).

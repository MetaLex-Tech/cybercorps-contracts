---
description: Deploy a cyberCORP and its contract suite, create a LET contract for its common stock, and issue the founder's first Ledger Entry Token
---

# Incorporate a cyberCORP

This guide deploys a new cyberCORP through a v5 factory, creates the Ledger
Entry Token (LET) contract for its Common Stock, and issues the first LET to
a founder. You finish with a `CyberCorp` and its suite (`IssuanceManager`,
`DealManager`, `RoundManager` and a `BorgAuth` ACL), one LET contract for
Common Stock, and one LET held by the founder.

## 1. Deploy the company and its suite

`CyberCorpFactory.deployCyberCorp` deploys the BorgAuth ACL and every
contract in the suite in one call.

```solidity
import {CompanyOfficer} from "src/CyberCorpConstants.sol";

CyberCorpFactory factory = CyberCorpFactory(FACTORY_ADDR);

CompanyOfficer memory officer = CompanyOfficer({
    eoa:     founder,
    name:    "Jane Founder",
    contact: "jane@acme.example",
    title:   "Chief Executive Officer"
});

(
    address cyberCorp,
    address auth,
    address issuanceManager,
    address dealManager,
    address roundManager
) = factory.deployCyberCorp(
    keccak256("acme-cyberco-v1"),     // salt (must be non-zero)
    "Acme CyberCo, Inc.",            // companyName
    "corporation",                   // companyType (free-form text)
    "Delaware",                      // companyJurisdiction
    "legal@acme.example",            // companyContactDetails
    "Delaware Court of Chancery",     // defaultDisputeResolution
    founder,                          // companyPayable
    officer
);
```

The factory grants BorgAuth level `200` (officer) to the founder and to the
`CyberCorp`, and level `99` (owner) to the IssuanceManager, DealManager and
RoundManager. The factory also keeps the level `99` that BorgAuth gives the
address that deploys it; see [Access control](../reference/access-control.md).
The call emits `CyberCorpDeployed`.

Before deploying, the factory hashes the salt with the company name, type,
jurisdiction, contact details, dispute forum, payout address and officer
(`computeDeploymentSalt`), and each component factory then namespaces the
result by its caller. Change any of those arguments and
the addresses change, so a deployment with other terms cannot take the
addresses your configuration predicts. Anyone may submit your exact
configuration, and the result is the same company with your officer in
control. On a v5 factory, every component of the new company reports
`DEPLOY_VERSION` `"5"`.

## 2. Create a LET contract for Common Stock

The `IssuanceManager` creates one LET contract (a `LedgerEntryToken`
deployment) per security series.

```solidity
import {SecurityClass, SecuritySeries} from "src/CyberCorpConstants.sol";

string[] memory legend = new string[](1);
legend[0] = "These securities have not been registered under the Securities Act of 1933...";

address commonPrinter = IIssuanceManager(issuanceManager).createCertPrinter(
    legend,                       // default legend
    "Acme CyberCo Common Stock",  // name
    "ACME-CS",                    // ticker
    "ipfs://acme-cert-art",       // certificate URI
    SecurityClass.CommonStock,
    SecuritySeries.NA,
    SHARE_EXTENSION_ADDR,         // certificate extension for this series
    ""                            // seriesData, the extension-encoded series-scope
                                  // payload; empty when the extension has none
);
```

## 3. Issue the founder's first LET

`createCertAndAssign` mints the founder's LET. Its metadata is a
`CertificateDetails` struct, defined in
[`ILedgerEntryToken.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/interfaces/ILedgerEntryToken.sol).

```solidity
import {CertificateDetails} from "src/interfaces/ILedgerEntryToken.sol";

CertificateDetails memory details = CertificateDetails({
    signingOfficerName:                  "Jane Founder",
    signingOfficerTitle:                 "Chief Executive Officer",
    investmentAmountUSD:                 0,
    issuerUSDValuationAtTimeOfInvestment: 0,
    unitsRepresented:                    8_000_000e18, // 8,000,000 shares (18-decimal)
    legalDetails:                        "Founder common stock",
    extensionData:                       ""   // ABI-encoded per the extension
});

uint256 tokenId = IIssuanceManager(issuanceManager).createCertAndAssign(
    commonPrinter,
    founder,
    details
);
```

`createCertAndAssign` mints the ERC-721 and records the founder as its
registered owner. On a v5 LET contract, `createCert` also records the
recipient as registered owner, with no name. The other `createCert*`
variants attach a name, an endorsement or a signature; [Issue a
LET](issue-a-let.md) compares them.

## 4. Read the LET back

```solidity
LedgerEntryToken printer = LedgerEntryToken(commonPrinter);

string  memory uri        = printer.tokenURI(tokenId);     // onchain JSON + SVG
address         tokenHolder = printer.ownerOf(tokenId);     // ERC-721 holder
address         registered  = printer.legalOwnerOf(tokenId);// registered owner of record
```

A LET tracks two owners. `ownerOf` returns the wallet that holds the token,
and `legalOwnerOf` returns the registered owner of record. They can differ:
an administered lot sits in an admin multisig while the buyer is its
registered owner. [LETs and scrip](../explanation/lets-and-scrip.md) explains
the model.

Next, [run a cyberRAISE round](run-a-cyberraise-round.md) on the new company.
Function-level detail is in
[IssuanceManager](../reference/contracts/IssuanceManager.md) and
[LedgerEntryToken](../reference/contracts/LedgerEntryToken.md).

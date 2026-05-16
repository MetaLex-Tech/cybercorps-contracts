# Tutorial: Incorporate a cyberCORP

In this tutorial you deploy a new cyberCORP, create a certificate printer for
its Common Stock, and issue the first cyberCERT to a founder.

At the end you will have a `CyberCorp` and its suite (`IssuanceManager`,
`DealManager`, `RoundManager`, plus a `BorgAuth` ACL), one `CyberCertPrinter`
for Common Stock, and one cyberCERT held by the founder.

> Code here is **illustrative of the flow** and uses the real contract
> signatures from `cybercorps-contracts` (`develop`). Confirm structs and
> parameters against the source before deploying.

## 1. Deploy the cyberCORP

New cyberCORPs are deployed by the **`CyberCorpFactory`**. A single
`deployCyberCorp` call deploys the BorgAuth ACL and the whole suite.

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

The factory grants the founder BorgAuth role `200` (officer) and grants the
IssuanceManager / DealManager / RoundManager role `99`. See
[Access control](../reference/access-control.md). It emits `CyberCorpDeployed`.

## 2. Create a Common Stock certificate printer

The `IssuanceManager` creates one `CyberCertPrinter` per security class.

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
    SHARE_EXTENSION_ADDR          // certificate extension for this class
);
```

## 3. Issue the genesis cyberCERT

Mint a cyberCERT to the founder with `createCertAndAssign`. The metadata is a
`CertificateDetails` struct (defined in
[`CyberCertPrinterStorage.sol`](https://github.com/MetaLex-Tech/cybercorps-contracts/blob/develop/src/storage/CyberCertPrinterStorage.sol)).

```solidity
import {CertificateDetails} from "src/storage/CyberCertPrinterStorage.sol";

CertificateDetails memory details = CertificateDetails({
    signingOfficerName:                  "Jane Founder",
    signingOfficerTitle:                 "Chief Executive Officer",
    investmentAmountUSD:                 0,
    issuerUSDValuationAtTimeOfInvestment: 0,
    unitsRepresented:                    8_000_000,
    legalDetails:                        "Founder common stock",
    extensionData:                       ""   // ABI-encoded per the extension
});

uint256 tokenId = IIssuanceManager(issuanceManager).createCertAndAssign(
    commonPrinter,
    founder,
    details
);
```

`createCertAndAssign` mints the ERC-721 *and* records the founder as the
registered owner. (`createCert` mints without assigning a registered owner;
other `createCert*` variants also attach a name, an endorsement, or a
signature — see [IssuanceManager](../reference/contracts/IssuanceManager.md).)

## 4. Inspect the register

```solidity
CyberCertPrinter printer = CyberCertPrinter(commonPrinter);

string  memory uri        = printer.tokenURI(tokenId);     // onchain JSON + SVG
address         tokenHolder = printer.ownerOf(tokenId);     // ERC-721 holder
address         registered  = printer.legalOwnerOf(tokenId);// registered owner of record
```

Note the two owners: `ownerOf` is the NFT holder; `legalOwnerOf` is the
registered owner of record. They are kept distinct on purpose — see
[The dual-token model](../explanation/dual-token-model.md).

## What you just did

* Deployed a cyberCORP and its full contract suite in one call.
* Created a Common Stock certificate printer.
* Issued the first register entry as a cyberCERT.

## Next

* [Run a cyberRAISE round](run-a-cyberraise-round.md).
* Reference: [IssuanceManager](../reference/contracts/IssuanceManager.md),
  [CyberCertPrinter](../reference/contracts/CyberCertPrinter.md).

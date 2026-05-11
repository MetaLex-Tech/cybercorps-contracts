# Tutorial: Incorporate a cyberCORP

In this tutorial you will deploy a brand-new cyberCORP representing a Delaware
C-corp, issue its first cyberCERT (a genesis share certificate), and inspect
the onchain register.

At the end, you will have:

* a `CyberCorp` proxy you control,
* an `IssuanceManager`, `DealManager`, `RoundManager`, `CyberCertPrinter` and
  `CyberShares` deployed as part of the suite,
* a single cyberCERT minted to a founder address representing 10,000,000
  authorized shares of Common Stock.

## 1. Pick a factory

New cyberCORPs are deployed by a `CyberCorpFactory`. The factory composes the
`CyberCorpSingleFactory`, `IssuanceManagerFactory`, `DealManagerFactory` and
`RoundManagerFactory` so that a single transaction produces a fully wired
suite.

Use the canonical Base Sepolia factory address from
[Deployments](../reference/deployments.md). Cast it to the
`ICyberCorpFactory` interface in your script.

## 2. Assemble the entity config

The `CyberCorp` contract stores the entity's legal identity. Fill in:

* **Legal name** — `"Acme CyberCo, Inc."`
* **Entity type** — `EntityType.DELAWARE_C_CORP`
* **Jurisdiction** — `"Delaware, USA"`
* **Governance roles** — addresses for `officer`, `director`,
  `secretary` (these become BorgAuth roles)
* **Default dispute resolution** — the URI of your governing arbitration
  clause or a sentinel
* **Authorized signatures** — initial escrowed signature data structures
* **Agreement registry** — address of the canonical `CyberAgreementRegistry`
  on your chain (see [Reference → Deployments](../reference/deployments.md))

See [`CyberCorp.sol`](../reference/contracts/CyberCorp.md) for the full struct.

## 3. Deploy via `createCyberCorp`

```solidity
ICyberCorpFactory factory = ICyberCorpFactory(FACTORY_ADDR);
address corp = factory.createCyberCorp(entityConfig, governanceConfig);
```

The factory will:

1. Deploy a UUPS `CyberCorp` proxy owned by your address.
2. Deploy an `IssuanceManager` proxy and grant it the issuance authority.
3. Deploy `CyberCertPrinter` (the ERC-721) and `CyberScrip` beacons under the
   `IssuanceManager`.
4. Deploy a `DealManager` and a `RoundManager`.
5. Wire all addresses into the root `CyberCorp` contract.

The transaction emits a `CyberCorpDeployed` event. Capture every address from
the event for the next step.

## 4. Issue the genesis cyberCERT

A cyberCORP is born with zero issued shares. You authorize, then issue.

```solidity
IIssuanceManager im = IIssuanceManager(issuanceManagerAddr);

// 4a. Authorise 10,000,000 shares of Common Stock under the share extension.
im.setAuthorizedShares(SHARE_CLASS_COMMON, 10_000_000);

// 4b. Build a CertIssuance struct (see CyberCertPrinter reference).
CertIssuance memory cert = CertIssuance({
    holderName: "Jane Founder",
    holderAddress: founder,
    units: 8_000_000,
    shareClass: SHARE_CLASS_COMMON,
    series: "",
    legend: "These securities have not been registered under the Securities Act of 1933...",
    agreementUri: "ipfs://...",
    acquisitionPriceUsd: 0,
    // ...
});

// 4c. Mint.
uint256 tokenId = im.issueCert(cert);
```

The call will:

* require the caller to hold the `ISSUER_AUTHORITY` BorgAuth role,
* increment `CyberShares.outstanding(SHARE_CLASS_COMMON)` by 8,000,000,
* mint an ERC-721 to `founder` whose `tokenURI` is a fully onchain JSON+SVG
  certificate produced by `CertificateUriBuilder`,
* emit `CertIssued(tokenId, ...)`.

## 5. Inspect the register

The register *is* the chain. Anything you want to know is readable:

```solidity
// What does this cert say?
string memory uri = CyberCertPrinter(certPrinter).tokenURI(tokenId);
// → data:application/json;base64,... with the rendered SVG inside

// Who owns it?
address owner = CyberCertPrinter(certPrinter).ownerOf(tokenId);

// How many Common shares are outstanding?
uint256 outstanding = CyberShares(sharesAddr).outstanding(SHARE_CLASS_COMMON);

// What is the entity?
string memory name = CyberCorp(corp).legalName();
EntityType etype = CyberCorp(corp).entityType();
```

There is no offchain ledger to reconcile against, no transfer agent to
instruct. Per the entity's governing documents, **this** is the official
stock ledger of Acme CyberCo, Inc.

## What you just did

* Deployed a Delaware C-corp whose DGCL §224 stock ledger lives natively
  onchain.
* Used BorgAuth's role separation to make the founder a director-officer and
  the IssuanceManager the only address that can mint share certificates.
* Produced an ERC-721 whose metadata is itself the legal record (DGCL §158
  share-certificate requirements are encoded into the token URI).

## Next

* Tutorial 2: [Run a cyberRAISE round](run-a-cyberraise-round.md) to actually
  raise capital from outside investors.
* Reference: [`CyberCertPrinter`](../reference/contracts/CyberCertPrinter.md),
  [`IssuanceManager`](../reference/contracts/IssuanceManager.md).
* Explanation:
  [Constitutive vs. pointer tokenization](../explanation/constitutive-vs-pointer.md).

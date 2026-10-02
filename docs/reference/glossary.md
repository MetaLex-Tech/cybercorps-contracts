# Glossary

**ACE (Asset Conversion to Equity)** — MetaLeX's product for converting a
token community into equity stakeholders. Live at
[ace.metalex.tech](https://ace.metalex.tech). Powered by `PumpCorpFactory`
and `ACESAFEExtension`.

**Agreement id** — The `bytes32` id of an agreement in
`CyberAgreementRegistry` (a deal, an EOI, a secondary settlement, or a
standalone cyberSign agreement). The current registry derives it from the
template id, salt, global values, parties, secret hash, and finalizer. See
[CyberAgreementRegistry](contracts/CyberAgreementRegistry.md).

**BorgAuth** — MetaLeX's role-based access control framework. See
[borg-core](https://github.com/MetaLex-Tech/borg-core).

**Cap table** — The ownership record the cyberCORPs app assembles,
displays, and exports: every position from every source (offchain entries,
cyberCERTs, cyberSCRIP) in one view. It is an app record; whether it, the
chain, or some other record is the company's *securities ledger* depends on
the company's governing documents.

**cyberCERT** — A *Ledger Entry Token* (ERC-721), minted by the
`LedgerEntryToken` contract (formerly `CyberCertPrinter`). One token = one
entry on a cyberCORP's register of holders.

**cyberCORP** — An onchain legal entity that issues legally constitutive
digital securities through this protocol.

**cyberCORPs app** — MetaLeX's issuer-facing app. A company's sidebar
sections are **mission control** (the company dashboard), **Incorporation
Hub**, **Documents**, **boardRoom**, **capTable**, **grants**,
**cyberRaise**, **Tokenization Hub**, and **cyberSign**. See
[the application stack](../explanation/application-stack.md#the-cybercorps-app).

**cyberRAISE** — Onchain primary fundraising. Implemented via `RoundManager`,
`DealManager`, and the LeXscroW escrow subsystem (`LexScrowStorage`). The
cyberCORPs app's sidebar entry for it reads **cyberRaise**.

**cyberSCRIP** — The ERC-20 fungible form of a cyberCORP security, minted
from a cyberCERT via `scripifyCert` and convertible back. Itself a security
in scrip form (e.g., DGCL §155).

**cyberSign** — Cybernetic legal-agreement execution layer. Implemented via
`CyberAgreementRegistry`.

**cyberTRADE** — Post-negotiation settlement for secondary trades of private
securities. Settles via the `DealManager` offer/acceptance flow (with an
elected exemption pathway) and the LeXscroW escrow subsystem.

**Constitutive tokenization** — Token issuance where the entity's governing
documents designate the onchain record as the official register, so the
chain *is* the register rather than a pointer to one. Contrast with pointer
tokenization.

**DGCL** — Delaware General Corporation Law. The most fully worked-out
statutory reference for the protocol.

**Endorsement** — A record appended to a cyberCERT documenting a state-
changing event (transfer, conversion, restriction change).

**EOI (Expression of Interest)** — An EIP-712-signed message in which an
investor declares intent to participate in a cyberRAISE round on stated
terms.

**Exemption pathway** — The securities-law exemption a secondary trade
settles under (`RULE_144`, `SECTION_4A7`, `SECTION_4A1HALF`, `RULE_144A`,
or `REGULATION_S`), elected per trade and enforced by
per-pathway [condition](conditions.md) sets on the `DealManager`.

**Incorporation Hub** — The cyberCORPs app's section for a company's
identity, formation progress and public onchain company record (formerly
labeled *company record*). See
[the boardRoom and Incorporation Hub](../webapp/boardroom.md#the-incorporation-hub).

**Legal terms** — The legal class, series and versioned terms recorded
behind a security class in the cyberCORPs app. One current officer wallet
approves an exact version before it activates; the cap table and its
exports read the activated version. See
[the cap table](../webapp/captable.md).

**LeXcheX** — MetaLeX's onchain accreditation / KYC-AML credential system.
Soulbound, wallet-bound NFT credentials.

**LeXcheXBadge** — The unified soulbound credential registry (LeXcheX v2,
`src/creds/lexchexBadge.sol`): fact-keyed credential attributes with
expiries, read by the badge-scoped secondary-trading
[conditions](conditions.md).

**LeXscroWLite** — The atomic deal-closing escrow subsystem. Now implemented
as the `LexScrowStorage` library linked into `DealManager` and
`RoundManager` (formerly a standalone contract).

**LiquiLeX** — AMM-native secondary liquidity for cyberSCRIPs, using
Uniswap v4 pools and the `MetalexIssuerFeeHook`.

**MetaDAO** — A futarchy-governed Cayman SPC structure deployed via
`MetaDAOFactory`.

**Pointer tokenization** — Token issuance where the chain is a notification
layer; the official register lives offchain. Contrast with constitutive
tokenization.

**Public company page** — A wallet-free page for every cyberCORP, at
`cybercorps.metalex.tech/company/{chainId}/{address}`, showing what the
chain and the public indexer record about it. See
[Launchpads](../webapp/metadao.md#public-company-pages).

**PumpCorp** — A cyberCORP variant deployed by `PumpCorpFactory` for ACE.

**Reg D / Reg S** — Two exemption frameworks for private securities under
the US Securities Act of 1933. Reg D is the US-investor framework
(accreditation-driven); Reg S is the non-US-investor framework.

**Scripification** — Minting cyberSCRIP from a cyberCERT.

**Securities ledger** — The company's legally definitive record of its
securities. Which record that is (the chain, the app's cap table, or
something else) depends on the company's governing documents, such as its
bylaws; it never follows from tokenization or from where data is stored.

**SegCo** — Segregated Portfolio Company portfolio (Cayman SPC structure).

**Tokenization Hub** — The securities console of the cyberCORPs app
(formerly called the *Mainframe*): configure, issue, and manage tokenized
securities. The app's company dashboard is a separate section,
**mission control**. Reference UI at
[`apps/cybercorps-web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web).
Used by MetaDAO.

**Tokenized / untokenized** — Whether units have a token onchain (a
cyberCERT or cyberSCRIP). Says nothing about where a record is stored or
which record is definitive.

**Umia** — A token launchpad that, like MetaDAO, prescribes the legal entity
a project uses; the cyberCORPs app has a formation page for it. See
[Launchpads](../webapp/metadao.md).

**Unregistered scrip** — cyberSCRIP in a holder's wallet beyond what
recorded grants' withdrawals explain: beneficial units with no registered
position accounting for them. The cyberCORPs app flags it for review.

**zkPassport** — Privacy-preserving passport credential used by
`NonUSNationalityCondition`.

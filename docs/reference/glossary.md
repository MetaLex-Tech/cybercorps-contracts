# Glossary

**ACE (Asset Conversion to Equity)** — MetaLeX's product for converting a
token community into equity stakeholders. Live at
[ace.metalex.tech](https://ace.metalex.tech). Powered by `PumpCorpFactory`
and `ACESAFEExtension`.

**BorgAuth** — MetaLeX's role-based access control framework. See
[borg-core](https://github.com/MetaLex-Tech/borg-core).

**cyberCERT** — A *Ledger Entry Token* (ERC-721). One token = one entry on a
cyberCORP's register of holders.

**cyberCORP** — An onchain legal entity that issues legally constitutive
digital securities through this protocol.

**cyberRAISE** — Onchain primary fundraising. Implemented via `RoundManager`,
`DealManager`, and `LeXscroWLite`.

**cyberSCRIP** — The ERC-20 fungible form of a cyberCORP security, minted
from a cyberCERT via `scripifyCert` and convertible back. Itself a security
in scrip form (e.g., DGCL §155).

**cyberSign** — Cybernetic legal-agreement execution layer. Implemented via
`CyberAgreementRegistry`.

**cyberTRADE** — Post-negotiation settlement for secondary trades of private
securities. Settles via `DealManager` + `LeXscroWLite`.

**Constitutive tokenization** — Token issuance where the chain *is* the
official register, not a pointer to one. Contrast with pointer tokenization.

**DGCL** — Delaware General Corporation Law. The most fully worked-out
statutory reference for the protocol.

**Endorsement** — A record appended to a cyberCERT documenting a state-
changing event (transfer, conversion, restriction change).

**EOI (Expression of Interest)** — An EIP-712-signed message in which an
investor declares intent to participate in a cyberRAISE round on stated
terms.

**LeXcheX** — MetaLeX's onchain accreditation / KYC-AML credential system.
Soulbound, wallet-bound NFT credentials.

**LeXscroWLite** — The atomic deal-closing escrow contract.

**LiquiLeX** — AMM-native secondary liquidity for cyberSCRIPs, using
Uniswap v4 pools and the `MetalexIssuerFeeHook`.

**Mainframe** — The issuer-facing application surface in the cyberCORPs app.
Reference UI at
[`apps/cybercorps-web`](https://github.com/MetaLex-Tech/metalex-webapp/tree/develop/apps/cybercorps-web).

**MetaDAO** — A futarchy-governed Cayman SPC structure deployed via
`MetaDAOFactory`.

**Pointer tokenization** — Token issuance where the chain is a notification
layer; the official register lives offchain. Contrast with constitutive
tokenization.

**PumpCorp** — A cyberCORP variant deployed by `PumpCorpFactory` for ACE.

**Reg D / Reg S** — Two exemption frameworks for private securities under
the US Securities Act of 1933. Reg D is the US-investor framework
(accreditation-driven); Reg S is the non-US-investor framework.

**Scripification** — Minting cyberSCRIP from a cyberCERT.

**SegCo** — Segregated Portfolio Company portfolio (Cayman SPC structure).
Used by MetaDAO.

**zkPassport** — Privacy-preserving passport credential used by
`NonUSNationalityCondition`.

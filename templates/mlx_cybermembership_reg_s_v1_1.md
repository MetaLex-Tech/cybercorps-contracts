# Approved v1.1 Data Overview

For new P2PIX governance Membership Units rounds, use this approved v1.1 identity. The [historical v1.0 sheet](mlx_cybermembership_reg_s_v1_0.md) remains a separate record. Never replace its ID, title, URI or signed agreement data with this revision.

id: bytes32(bytes("metalex_cybermember_reg_s_v1_1"))
idHex: 0x6d6574616c65785f63796265726d656d6265725f7265675f735f76315f310000
templateName: metalex_cybermember_reg_s_v1_1
title: P2PIX cyberMembership Subscription Agreement Reg S v.1.1

legalURI: ipfs://bafybeibwqh4zaj2zfgev6bhnrtl2mdokqc6lwjyxlz3klfovop537aztgu
classDocumentURI: ipfs://bafkreiaosrwlfjvrj66miwwocuxp5fitsqbwss76ua75nkbb4sfrq3ry4i

The owner approved the exact 60-page combined packet and its public IPFS upload. It contains the revised subscription agreement and Exhibits A to F, followed by the unchanged certified Operating Agreement and Tokenized Membership Amendment v2. The combined PDF is 3,935,199 bytes with SHA-256 `0097e6ee50ab61de47c60019c937afec48d7257c82e5832010312ce2c6bf4ef3`. The separate amendment remains SHA-256 `0e946cb2a6b14fbcc45ace152efe95139403694bfea03fd6a821e48b186e38e2`.

This packet identifies only P2PIX DAO LLC, Ethereum chain 1, company `0x5eB44812A8745f42D03EB994897b7e1F419a78C7`. It must not be used for another issuer or chain. The template name is 30 UTF-8 bytes, right-padded with two zero bytes for the exact bytes32 ID above; it is not a name hash.

## Global Fields

Keep these names and this order. The field schema is unchanged from v1.0; the v1.1 paper changes their legal effect.

| globalFieldName | v1.1 meaning |
| --- | --- |
| contributionPerUnit | Informational estimate of the contribution per Unit. The applicable Round's `pricePerUnit` used in Original Settlement controls under Section 1.5. |
| numMembershipUnits | Informational estimate of the subscribed quantity. Original issued Units are determined by Original Settlement under Section 1.5, not by this string. |
| governingJurisdiction | Supply `Marshall Islands`. Section 5.1 fixes the governing law; a conflicting string does not change it. |
| disputeResolution | Supply `courtResolution`. Section 5.2 and Exhibit C fix court resolution; this field does not select another procedure. |
| customProvisions | Reserved transport field; supply an empty string. Section 7 makes supplied text nonoperative. A separate amendment or waiver requires Section 5.4. |

The paper identifies Original Settlement through the chain, registry, agreement ID and original Round Manager finalizer, with the issuer and class identified in the packet. Original `AllocationMade` certificate IDs link the agreement to the original `CertificateCreated.details.unitsRepresented`. Section 1.5 and Exhibit F address partial and cap-limited allocations, FCFS settlement, truncation and refunds. Later transfers, scripification or replacement certificates do not rewrite that original issuance evidence.

The Membership Contribution is the amount actually applied to the issuance and is non-refundable. Unallocated or truncation-related returned funds are not part of that Membership Contribution. At a Round price of 0.05 USDC per Unit, a full 500 USDC allocation records `investmentAmountUSD = 500e18` and `unitsRepresented = 10000e18`; a smaller allocation must be interpreted from its actual Original Settlement.

## Party Fields

These names and their order are unchanged. Keep the application's existing privacy and encryption behavior.

| partyFieldName | Description |
| --- | --- |
| name | Name of the individual or entity. |
| evmAddress | EVM address of the signing party. |
| contactDetails | Contact information, subject to the application's encryption settings. |
| entityType | Entity type; blank for a natural person. |
| entityJurisdiction | Jurisdiction of formation; blank for a natural person. |

## Certificate and Class Configuration

- Security class: `MembershipInterest` (13); security series: `NA` (8).
- Certificate extension: zero address; `seriesData = "0x"`; certificate `extensionData = "0x"`.
- Class record: the unchanged amendment URI above, zero extension and empty class data. Use the actual existing class if it matches; an authorized class update must be reviewed against the current record.
- Membership Units carry votes and no economic rights. Record zero valuation and the seven restrictive legends in Exhibit A Part 3.
- Primary issuance uses the existing overridable non-U.S. nationality condition. This revision does not change protocol authorization, transfer defaults or scrip behavior.

## Unsigned Registration and Controller Workflow

The prepared call is `createTemplate(bytes32,string,string,string[],string[])` on Ethereum chain 1 registry `0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134`, value zero. Its argument order is ID, title, legal URI, the five ordered global field names, then the five ordered party field names. The exact approved tuple above encodes to calldata keccak256 `0xf690f6496e9d30d1e51a739d9882b2af6ddaefab85966636bab408a965882d3e`.

At Ethereum block 26273510, the ID returned `TemplateDoesNotExist()` and read-only registration simulations succeeded from both an arbitrary role-zero account and the existing company officer. Registration is permissionless; no company role grant is required for this registry call. This observation is historical, not a current absence claim or evidence of registration.

Refresh the registry runtime and `getTemplateDetails` immediately before any separately authorized signing. If the ID already exists, require the exact title, URI and both ordered field arrays above; do not overwrite, silently substitute or duplicate an occupied ID. After a separately authorized registration, read back and compare all five values. Paper/publication approval does not authorize signing or submitting the prepared registration. This sheet records no submitted mainnet transaction.

The controller of the existing company officer wallet handles ordinary company setup and legal-term approval. Use the app's guided Upgrade page and the preserving-field jurisdiction correction as needed for the actual company state, then its normal class-record, legal-identity, approval and activation controls. No new officer, manual database mapping or protocol change is required by this sheet. Template registration alone does not create a class, activate company legal terms or open a round.

Current application, controller and verification evidence is maintained in the [webapp task record](https://github.com/MetaLex-Tech/metalex-webapp/blob/develop/notes/ai/tasks/cybermembership-reg-s-round.md). Company actions remain separate from frontend release. This documentation does not change contracts, register a template, sign an agreement or establish live launch acceptance.

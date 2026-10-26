# Historical v1.0 Data Overview

This sheet retains the original v1.0 identity and paper. For new P2PIX rounds, use the separately approved [v1.1 sheet](mlx_cybermembership_reg_s_v1_1.md). For any agreement using v1.0, retain its actual template ID, title, URI, ordered fields and original manager/finalizer routing. Do not substitute v1.1 paper or field semantics under this ID.

id: bytes32(bytes("metalex_cybermember_reg_s_v1_0"))
idHex: 0x6d6574616c65785f63796265726d656d6265725f7265675f735f76315f300000
templateName: metalex_cybermember_reg_s_v1_0
title: MetaLeX cyberMembership Subscription Agreement Reg S v.1

legalURI: ipfs://bafybeih2nqfz6tgdwrbihgglduooescrpwdzu3ce2l7hj6qvejwa7yzvva
classDocumentURI: ipfs://bafkreiaosrwlfjvrj66miwwocuxp5fitsqbwss76ua75nkbb4sfrq3ry4i

The owner approved the 30-byte name `metalex_cybermember_reg_s_v1_0` on October 25, 2026. The originally supplied `metalex_cybermembership_reg_s_v1_0` exceeds bytes32. The filename retains the requested document name; registration uses the approved name and exact ID above.

The legal URI identifies the October 25 P2PIX combined pack: subscription agreement and Exhibits A to E, certified Operating Agreement, and Tokenized Membership Amendment v2. The class document URI identifies the amendment alone. This combined pack contains P2PIX-specific governing documents and must not be used for another issuer.

## Global Fields

| globalFieldName | Description |
| --- | --- |
| contributionPerUnit | Membership Contribution per Membership Unit in the denomination token; `0.05` for this round. |
| numMembershipUnits | Membership Units subscribed for; `10000` for a 500 USDC contribution at 0.05 per Unit. |
| governingJurisdiction | `Marshall Islands` for P2PIX. |
| disputeResolution | `courtResolution`, consistent with the Operating Agreement. |
| customProvisions | Additional provisions, or an empty string. |

## Party Fields

These exact names and order were read from the registered `metalex_cyberstock_reg_d_v1_0` template on Base Sepolia.

| partyFieldName | Description |
| --- | --- |
| name | Name of the individual or entity. |
| evmAddress | EVM address of the signing party. |
| contactDetails | Contact information, subject to the application's existing encryption settings. |
| entityType | Entity type; blank for a natural person. |
| entityJurisdiction | Jurisdiction of formation; blank for a natural person. |

## Certificate and Class Configuration

- Security class: `MembershipInterest` (13).
- Security series: `NA` (8).
- Certificate extension: zero address; `seriesData = "0x"`; certificate `extensionData = "0x"`.
- Class record: define type 13 with `classDocumentURI`, zero extension and empty class data before printer creation. If type 13 already exists, review the record and use the existing owner-only update operation.
- Seven default restrictive legends: use Exhibit A Part 3 verbatim, including the Non-Economic Membership, Transfer Restriction, Operating Agreement, Tokenized Membership Register, MAEE, Regulation S and Securities Act legends.
- Membership Units carry votes and no economic rights. Contributions are non-refundable. Record zero valuation.
- Primary issuance: the existing overridable non-U.S. nationality condition. The secondary Reg S distribution condition is a separate workflow.

`RoundManager.allocate` normalizes USDC to 18 decimals. A 500 USDC allocation records `investmentAmountUSD = 500e18` and `unitsRepresented = 10000e18` at 0.05 per Unit.

## Registration and Verification Status

Both PDFs were pinned through the configured Pinata service. Retrieved bytes match these SHA-256 digests:

- Combined pack: `010e648320d51a567e1f64e49bddd076e6b7dbd9bc53b70e9c018ebbdd67aff1`.
- Amendment: `0e946cb2a6b14fbcc45ace152efe95139403694bfea03fd6a821e48b186e38e2`.

This data sheet does not register the template or deploy contracts. Earlier Base Sepolia and Base launch guidance is superseded: the selected P2PIX issuer is the existing company on Ethereum chain 1, and new rounds use the separate v1.1 identity. Do not register this historical payload as the new v1.1 packet or overwrite an occupied ID. Resolve any existing agreement from its actual onchain template ID and verify the matching title, URI and ordered fields.

The current application, Ethereum runtime and controller evidence are maintained in the [webapp task record](https://github.com/MetaLex-Tech/metalex-webapp/blob/develop/notes/ai/tasks/cybermembership-reg-s-round.md). The earlier Base fork results are historical. No Solidity implementation changes are required by this data sheet.

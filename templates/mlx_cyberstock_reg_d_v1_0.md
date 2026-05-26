# Data Overview

id: bytes32(bytes("mlx_cyberstock_reg_d_v1_0"))
idHex: 0x6d6c785f637962657273746f636b5f7265675f645f76315f3000000000000000
title: mlx_cyberstock_reg_d_v1_0

<!-- TODO WIP -->
legalURI: IPFS://[CID assigned at pinning of cyberSTOCK Purchase Agreement v6]

<!-- TODO WIP -->
doc: https://beige-just-flyingfish-108.mypinata.cloud/ipfs/[CID]

## Global Fields

| **globalFieldName**   | **description**                                                                                                                                                                         |
|:----------------------|:----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| purchasePricePerShare | Price per Tokenized Share, denominated in units of the Denomination Token (e.g. "0.10"). Must equal the originalIssuePrice for the Applicable Series in the CyberCertPrinter ShareData. |
| numTokenizedShares    | Number of Tokenized Shares of the Applicable Series being purchased (e.g. "1000000").                                                                                                   |
| governingJurisdiction | Governing law jurisdiction (e.g. "Delaware").                                                                                                                                           |
| disputeResolution     | "bindingArbitration" \| "courtResolution" \| custom string specifying an alternative procedure.                                                                                         |

## Party Fields

| **partyFieldName** | **description**                                                                          |
|:-------------------|:-----------------------------------------------------------------------------------------|
| name               | Name of the individual or organization                                                   |
| evmAddress         |                                                                                          |
| contactDetails     |                                                                                          |
| entityType         | Entity type if party is an entity; blank for natural persons                             |
| entityJurisdiction | Jurisdiction of incorporation/formation if party is an entity; blank for natural persons |

## Certificate Extension

- [ShareExtension.sol](../src/storage/extensions/ShareExtension.sol)
- [ShareExtensionLogic.sol](../src/storage/extensions/ShareExtensionLogic.sol)

/*    .o.
     .888.
    .8"888.
   .8' `888.
  .88ooo8888.
 .8'     `888.
o88o     o8888o



ooo        ooooo               .             ooooo                  ooooooo  ooooo
`88.       .888'             .o8             `888'                   `8888    d8'
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o



  .oooooo.                .o8                            .oooooo.
 d8P'  `Y8b              "888                           d8P'  `Y8b
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o.
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
             .o..P'                                                                     888
             `Y8P'                                                                     o888o
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published,
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system,
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import {ICyberAgreementRegistry} from "../interfaces/ICyberAgreementRegistry.sol";

/// @title CyberAgreementRegistryStorage
/// @notice Storage of the agreement registry. The registry and its linked libraries read it at one fixed slot.
library CyberAgreementRegistryStorage {
    // The live proxy keeps its state from slot 1. Slot 0 is BorgAuthACL.AUTH. The struct starts at
    // slot 1, so the live data stays readable with no migration. Do not change the field order. Add
    // new fields at the end only.
    bytes32 constant STORAGE_POSITION = bytes32(uint256(1));

    struct AgreementData {
        bytes32 templateId; // ID of the template this contract uses
        string[] globalValues; // Values for the global fields
        address[] parties; // List of parties who should sign. Use zeroAddress for unknown counterparty
        mapping(address => string[]) partyValues; // Each signer's field data
        mapping(address => uint256) signedAt; // Timestamp when each party signed (0 if unsigned)
        uint256 numSignatures; // Number of parties who have signed
        address finalizer;
        bool finalized;
        bool voided;
        bytes32 secretHash;
        uint256 expiry;
        address[] voidRequestedBy;
    }

    struct Delegation {
        address delegate;
        uint256 expiry;
    }

    // Main storage layout struct
    struct StorageData {
        // Domain information
        string version;
        bytes32 domainSeparator;
        // The registry does not read these fields now. Keep them so the layout does not move.
        bytes32 deprecatedSignatureTypehash;
        bytes32 deprecatedVoidSignatureDataTypehash;
        mapping(bytes32 => string[]) deprecatedClosedAgreementValues;
        // Mapping of templateId => template data
        mapping(bytes32 => ICyberAgreementRegistry.Template) templates;
        // Mapping of contractId => contract data
        mapping(bytes32 => AgreementData) agreements;
        // A mapping connecting an address to all the agreements they are a party to
        mapping(address => bytes32[]) agreementsForParty;
        mapping(address => Delegation) delegations;
    }

    // Returns the storage layout
    function getStorageData() internal pure returns (StorageData storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }
}

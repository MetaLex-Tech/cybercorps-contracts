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

import {ISignerConditions, SignerCondition} from "../interfaces/ISignerConditions.sol";
import {ZKPassportConditionLib} from "./ZKPassportConditionLib.sol";

/// @title SignerConditionLib
/// @notice Stores the conditions of each party and sends each check to the library of its kind.
/// It runs inside the registry, so its state is in the registry's storage.
library SignerConditionLib {
    struct SignerConditionStorage {
        mapping(bytes32 => mapping(address => SignerCondition[])) conditions; // contractId => party => conditions
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.agreements.signer-conditions.storage.v1");

    function conditionsOf(bytes32 contractId, address party) internal view returns (SignerCondition[] storage) {
        return _storage().conditions[contractId][party];
    }

    /// @dev An empty list means no conditions. Otherwise each party has one list.
    function checkLength(SignerCondition[][] memory conditions, uint256 partyCount) internal pure {
        if (conditions.length != 0 && conditions.length != partyCount) {
            revert ISignerConditions.SignerConditionsLengthMismatch();
        }
    }

    /// @notice Store `conditions[i]` for `parties[i]`. Each condition must have a known kind and valid params.
    function set(bytes32 contractId, address[] memory parties, SignerCondition[][] memory conditions) internal {
        SignerConditionStorage storage $ = _storage();
        for (uint256 i = 0; i < conditions.length; i++) {
            for (uint256 j = 0; j < conditions[i].length; j++) {
                SignerCondition memory condition = conditions[i][j];
                _validateParams(condition.kind, condition.params);
                $.conditions[contractId][parties[i]].push(condition);
                emit ISignerConditions.SignerConditionSet(contractId, parties[i], j, condition.kind, condition.params);
            }
        }
    }

    /// @notice Check each condition of `party` with its evidence. `evidence[j]` is for condition `j`.
    /// Revert unless all pass.
    function verifyAll(bytes32 contractId, address party, bytes[] memory evidence) internal {
        SignerCondition[] storage conditions = _storage().conditions[contractId][party];
        for (uint256 j = 0; j < conditions.length; j++) {
            bytes32 kind = conditions[j].kind;
            bytes memory result;
            if (kind == ZKPassportConditionLib.KIND) {
                result = ZKPassportConditionLib.verify(contractId, party, conditions[j].params, evidence[j]);
            } else {
                revert ISignerConditions.UnknownSignerConditionKind(kind);
            }
            emit ISignerConditions.SignerConditionMet(contractId, party, j, kind, result);
        }
    }

    function setConfig(bytes32 kind, bytes memory config) internal {
        if (kind == ZKPassportConditionLib.KIND) {
            ZKPassportConditionLib.setConfig(config);
        } else {
            revert ISignerConditions.UnknownSignerConditionKind(kind);
        }
        emit ISignerConditions.SignerConditionConfigSet(kind, config);
    }

    function getConfig(bytes32 kind) internal view returns (bytes memory) {
        if (kind == ZKPassportConditionLib.KIND) return ZKPassportConditionLib.getConfig();
        revert ISignerConditions.UnknownSignerConditionKind(kind);
    }

    function _validateParams(bytes32 kind, bytes memory params) private view {
        if (kind == ZKPassportConditionLib.KIND) {
            ZKPassportConditionLib.validateParams(params);
        } else {
            revert ISignerConditions.UnknownSignerConditionKind(kind);
        }
    }

    function _storage() private pure returns (SignerConditionStorage storage $) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }
}

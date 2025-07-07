// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "./baseCondition.sol";
import "../../interfaces/ILexChex.sol";
import "../LexScroWLite.sol";

/// @title  LexChexCondition - A condition that checks if the user has a valid LexChex accreditation
/// @author MetaLeX Labs, Inc.

    contract LexChexCondition is BaseCondition {

    address public lexchex;

    constructor(address _lexchex) {
        lexchex = _lexchex;
    }

    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data) public view override returns (bool) {
        LexScroWLite lexScrow = LexScroWLite(_contract);
        bytes32 agreementId = abi.decode(data, (bytes32));
        
        // Get the counterparty address directly from escrow details
        address counterparty = lexScrow.getEscrowDetails(agreementId).counterParty;
        
        // Get all LexChex token IDs owned by the counterparty
        uint256[] memory tokenIds = ILexChex(lexchex).getTokenIdsByOwner(counterparty);
        
        // If no tokens, return false
        if (tokenIds.length == 0) {
            return false;
        }
        
        // Check if at least one token is valid
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (ILexChex(lexchex).isValid(tokenIds[i])) {
                return true; // Found at least one valid token
            }
        }
        
        // No valid tokens found
        return false;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(ICondition).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
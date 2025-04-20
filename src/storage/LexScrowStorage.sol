// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.28;

import "../interfaces/ICondition.sol";

enum TokenType {
    ERC20,
    ERC721,
    ERC1155
}

enum EscrowStatus {
    PENDING,
    PAID,
    FINALIZED,
    VOIDED
}

struct Token {
    TokenType tokenType;
    address tokenAddress;
    uint256 tokenId;
    uint256 amount;
}

struct Escrow {
    bytes32 agreementId;
    address counterParty;
    Token[] corpAssets;
    Token[] buyerAssets;
    bytes signature;
    uint256 expiry;
    EscrowStatus status;
}

library LexScrowStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.lexscrow.storage.v1");

    // Main storage layout struct
    struct LexScrowData {
        address CORP;
        address DEAL_REGISTRY;
        mapping(bytes32 => Escrow) escrows;
        mapping(bytes32 => ICondition[]) conditionsByEscrow;
    }

    // Returns the storage layout
    function lexScrowStorage() internal pure returns (LexScrowData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // Getters
    function getCorp() internal view returns (address) {
        return lexScrowStorage().CORP;
    }

    function getDealRegistry() internal view returns (address) {
        return lexScrowStorage().DEAL_REGISTRY;
    }

    function getEscrow(bytes32 agreementId) internal view returns (Escrow storage) {
        return lexScrowStorage().escrows[agreementId];
    }

    function getConditionsByEscrow(bytes32 agreementId) internal view returns (ICondition[] storage) {
        return lexScrowStorage().conditionsByEscrow[agreementId];
    }

    // Setters
    function setCorp(address _corp) internal {
        lexScrowStorage().CORP = _corp;
    }

    function setDealRegistry(address _dealRegistry) internal {
        lexScrowStorage().DEAL_REGISTRY = _dealRegistry;
    }

    function setEscrow(bytes32 agreementId, Escrow memory escrow) internal {
        lexScrowStorage().escrows[agreementId] = escrow;
    }

    function addConditionToEscrow(bytes32 agreementId, ICondition condition) internal {
        lexScrowStorage().conditionsByEscrow[agreementId].push(condition);
    }

    function removeConditionFromEscrow(bytes32 agreementId, uint256 index) internal {
        ICondition[] storage conditions = lexScrowStorage().conditionsByEscrow[agreementId];
        require(index < conditions.length, "Index out of bounds");
        
        for (uint i = index; i < conditions.length - 1; i++) {
            conditions[i] = conditions[i + 1];
        }
        conditions.pop();
    }
} 
// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.28;

import "../interfaces/IIssuanceManager.sol";

library DealManagerStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.deal.manager.storage.v1");

    // Main storage layout struct
    struct DealManagerData {
        // Core contract references
        IIssuanceManager issuanceManager;
        
        // Deal-specific data
        mapping(bytes32 => string[]) counterPartyValues;
    }

    // Returns the storage layout
    function dealManagerStorage() internal pure returns (DealManagerData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    // Getters
    function getCounterPartyValues(bytes32 agreementId) internal view returns (string[] storage) {
        return dealManagerStorage().counterPartyValues[agreementId];
    }

    function getIssuanceManager() internal view returns (IIssuanceManager) {
        return dealManagerStorage().issuanceManager;
    }

    // Setters
    function setCounterPartyValues(bytes32 agreementId, string[] memory values) internal {
        dealManagerStorage().counterPartyValues[agreementId] = values;
    }

    function setIssuanceManager(address _issuanceManager) internal {
        dealManagerStorage().issuanceManager = IIssuanceManager(_issuanceManager);
    }
} 
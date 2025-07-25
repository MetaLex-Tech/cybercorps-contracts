pragma solidity 0.8.28;

import "../interfaces/IIssuanceManager.sol";
import "../interfaces/ICondition.sol";

enum RoundType {
    FCFS,
    FounderApproved
}

struct Round {
    bytes32 id;
    string seriesType;
    uint256 raiseCap;
    uint256 minTicket;
    uint256 maxTicket;
    RoundType roundType;
    string terms;
    uint256 startTime;
    uint256 endTime;
    bytes32 templateId;
    address certPrinter;
    address paymentToken;
    uint256 pricePerUnit;
    uint256 valuation;
    uint256 paymentDecimals;
    uint256 raised;
}

struct EOI {
    string name;
    string investorType;
    string jurisdiction;
    string contact;
    uint256 minAmount;
    uint256 maxAmount;
}

/// @title RoundManagerStorage
/// @notice Storage library for the RoundManager contract that handles persistent data storage
/// @dev Uses the unstructured storage pattern to manage round-related data
library RoundManagerStorage {
    // Storage slot for our struct
    bytes32 constant STORAGE_POSITION = keccak256("cybercorp.round.manager.storage.v1");

    /// @notice Main storage layout struct that holds all round manager data
    /// @dev Uses unstructured storage pattern to avoid storage collisions
    struct RoundManagerData {
        /// @notice Reference to the issuance manager contract
        IIssuanceManager issuanceManager;
        address upgradeFactory;
        
        /// @notice Mapping from round IDs to their data
        mapping(bytes32 => Round) rounds;
        
        /// @notice Mapping from agreement IDs to their round ID
        mapping(bytes32 => bytes32) agreementToRound;
        
        /// @notice Mapping from round IDs to list of agreement IDs
        mapping(bytes32 => bytes32[]) roundToAgreements;
        
        /// @notice Mapping from agreement IDs to EOI data
        mapping(bytes32 => EOI) agreementToEOI;
        
        /// @notice Mapping from agreement IDs to pre-signed void signatures
        mapping(bytes32 => bytes) voidSignatures;
    }

    /// @notice Retrieves the storage reference for the RoundManagerData struct
    /// @dev Uses assembly to compute the storage position
    /// @return ds Reference to the RoundManagerData struct in storage
    function roundManagerStorage() internal pure returns (RoundManagerData storage ds) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /// @notice Retrieves a specific round's data
    /// @param roundId The unique identifier of the round
    /// @return Round The round data struct
    function getRound(bytes32 roundId) internal view returns (Round storage) {
        return roundManagerStorage().rounds[roundId];
    }

    /// @notice Sets a round's data
    /// @param roundId The unique identifier of the round
    /// @param round The round data to store
    function setRound(bytes32 roundId, Round memory round) internal {
        roundManagerStorage().rounds[roundId] = round;
    }

    /// @notice Retrieves the round ID for an agreement
    /// @param agreementId The agreement identifier
    /// @return bytes32 The round ID
    function getAgreementToRound(bytes32 agreementId) internal view returns (bytes32) {
        return roundManagerStorage().agreementToRound[agreementId];
    }

    /// @notice Sets the round ID for an agreement
    /// @param agreementId The agreement identifier
    /// @param roundId The round ID to associate
    function setAgreementToRound(bytes32 agreementId, bytes32 roundId) internal {
        roundManagerStorage().agreementToRound[agreementId] = roundId;
    }

    /// @notice Retrieves the list of agreements for a round
    /// @param roundId The round identifier
    /// @return bytes32[] Array of agreement IDs
    function getRoundToAgreements(bytes32 roundId) internal view returns (bytes32[] storage) {
        return roundManagerStorage().roundToAgreements[roundId];
    }

    /// @notice Retrieves EOI data for an agreement
    /// @param agreementId The agreement identifier
    /// @return EOI The EOI struct
    function getAgreementToEOI(bytes32 agreementId) internal view returns (EOI storage) {
        return roundManagerStorage().agreementToEOI[agreementId];
    }

    /// @notice Sets EOI data for an agreement
    /// @param agreementId The agreement identifier
    /// @param eoi The EOI data to store
    function setAgreementToEOI(bytes32 agreementId, EOI memory eoi) internal {
        roundManagerStorage().agreementToEOI[agreementId] = eoi;
    }

    /// @notice Retrieves the pre-signed void signature for an agreement
    /// @param agreementId The agreement identifier
    /// @return bytes The void signature
    function getVoidSignature(bytes32 agreementId) internal view returns (bytes storage) {
        return roundManagerStorage().voidSignatures[agreementId];
    }

    /// @notice Sets the pre-signed void signature for an agreement
    /// @param agreementId The agreement identifier
    /// @param signature The void signature to store
    function setVoidSignature(bytes32 agreementId, bytes memory signature) internal {
        roundManagerStorage().voidSignatures[agreementId] = signature;
    }

    /// @notice Retrieves the current issuance manager
    /// @return IIssuanceManager The current issuance manager contract
    function getIssuanceManager() internal view returns (IIssuanceManager) {
        return roundManagerStorage().issuanceManager;
    }

    /// @notice Updates the issuance manager reference
    /// @param _issuanceManager Address of the new issuance manager contract
    function setIssuanceManager(address _issuanceManager) internal {
        roundManagerStorage().issuanceManager = IIssuanceManager(_issuanceManager);
    }

    function setUpgradeFactory(address _upgradeFactory) internal {
        roundManagerStorage().upgradeFactory = _upgradeFactory;
    }

    function getUpgradeFactory() external view returns (address) {
        return roundManagerStorage().upgradeFactory;
    }
}


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

import "../interfaces/IIssuanceManager.sol";
import "../interfaces/ICondition.sol";

enum RoundType {
    FCFS,
    FounderApproved
}

enum RoundingMode {
    Floor,
    Ceil,
    Round
}

struct CapTableSnapshot {
    uint256 totalCapitalSecuritiesOutstanding;
    uint256 totalConvertingSecurities;
    uint256 totalOptionsIssuedAndOutstanding;
    uint256 totalPromisedOptions;
    uint256 unissuedOptionPoolPreRound;
    uint256 unissuedOptionPoolIncreaseIncludedInCalc;
    uint256 cCapUsed; // computed capitalization used for conversions
}

struct RoundingPolicy {
    RoundingMode mode;
    uint8 priceDecimals; // decimals used for price math
    uint8 shareDecimals; // decimals for share quantities if fractional
}

struct Round {
    bytes32 id;
    string seriesType;
    uint256 raiseCap;
    uint256 minTicket;
    uint256 maxTicket;
    RoundType roundType;
    uint256 startTime;
    uint256 endTime;
    bytes32 templateId;
    address[] certPrinter;
    address paymentToken;
    uint256 pricePerUnit;
    uint256 valuation;
    uint256 raised;
    // Normalized round price and primary security sold to new money
    uint256 roundPricePerShare; // normalized to priceDecimals
    uint8 roundPriceDecimals;
    SecurityClass primarySecurityClass;
    SecuritySeries primarySecuritySeries;
    address authorityOfficer;
    string[] roundPartyValues;
    bytes escrowedSignature;
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
        

        /// @notice Per-round capitalization snapshot
        mapping(bytes32 => CapTableSnapshot) roundSnapshots;

        /// @notice Per-round rounding policy
        mapping(bytes32 => RoundingPolicy) roundingPolicies;

        /// @notice Per-round mapping from PMVC (valuation cap) to SAFE sub-series label
        mapping(bytes32 => mapping(uint256 => string)) pmvcToSubseriesLabel;
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

    // -------- Round snapshot --------
    function setRoundSnapshot(bytes32 roundId, CapTableSnapshot memory snapshot) internal {
        roundManagerStorage().roundSnapshots[roundId] = snapshot;
    }

    function getRoundSnapshot(bytes32 roundId) internal view returns (CapTableSnapshot memory) {
        return roundManagerStorage().roundSnapshots[roundId];
    }

    // -------- Rounding policy --------
    function setRoundingPolicy(bytes32 roundId, RoundingPolicy memory policy) internal {
        roundManagerStorage().roundingPolicies[roundId] = policy;
    }

    function getRoundingPolicy(bytes32 roundId) internal view returns (RoundingPolicy memory) {
        return roundManagerStorage().roundingPolicies[roundId];
    }

    // -------- SAFE sub-series labels --------
    function setPMVCSubseriesLabel(bytes32 roundId, uint256 pmvc, string memory label) internal {
        roundManagerStorage().pmvcToSubseriesLabel[roundId][pmvc] = label;
    }

    function getPMVCSubseriesLabel(bytes32 roundId, uint256 pmvc) internal view returns (string memory) {
        return roundManagerStorage().pmvcToSubseriesLabel[roundId][pmvc];
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

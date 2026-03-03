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

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./ICertificateExtension.sol";
import "../../CyberCorpConstants.sol";
import "../../libs/auth.sol";

/// @notice Classification of capital stock
enum ShareClass {
    Common,
    Preferred
}

/// @notice Liquidation preference payout structure
enum LiquidationPreferenceType {
    NonParticipating,       // holder receives the greater of preference or as-converted amount
    Participating,          // holder receives preference + pro rata share of remainder
    CappedParticipating     // participating, but capped at a multiple of original issue price
}

/// @notice Anti-dilution protection mechanism
enum AntiDilutionType {
    None,
    BroadBasedWeightedAverage,
    NarrowBasedWeightedAverage,
    FullRatchet
}

/// @notice Dividend accrual behavior
enum DividendType {
    None,
    NonCumulative,      // dividends declared at board discretion, unpaid amounts do not accrue
    Cumulative           // dividends accrue whether or not declared
}

/// @notice Transfer restriction regime applicable to the shares
enum TransferRestrictionType {
    None,
    BoardConsentRequired,       // Section 8.9(a) of Bylaws — no transfer without board consent
    ROFRAndCoSale,              // subject to ROFR/Co-Sale agreement
    Rule144Eligible,            // restriction relaxed per Rule 144
    CustomRestriction           // custom restriction defined by agreement or board resolution
}

/// @notice Core share designation data for a cyberCERT representing equity
struct ShareData {
    // === Identity & Classification ===
    ShareClass shareClass;              // Common or Preferred
    string seriesName;                  // e.g. "Series Seed", "" for Common
    uint256 parValue;                   // par value per share (18 decimals, e.g. 10000000000000 = $0.00001)

    // === Economic Rights ===
    uint256 originalIssuePrice;         // price per share at issuance (18 decimals)
    uint256 liquidationPreferenceMultiple; // multiple of OIP for preference (18 decimals, 1e18 = 1x)
    LiquidationPreferenceType liquidationPreferenceType;
    uint256 participationCap;           // if CappedParticipating, max multiple of OIP (18 decimals); 0 otherwise
    DividendType dividendType;
    uint256 dividendRateOrPriority;     // annual rate (18 decimals, e.g. 8% = 8e16) or 0 for pari passu with common

    // === Conversion ===
    bool isConvertible;                 // whether shares are convertible to Common
    uint256 conversionPrice;            // conversion price (18 decimals); conversion ratio = OIP / conversionPrice
    AntiDilutionType antiDilutionType;

    // === Voting ===
    uint256 votesPerShare;              // votes per share (18 decimals, 1e18 = 1 vote per share); 0 = non-voting
    bool hasClassVotingRights;          // whether holder votes as a separate class on certain matters
    uint8 designatedBoardSeats;         // number of board seats this class/series is entitled to elect

    // === Transfer Restrictions ===
    TransferRestrictionType transferRestrictionType;

    // === Redemption ===
    bool isRedeemable;                  // whether shares are subject to optional or mandatory redemption
    uint256 redemptionPrice;            // redemption price per share (18 decimals); 0 if not redeemable

    // === Protective Provisions ===
    bool hasProtectiveProvisions;       // whether holders have protective provision veto rights (COI §3.3)
    uint256 protectiveProvisionThreshold; // percentage of outstanding required to waive (4 decimals, e.g. 5010 = 50.10%)

    // === Authorization ===
    uint256 authorizedShares;           // total authorized shares of this class/series
}

contract ShareExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = keccak256("SHARE");
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;
    uint256 public constant PRICE_PRECISION = 10 ** 18;

    // offset to leave for future upgrades
    uint256[30] private __gap;

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodeExtensionData(bytes memory data) external pure returns (ShareData memory) {
        return abi.decode(data, (ShareData));
    }

    function encodeExtensionData(ShareData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(bytes memory data) external pure override returns (string memory) {
        ShareData memory d = abi.decode(data, (ShareData));

        // Build JSON in segments to avoid stack-too-deep
        string memory part1 = _buildIdentityAndEconomics(d);
        string memory part2 = _buildConversionAndVoting(d);
        string memory part3 = _buildRestrictionsAndRedemption(d);
        string memory part4 = _buildProtectiveAndAuth(d);

        return string(abi.encodePacked(
            ', "shareDetails": {',
            part1, part2, part3, part4,
            "}"
        ));
    }

    // ──────────────────────────────────────────────────────────────
    //  Internal JSON-building helpers (split to avoid stack-too-deep)
    // ──────────────────────────────────────────────────────────────

    function _buildIdentityAndEconomics(ShareData memory d) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"shareClass": "', _shareClassToString(d.shareClass),
            '", "seriesName": "', d.seriesName,
            '", "parValue": "', _uint256ToString(d.parValue),
            '", "originalIssuePrice": "', _uint256ToString(d.originalIssuePrice),
            '", "liquidationPreferenceMultiple": "', _uint256ToString(d.liquidationPreferenceMultiple),
            '", "liquidationPreferenceType": "', _liquidationPrefTypeToString(d.liquidationPreferenceType),
            '", "participationCap": "', _uint256ToString(d.participationCap),
            '", '
        ));
    }

    function _buildConversionAndVoting(ShareData memory d) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"dividendType": "', _dividendTypeToString(d.dividendType),
            '", "dividendRateOrPriority": "', _uint256ToString(d.dividendRateOrPriority),
            '", "isConvertible": "', _boolToString(d.isConvertible),
            '", "conversionPrice": "', _uint256ToString(d.conversionPrice),
            '", "antiDilutionType": "', _antiDilutionTypeToString(d.antiDilutionType),
            '", "votesPerShare": "', _uint256ToString(d.votesPerShare),
            '", "hasClassVotingRights": "', _boolToString(d.hasClassVotingRights),
            '", "designatedBoardSeats": "', _uint256ToString(uint256(d.designatedBoardSeats)),
            '", '
        ));
    }

    function _buildRestrictionsAndRedemption(ShareData memory d) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"transferRestrictionType": "', _transferRestrictionTypeToString(d.transferRestrictionType),
            '", "isRedeemable": "', _boolToString(d.isRedeemable),
            '", "redemptionPrice": "', _uint256ToString(d.redemptionPrice),
            '", '
        ));
    }

    function _buildProtectiveAndAuth(ShareData memory d) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"hasProtectiveProvisions": "', _boolToString(d.hasProtectiveProvisions),
            '", "protectiveProvisionThreshold": "', _uint256ToString(d.protectiveProvisionThreshold),
            '", "authorizedShares": "', _uint256ToString(d.authorizedShares),
            '"'
        ));
    }

    // ──────────────────────────────────────────────────────────────
    //  Enum-to-string helpers
    // ──────────────────────────────────────────────────────────────

    function _shareClassToString(ShareClass c) internal pure returns (string memory) {
        if (c == ShareClass.Common) return "Common";
        if (c == ShareClass.Preferred) return "Preferred";
        return "Unknown";
    }

    function _liquidationPrefTypeToString(LiquidationPreferenceType t) internal pure returns (string memory) {
        if (t == LiquidationPreferenceType.NonParticipating) return "NonParticipating";
        if (t == LiquidationPreferenceType.Participating) return "Participating";
        if (t == LiquidationPreferenceType.CappedParticipating) return "CappedParticipating";
        return "Unknown";
    }

    function _antiDilutionTypeToString(AntiDilutionType t) internal pure returns (string memory) {
        if (t == AntiDilutionType.None) return "None";
        if (t == AntiDilutionType.BroadBasedWeightedAverage) return "BroadBasedWeightedAverage";
        if (t == AntiDilutionType.NarrowBasedWeightedAverage) return "NarrowBasedWeightedAverage";
        if (t == AntiDilutionType.FullRatchet) return "FullRatchet";
        return "Unknown";
    }

    function _dividendTypeToString(DividendType t) internal pure returns (string memory) {
        if (t == DividendType.None) return "None";
        if (t == DividendType.NonCumulative) return "NonCumulative";
        if (t == DividendType.Cumulative) return "Cumulative";
        return "Unknown";
    }

    function _transferRestrictionTypeToString(TransferRestrictionType t) internal pure returns (string memory) {
        if (t == TransferRestrictionType.None) return "None";
        if (t == TransferRestrictionType.BoardConsentRequired) return "BoardConsentRequired";
        if (t == TransferRestrictionType.ROFRAndCoSale) return "ROFRAndCoSale";
        if (t == TransferRestrictionType.Rule144Eligible) return "Rule144Eligible";
        if (t == TransferRestrictionType.CustomRestriction) return "CustomRestriction";
        return "Unknown";
    }

    function _boolToString(bool b) internal pure returns (string memory) {
        return b ? "true" : "false";
    }

    // ──────────────────────────────────────────────────────────────
    //  uint256 → string
    // ──────────────────────────────────────────────────────────────

    function _uint256ToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // ──────────────────────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────────────────────

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}

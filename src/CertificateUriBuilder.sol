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

pragma solidity ^0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./CyberCorpConstants.sol";
import "./interfaces/ICyberAgreementRegistry.sol";
import "./interfaces/ICertificateImageBuilder.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/IIssuanceManager.sol";
import {
    ILedgerEntryToken,
    RestrictionType,
    RestrictiveLegend
} from "./interfaces/ILedgerEntryToken.sol";
import {
    ICertificateExtension,
    ICertificateExtensionV3
} from "./storage/extensions/ICertificateExtension.sol";
import "./libs/auth.sol";

interface ICertificateUnitsReserved {
    function unitsReserved(uint256 tokenId) external view returns (uint256);
}

contract CertificateUriBuilder is UUPSUpgradeable, BorgAuthACL {

    /// @notice Address of the external image builder contract
    address public imageBuilder;

    /// @notice Emitted when the image builder is updated
    event ImageBuilderUpdated(address indexed oldBuilder, address indexed newBuilder);

    // Upgrade notes: Reduced gap to account for new variables (50 - 2 = 48)
    uint256[48] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    /// @notice Sets the image builder contract address
    /// @param _imageBuilder The address of the CertificateImageBuilderContract
    function setImageBuilder(address _imageBuilder) external onlyOwner {
        require(_imageBuilder != address(0), "Invalid image builder address");
        address oldBuilder = imageBuilder;
        imageBuilder = _imageBuilder;
        emit ImageBuilderUpdated(oldBuilder, _imageBuilder);
    }

    // Helper function to convert SecurityClass enum to string
    function securityClassToString(SecurityClass _class) public pure returns (string memory) {
        if (_class == SecurityClass.SAFE) return "SAFE";
        if (_class == SecurityClass.SAFT) return "SAFT";
        if (_class == SecurityClass.SAFTE) return "SAFTE";
        if (_class == SecurityClass.TokenPurchaseAgreement) return "TokenPurchaseAgreement";
        if (_class == SecurityClass.TokenWarrant) return "TokenWarrant";
        if (_class == SecurityClass.ConvertibleNote) return "ConvertibleNote";
        if (_class == SecurityClass.CommonStock) return "CommonStock";
        if (_class == SecurityClass.StockOption) return "StockOption";
        if (_class == SecurityClass.PreferredStock) return "PreferredStock";
        if (_class == SecurityClass.RestrictedStockPurchaseAgreement) return "RestrictedStockPurchaseAgreement";
        if (_class == SecurityClass.RestrictedStockUnit) return "RestrictedStockUnit";
        if (_class == SecurityClass.RestrictedTokenPurchaseAgreement) return "RestrictedTokenPurchaseAgreement";
        if (_class == SecurityClass.RestrictedTokenUnit) return "RestrictedTokenUnit";
        return "Unknown";
    }

    function securityClassToUnit(SecurityClass _class) public pure returns (string memory) {
        if (_class == SecurityClass.SAFE) return "Dollars";
        if (_class == SecurityClass.SAFT) return "Dollars";
        if (_class == SecurityClass.SAFTE) return "Dollars";
        if (_class == SecurityClass.TokenPurchaseAgreement) return "Tokens";
        if (_class == SecurityClass.TokenWarrant) return "Tokens";
        if (_class == SecurityClass.ConvertibleNote) return "Notes";
        if (_class == SecurityClass.CommonStock) return "Shares";
        if (_class == SecurityClass.StockOption) return "Shares";
        if (_class == SecurityClass.PreferredStock) return "Shares";
        if (_class == SecurityClass.RestrictedStockPurchaseAgreement) return "Units";
        if (_class == SecurityClass.RestrictedStockUnit) return "Units";
        if (_class == SecurityClass.RestrictedTokenPurchaseAgreement) return "Units";
        if (_class == SecurityClass.RestrictedTokenUnit) return "Units";
        return "Unknown";
    }

    // Helper function to convert SecuritySeries enum to string
    function securitySeriesToString(SecuritySeries _series) public pure returns (string memory) {
        if (_series == SecuritySeries.SeriesPreSeed) return "SeriesPreSeed";
        if (_series == SecuritySeries.SeriesSeed) return "SeriesSeed";
        if (_series == SecuritySeries.SeriesA) return "SeriesA";
        if (_series == SecuritySeries.SeriesB) return "SeriesB";
        if (_series == SecuritySeries.SeriesC) return "SeriesC";
        if (_series == SecuritySeries.SeriesD) return "SeriesD";
        if (_series == SecuritySeries.SeriesE) return "SeriesE";
        if (_series == SecuritySeries.SeriesF) return "SeriesF";
        if (_series == SecuritySeries.NA) return "NA";
        if (_series == SecuritySeries.ACE) return "ACE";
        return "Unknown";
    }

    // Helper function to convert string array to JSON array string with numbered legends
    function arrayToJsonString(string[] memory arr) public pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < arr.length; i++) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(json, '{"id": ', uint256ToString(i + 1), ', "legend": "', arr[i], '"}');
        }
        return string.concat(json, "]");
    }

    function legacyLegendsToRestrictiveLegends(
        string[] memory arr
    ) public pure returns (RestrictiveLegend[] memory legends) {
        legends = new RestrictiveLegend[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            legends[i] = RestrictiveLegend({
                restrictionType: RestrictionType.Custom,
                title: "",
                text: arr[i],
                jurisdiction: "",
                referenceId: bytes32(0),
                effectiveTimestamp: 0,
                expirationTimestamp: 0,
                active: true,
                data: ""
            });
        }
    }

    function restrictiveLegendsToJson(RestrictiveLegend[] memory arr) public pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < arr.length; i++) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(json, restrictiveLegendToJson(i + 1, arr[i]));
        }
        return string.concat(json, "]");
    }

    function restrictiveLegendToJson(
        uint256 id,
        RestrictiveLegend memory legend
    ) public pure returns (string memory) {
        string memory part1 = string.concat(
            '{"id": ', uint256ToString(id),
            ', "restrictionType": "', restrictionTypeToString(legend.restrictionType),
            '", "title": "', legend.title,
            '", "text": "', legend.text,
            '", "jurisdiction": "', legend.jurisdiction,
            '"'
        );
        string memory part2 = string.concat(
            ', "referenceId": "0x', bytes32ToString(legend.referenceId),
            '", "effectiveTimestamp": "', uint256ToString(uint256(legend.effectiveTimestamp)),
            '", "expirationTimestamp": "', uint256ToString(uint256(legend.expirationTimestamp)),
            '", "active": "', boolToString(legend.active),
            '", "data": "', bytesToHexString(legend.data),
            '"}'
        );
        return string.concat(part1, part2);
    }

    function restrictionTypeToString(RestrictionType restrictionType) public pure returns (string memory) {
        if (restrictionType == RestrictionType.Unspecified) return "Unspecified";
        if (restrictionType == RestrictionType.TransferConsentRequired) return "TransferConsentRequired";
        if (restrictionType == RestrictionType.RestrictedSecurityRule144) return "RestrictedSecurityRule144";
        if (restrictionType == RestrictionType.UnregisteredSecurities) return "UnregisteredSecurities";
        if (restrictionType == RestrictionType.RegulationS) return "RegulationS";
        if (restrictionType == RestrictionType.ContentiousHardfork) return "ContentiousHardfork";
        if (restrictionType == RestrictionType.Custom) return "Custom";
        return "Unknown";
    }

    function boolToString(bool value) public pure returns (string memory) {
        return value ? "true" : "false";
    }

    // Helper function to convert address to string
    function addressToString(address _addr) public pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint160(_addr) >> (8 * (19 - i))));
            uint8 hi = uint8(b) >> 4;
            uint8 lo = uint8(b) & 0x0f;
            s[2*i] = bytes1(hi + (hi < 10 ? 48 : 87));
            s[2*i+1] = bytes1(lo + (lo < 10 ? 48 : 87));
        }
        return string(abi.encodePacked("0x", s));
    }

    // Helper function to convert uint256 to string
    function uint256ToString(uint256 _i) public pure returns (string memory) {
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
            k = k-1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    /// @notice Converts 18-decimal value to string with 2 decimal places (cents)
    /// @param value The 18-decimal value (e.g., 100000.50 * 1e18)
    /// @return The formatted string with 2 decimals (e.g., "100000.50")
    function from18DecimalsToString(uint256 value) public pure returns (string memory) {
        // Divide by 1e16 to get value in cents (2 decimal places)
        uint256 valueInCents = value / 1e16;
        uint256 wholePart = valueInCents / 100;
        uint256 centsPart = valueInCents % 100;
        
        string memory wholeStr = uint256ToString(wholePart);
        
        // Format cents with leading zero if needed
        string memory centsStr;
        if (centsPart < 10) {
            centsStr = string(abi.encodePacked("0", uint256ToString(centsPart)));
        } else {
            centsStr = uint256ToString(centsPart);
        }
        
        return string(abi.encodePacked(wholeStr, ".", centsStr));
    }

    function unitsReservedToString(address contractAddress, uint256 tokenId) internal view returns (string memory) {
        if (contractAddress == address(0)) return "0.00";
        return from18DecimalsToString(ICertificateUnitsReserved(contractAddress).unitsReserved(tokenId));
    }

    // Helper function to convert bytes32 to string
    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        bytes memory bytesArray = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(uint8(bytes1(bytes32(_bytes32) >> (8 * (31 - i)))));
            bytesArray[i*2] = bytes1(uint8(b/16 + (b/16 < 10 ? 48 : 87)));
            bytesArray[i*2+1] = bytes1(uint8(b%16 + (b%16 < 10 ? 48 : 87)));
        }
        return string(bytesArray);
    }

    // Helper function to convert bytes to hex string
    function bytesToHexString(bytes memory data) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory hexString = new bytes(2 + data.length * 2);
        hexString[0] = "0";
        hexString[1] = "x";
        
        for(uint i = 0; i < data.length; i++) {
            hexString[2 + i*2] = hexChars[uint8(data[i] >> 4)];
            hexString[2 + i*2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }
        
        return string(hexString);
    }

    /// @notice Removes the first 7 characters from a string (e.g., strips "ipfs://")
    /// @param str The original string
    /// @return The string with first 7 characters removed
    function stripIpfsPrefix(string memory str) public pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length <= 7) {
            return "";
        }
        bytes memory result = new bytes(strBytes.length - 7);
        for (uint i = 7; i < strBytes.length; i++) {
            result[i - 7] = strBytes[i];
        }
        return string(result);
    }

struct CertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmountUSD;
    uint256 issuerUSDValuationAtTimeOfInvestment;
    uint256 unitsRepresented;
    string legalDetails;
    bytes extensionData;
}

    struct Endorsement {
        address endorser;
        uint256 timestamp;
        bytes signatureHash;
        address registry;
        bytes32 agreementId;
        address endorsee;
        string endorseeName;
    }

    struct OwnerDetails {
        string name;
        address ownerAddress;
    }

    /// @notice Fetches the last signed timestamp from the registry for a given agreement
    /// @param registry The registry contract address
    /// @param agreementId The agreement ID
    /// @return timestamp The last signed timestamp, or block.timestamp if unavailable
    function _getAgreementTimestamp(address registry, bytes32 agreementId) internal view returns (uint256 timestamp) {
        if (registry == address(0) || agreementId == bytes32(0)) {
            return block.timestamp;
        }
        
        try ICyberAgreementRegistry(registry).getContractDetails(agreementId) returns (
            bytes32,
            string memory,
            string[] memory,
            string[] memory,
            string[] memory,
            address[] memory,
            string[][] memory,
            uint256[] memory signedAt,
            uint256,
            bool,
            bytes32
        ) {
            // Use the last signature timestamp
            if (signedAt.length > 0) {
                uint256 lastTimestamp = signedAt[signedAt.length - 1];
                if (lastTimestamp > 0) {
                    return lastTimestamp;
                }
            }
        } catch {
            // If the call fails, fall through to return block.timestamp
        }
        
        return block.timestamp;
    }

    function buildAttributes(
        OwnerDetails memory owner,
        CertificateDetails memory details,
        string memory cyberCORPName,
        string memory cyberCORPType,
        string memory cyberCORPJurisdiction,
        string memory cyberCORPContactDetails,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        string memory certificateUri
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            _buildAttributesPart1(owner, details, cyberCORPName, cyberCORPType),
            _buildAttributesPart2(cyberCORPJurisdiction, cyberCORPContactDetails, securityType, securitySeries, certificateUri)
        ));
    }

    function _buildAttributesPart1(
        OwnerDetails memory owner,
        CertificateDetails memory details,
        string memory cyberCORPName,
        string memory cyberCORPType
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type": "CurrentOwner", "value": "', addressToString(owner.ownerAddress),
            '"}, {"trait_type": "CurrentOwnerName", "value": "', owner.name,
            '"}, {"trait_type": "investmentAmount", "value": "', from18DecimalsToString(details.investmentAmountUSD),
            '"}, {"trait_type": "unitsRepresented", "value": "', from18DecimalsToString(details.unitsRepresented),
            '"}, {"trait_type": "issuerUSDValuationAtTimeOfInvestment", "value": "', from18DecimalsToString(details.issuerUSDValuationAtTimeOfInvestment),
            '"}, {"trait_type": "cyberCORPName", "value": "', cyberCORPName,
            '"}, {"trait_type": "cyberCORPType", "value": "', cyberCORPType,
            '"}'
        ));
    }

    function _buildAttributesPart2(
        string memory cyberCORPJurisdiction,
        string memory cyberCORPContactDetails,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        string memory certificateUri
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            ', {"trait_type": "cyberCORPJurisdiction", "value": "', cyberCORPJurisdiction,
            '"}, {"trait_type": "cyberCORPContactDetails", "value": "', cyberCORPContactDetails,
            '"}, {"trait_type": "securityType", "value": "', securityClassToString(securityType),
            '"}, {"trait_type": "securitySeries", "value": "', securitySeriesToString(securitySeries),
            '"}, {"trait_type": "certificateUri", "value": "https://ipfs.io/ipfs/', stripIpfsPrefix(certificateUri),
            '"}'
        ));
    }

    function buildEndorsementHistory(
        Endorsement[] memory endorsements,
        address registry,
        bytes32 agreementId
    ) internal view returns (string memory) {
        string memory json = '[';
        for (uint256 i = 0; i < endorsements.length; i++) {
            if (i > 0) json = string.concat(json, ',');
            json = string.concat(json, '{',
                '"endorser": "', addressToString(endorsements[i].endorser),
                '", "timestamp": "', uint256ToString(endorsements[i].timestamp),
                '", "registry": "', addressToString(endorsements[i].registry),
                '", "agreementId": "', bytes32ToString(endorsements[i].agreementId),
                '", "investorName": "', endorsements[i].endorseeName,
                '", "investorAddress": "', addressToString(endorsements[i].endorsee),
                '"');

            // Add purchaseAgreementDetails for the first endorsement only
            if (i == 0 && registry != address(0) && agreementId != bytes32(0)) {
                json = string.concat(json, ', "purchaseAgreementDetails": {');
                
                // Get agreement details from registry
                (
                    ,  // bytes32 templateId
                    ,  // string memory legalContractUri
                    string[] memory globalFields,  // string[] memory globalFields
                    string[] memory partyFields,
                    string[] memory globalValues,  // string[] memory globalValues
                    ,  // address[] memory parties
                    string[][] memory partyValues,  // string[][] memory partyValues
                    ,  // uint256[] memory signedAt
                    ,  // uint256 numSignatures
                    ,
                    // bool isComplete
                ) = ICyberAgreementRegistry(registry).getContractDetails(agreementId);

                // Add global fields
                for (uint256 j = 0; j < globalFields.length; j++) {
                    if (j > 0) json = string.concat(json, ',');
                    json = string.concat(json, '"', globalFields[j], '": "', 
                        j < globalValues.length ? globalValues[j] : "", '"');
                }

                // Add company details if party values exist at index 0
                if (partyValues.length > 0 && partyValues[0].length > 0) {
                    json = string.concat(json, ', "companyDetails": {');
                    for (uint256 j = 0; j < partyFields.length && j < partyValues[0].length; j++) {
                        if (j > 0) json = string.concat(json, ',');
                        json = string.concat(json, '"', partyFields[j], '": "', partyValues[0][j], '"');
                    }
                    json = string.concat(json, '}');
                }

                // Add investor details if party values exist at index 1
                if (partyValues.length > 1 && partyValues[1].length > 0) {
                    json = string.concat(json, ', "investorDetails": {');
                    for (uint256 j = 0; j < partyFields.length && j < partyValues[1].length; j++) {
                        if (j > 0) json = string.concat(json, ',');
                        json = string.concat(json, '"', partyFields[j], '": "', partyValues[1][j], '"');
                    }
                    json = string.concat(json, '}');
                }

                // Add the digital signature from the first endorsement
                if (endorsements[0].signatureHash.length > 0) {
                    json = string.concat(json, 
                        ', "digitalSignature": "', 
                        bytesToHexString(endorsements[0].signatureHash),
                        '"'
                    );
                }
                json = string.concat(json, '}');
            }

            json = string.concat(json, '}');
        }
        return string.concat(json, ']');
    }

    function buildCertificateUri(
        string memory cyberCORPName,
        string memory cyberCORPType,
        string memory cyberCORPJurisdiction,
        string memory cyberCORPContactDetails,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        string memory certificateUri,
        string[] memory certLegend,
        CertificateDetails memory details,
        Endorsement[] memory endorsements,
        OwnerDetails memory owner,
        address registry,
        bytes32 agreementId,
        uint256 tokenId,
        address contractAddress,
        address extension
    ) public view returns (string memory) {
        return buildCertificateUri(
            cyberCORPName,
            cyberCORPType,
            cyberCORPJurisdiction,
            cyberCORPContactDetails,
            securityType,
            securitySeries,
            certificateUri,
            legacyLegendsToRestrictiveLegends(certLegend),
            details,
            endorsements,
            owner,
            registry,
            agreementId,
            tokenId,
            contractAddress,
            extension
        );
    }

    function buildCertificateUri(
        string memory cyberCORPName,
        string memory cyberCORPType,
        string memory cyberCORPJurisdiction,
        string memory cyberCORPContactDetails,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        string memory certificateUri,
        RestrictiveLegend[] memory certLegend,
        CertificateDetails memory details,
        Endorsement[] memory endorsements,
        OwnerDetails memory owner,
        address registry,
        bytes32 agreementId,
        uint256 tokenId,
        address contractAddress,
        address extension
    ) public view returns (string memory) {
        // Start building the JSON string with ERC-721 metadata standard format
        // Build on-chain SVG image using the image builder
        
        string memory json;
        {
            uint256 certTimestamp = _getAgreementTimestamp(registry, agreementId);
            CertificateSVGParams memory svgParams = CertificateSVGParams({
                corpName: cyberCORPName,
                securityType: securityType,
                securitySeries: securitySeries,
                officerName: details.signingOfficerName,
                officerTitle: details.signingOfficerTitle,
                units: details.unitsRepresented,
                valuation: details.issuerUSDValuationAtTimeOfInvestment,
                jurisdiction: cyberCORPJurisdiction,
                ownerName: owner.name,
                tokenId: tokenId,
                certificateUri: certificateUri
            });
            string memory svg = ICertificateImageBuilder(imageBuilder).buildCertificateSVG(svgParams, certTimestamp);
            string memory imageDataUri = string(
                abi.encodePacked('data:image/svg+xml;base64,', Base64.encode(bytes(svg)))
            );
            json = string(abi.encodePacked(
                '{"title": "MetaLeX Tokenized Certificate",',
                '"type": "', securityClassToString(securityType),
                '", "image": "', imageDataUri, '",',
                '"attributes": [', buildAttributes(owner, details, cyberCORPName, cyberCORPType, cyberCORPJurisdiction, cyberCORPContactDetails, securityType, securitySeries, certificateUri),
                '],'
            ));
        }

        // Add all existing properties at root level
        json = string.concat(json, '"cyberCORPName": "', cyberCORPName, '"');
        json = string.concat(json, ', "cyberCORPType": "', cyberCORPType, '"');
        json = string.concat(json, ', "cyberCORPJurisdiction": "', cyberCORPJurisdiction, '"');
        json = string.concat(json, ', "cyberCORPContactDetails": "', cyberCORPContactDetails, '"');
        json = string.concat(json, ', "securityType": "', securityClassToString(securityType), '"');
        json = string.concat(json, ', "securitySeries": "', securitySeriesToString(securitySeries), '"');
        json = string.concat(json, ', "certificateUri": "', certificateUri, '"');

        // Add certificate details
        json = string.concat(json, ', "signingOfficerName": "', details.signingOfficerName, '"');
        json = string.concat(json, ', "signingOfficerTitle": "', details.signingOfficerTitle, '"');
        json = string.concat(json, ', "investmentAmountUSD": "', from18DecimalsToString(details.investmentAmountUSD), '"');
        json = string.concat(json, ', "issuerUSDValuationAtTimeOfInvestment": "', from18DecimalsToString(details.issuerUSDValuationAtTimeOfInvestment), '"');
        json = string.concat(json, ', "unitsRepresented": "', from18DecimalsToString(details.unitsRepresented), '"');
        json = string.concat(json, ', "unitsReserved": "', unitsReservedToString(contractAddress, tokenId), '"');
        json = string.concat(json, ', "legalDetails": "', details.legalDetails, '"');

        json = _appendCyberCorpExtensionData(json, contractAddress);

        // A V3 extension resolves the cert, series and class scopes itself and renders one complete
        // section. Only when it does not, fall back to rendering the scopes one at a time.
        bool resolved;
        (json, resolved) = _appendResolvedExtensionData(json, contractAddress, tokenId, extension);
        // not resolvable means it is legacy `extensionData`
        if (!resolved) {
            //add extensionData
            if (extension != address(0) && details.extensionData.length > 0) {
                json = string.concat(json, ICertificateExtension(extension).getExtensionURI(details.extensionData));
            }
        }

        // Add endorsement history
        json = string.concat(json, ', "endorsementHistory": ', buildEndorsementHistory(endorsements, registry, agreementId));

        // Add current owner details
        json = string.concat(json, 
            ', "currentOwner": {',
            '"name": "', owner.name,
            '", "ownerAddress": "', addressToString(owner.ownerAddress),
            '"}'
        );

        // Add restrictive legends at the end
        json = string.concat(json, ', "restrictiveLegends": ', restrictiveLegendsToJson(certLegend));

        // Close the main JSON object
        json = string.concat(json, '}');
        json = Base64.encode(bytes(string(json)));
        json = string(abi.encodePacked('data:application/json;base64,', json));
        return json;
    }

    /// @dev Adds issuer-level extension metadata when the printer and IssuanceManager expose it.
    /// Guards preserve URI availability for legacy printer or IssuanceManager implementations.
    function _appendCyberCorpExtensionData(
        string memory json,
        address certificate
    ) private view returns (string memory) {
        try ILedgerEntryToken(certificate).issuanceManager() returns (
            address issuanceManager
        ) {
            try IIssuanceManager(issuanceManager).CORP() returns (address corp) {
                if (corp == address(0)) return json;

                try ICyberCorp(corp).getExtensionURI() returns (
                    string memory extensionJson
                ) {
                    return bytes(extensionJson).length == 0
                        ? json
                        : string.concat(json, extensionJson);
                } catch {
                    return json;
                }
            } catch {
                return json;
            }
        } catch {
            return json;
        }
    }

    /// @dev Adds the resolved certificate when the extension implements ICertificateExtensionV3. The
    /// cert payload alone is not the whole picture once a section lives at the series or class scope,
    /// so a V3 extension merges every scope and returns one section. All calls are guarded, so a V1
    /// or V2 extension reports `false` and the caller keeps its existing per-scope output.
    function _appendResolvedExtensionData(
        string memory json,
        address certificate,
        uint256 tokenId,
        address extension
    ) private view returns (string memory, bool) {
        if (extension == address(0)) return (json, false);

        try ICertificateExtensionV3(extension).supportsResolvedExtensionData() returns (bool supported) {
            if (!supported) return (json, false);
        } catch {
            return (json, false);
        }

        try ICertificateExtensionV3(extension).getResolvedExtensionURI(certificate, tokenId) returns (
            string memory resolvedJson
        ) {
            return (bytes(resolvedJson).length == 0 ? json : string.concat(json, resolvedJson), true);
        } catch {
            return (json, false);
        }
    }

    function buildCertificateUriNotEncoded(
        string memory cyberCORPName,
        string memory cyberCORPType,
        string memory cyberCORPJurisdiction,
        string memory cyberCORPContactDetails,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        string memory certificateUri,
        string[] memory certLegend,
        CertificateDetails memory details,
        Endorsement[] memory endorsements,
        OwnerDetails memory owner,
        address registry,
        bytes32 agreementId,
        uint256 tokenId,
        address contractAddress,
        address extension
    ) public view returns (string memory) {
        return buildCertificateUriNotEncoded(
            cyberCORPName,
            cyberCORPType,
            cyberCORPJurisdiction,
            cyberCORPContactDetails,
            securityType,
            securitySeries,
            certificateUri,
            legacyLegendsToRestrictiveLegends(certLegend),
            details,
            endorsements,
            owner,
            registry,
            agreementId,
            tokenId,
            contractAddress,
            extension
        );
    }

    function buildCertificateUriNotEncoded(
        string memory cyberCORPName,
        string memory cyberCORPType,
        string memory cyberCORPJurisdiction,
        string memory cyberCORPContactDetails,
        SecurityClass securityType,
        SecuritySeries securitySeries,
        string memory certificateUri,
        RestrictiveLegend[] memory certLegend,
        CertificateDetails memory details,
        Endorsement[] memory endorsements,
        OwnerDetails memory owner,
        address registry,
        bytes32 agreementId,
        uint256 tokenId,
        address contractAddress,
        address extension
    ) public view returns (string memory) {
        // Start building the JSON string with ERC-721 metadata standard format
        // Build on-chain SVG image using the image builder

        string memory json;
        {
            uint256 certTimestamp = _getAgreementTimestamp(registry, agreementId);
            CertificateSVGParams memory svgParams = CertificateSVGParams({
                corpName: cyberCORPName,
                securityType: securityType,
                securitySeries: securitySeries,
                officerName: details.signingOfficerName,
                officerTitle: details.signingOfficerTitle,
                units: details.unitsRepresented,
                valuation: details.issuerUSDValuationAtTimeOfInvestment,
                jurisdiction: cyberCORPJurisdiction,
                ownerName: owner.name,
                tokenId: tokenId,
                certificateUri: certificateUri
            });
            string memory svg = ICertificateImageBuilder(imageBuilder).buildCertificateSVG(svgParams, certTimestamp);
            string memory imageDataUri = string(
                abi.encodePacked('data:image/svg+xml;base64,', Base64.encode(bytes(svg)))
            );
            json = string(abi.encodePacked(
                '{"title": "MetaLeX Tokenized Certificate",',
                '"type": "', securityClassToString(securityType),
                '", "image": "', imageDataUri, '",',
                '"attributes": [', buildAttributes(owner, details, cyberCORPName, cyberCORPType, cyberCORPJurisdiction, cyberCORPContactDetails, securityType, securitySeries, certificateUri),
                '],'
            ));
        }

        // Add all existing properties at root level
        json = string.concat(json, '"cyberCORPName": "', cyberCORPName, '"');
        json = string.concat(json, ', "cyberCORPType": "', cyberCORPType, '"');
        json = string.concat(json, ', "cyberCORPJurisdiction": "', cyberCORPJurisdiction, '"');
        json = string.concat(json, ', "cyberCORPContactDetails": "', cyberCORPContactDetails, '"');
        json = string.concat(json, ', "securityType": "', securityClassToString(securityType), '"');
        json = string.concat(json, ', "securitySeries": "', securitySeriesToString(securitySeries), '"');
        json = string.concat(json, ', "certificateUri": "', certificateUri, '"');

        // Add certificate details
        json = string.concat(json, ', "signingOfficerName": "', details.signingOfficerName, '"');
        json = string.concat(json, ', "signingOfficerTitle": "', details.signingOfficerTitle, '"');
        json = string.concat(json, ', "investmentAmountUSD": "', from18DecimalsToString(details.investmentAmountUSD), '"');
        json = string.concat(json, ', "issuerUSDValuationAtTimeOfInvestment": "', from18DecimalsToString(details.issuerUSDValuationAtTimeOfInvestment), '"');
        json = string.concat(json, ', "unitsRepresented": "', from18DecimalsToString(details.unitsRepresented), '"');
        json = string.concat(json, ', "unitsReserved": "', unitsReservedToString(contractAddress, tokenId), '"');
        json = string.concat(json, ', "legalDetails": "', details.legalDetails, '"');

        json = _appendCyberCorpExtensionData(json, contractAddress);

        // A V3 extension resolves the cert, series and class scopes itself and renders one complete
        // section. Only when it does not, fall back to rendering the scopes one at a time.
        bool resolved;
        (json, resolved) = _appendResolvedExtensionData(json, contractAddress, tokenId, extension);
        if (!resolved) {
            // not resolvable means it is legacy `extensionData`
            if (extension != address(0) && details.extensionData.length > 0) {
                json = string.concat(json, ICertificateExtension(extension).getExtensionURI(details.extensionData));
            }
        }

        // Add endorsement history
        json = string.concat(json, ', "endorsementHistory": ', buildEndorsementHistory(endorsements, registry, agreementId));

        // Add current owner details
        json = string.concat(json, 
            ', "currentOwner": {',
            '"name": "', owner.name,
            '", "ownerAddress": "', addressToString(owner.ownerAddress),
            '"}'
        );

        // Add restrictive legends at the end
        json = string.concat(json, ', "restrictiveLegends": ', restrictiveLegendsToJson(certLegend));

        // Close the main JSON object
        json = string.concat(json, '}');
        //json = Base64.encode(bytes(string(json)));
        //json = string(abi.encodePacked('data:application/json;base64,', json));
        return json;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}


/// [MIT License]
/// @title Base64
/// @notice Provides a function for encoding some bytes in base64
/// @author Brecht Devos <brecht@loopring.org>
library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encodes some bytes to the base64 representation
    function encode(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((len + 2) / 3);

        // Add some extra buffer at the end
        bytes memory result = new bytes(encodedLen + 32);

        bytes memory table = TABLE;

        assembly ("memory-safe") {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)

            for {
                let i := 0
            } lt(i, len) {

            } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)

                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                out := shl(224, out)

                mstore(resultPtr, out)

                resultPtr := add(resultPtr, 4)
            }

            switch mod(len, 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }

            mstore(result, encodedLen)
        }

        return string(result);
    }
}

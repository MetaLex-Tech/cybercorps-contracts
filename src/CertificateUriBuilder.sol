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

import "./CyberCorpConstants.sol";
import "./interfaces/ICyberAgreementRegistry.sol";

contract CertificateUriBuilder {
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

struct CertificateDetails {
    string signingOfficerName;
    string signingOfficerTitle;
    uint256 investmentAmount;
    uint256 issuerUSDValuationAtTimeofInvestment;
    uint256 unitsRepresented;
    string legalDetails;
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
        address contractAddress
    ) public view returns (string memory) {
        // Start building the JSON string with ERC-721 metadata standard format
        string memory json = string(abi.encodePacked(
            '{"title": "MetaLeX Tokenized Certificate",',
            '"type": "', securityClassToString(securityType),
            '", "image": "", "properties": {'
        ));

        // Add all existing properties under the properties object
        json = string.concat(json,
            '"cyberCORPName": "', cyberCORPName,
            '", "cyberCORPType": "', cyberCORPType,
            '", "cyberCORPJurisdiction": "', cyberCORPJurisdiction,
            '", "cyberCORPContactDetails": "', cyberCORPContactDetails,
            '", "securityType": "', securityClassToString(securityType),
            '", "securitySeries": "', securitySeriesToString(securitySeries),
            '", "certificateUri": "', certificateUri,
            '"'
        );

        // Add certificate details
        json = string.concat(json, 
            ', "signingOfficerName": "', details.signingOfficerName,
            '", "signingOfficerTitle": "', details.signingOfficerTitle,
            '", "investmentAmount": "', uint256ToString(details.investmentAmount),
            '", "issuerUSDValuationAtTimeofInvestment": "', uint256ToString(details.issuerUSDValuationAtTimeofInvestment),
            '", "unitsRepresented": "', uint256ToString(details.unitsRepresented),
            '", "legalDetails": "', details.legalDetails,
            '"'
        );

        // Add endorsement history
        json = string.concat(json, ', "endorsementHistory": [');
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
        json = string.concat(json, ']');

        // Add current owner details
        json = string.concat(json, 
            ', "currentOwner": {',
            '"name": "', owner.name,
            '", "ownerAddress": "', addressToString(owner.ownerAddress),
            '"}'
        );

        // Add restrictive legends at the end
        json = string.concat(json, ', "restrictiveLegends": ', arrayToJsonString(certLegend));

        // Close both the properties object and the main JSON object
        json = string.concat(json, '}}');

        return json;
    }
} 
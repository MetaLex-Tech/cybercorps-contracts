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
import "./CyberCorpConstants.sol";
import "./interfaces/ICyberAgreementRegistry.sol";
import "./storage/extensions/ICertificateExtension.sol";
import "./libs/auth.sol";

contract CertificateUriBuilder is UUPSUpgradeable, BorgAuthACL {

    // Upgrade notes: Reduced gap to account for new variables (50 - 1 = 49)
    uint256[49] private __gap;

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
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

    function buildAttributes(
        OwnerDetails memory owner,
        CertificateDetails memory details
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type": "CurrentOwner", "value": "', addressToString(owner.ownerAddress),
            '"}, {"trait_type": "investmentAmount", "value": "', uint256ToString(details.investmentAmountUSD),
            '"}, {"trait_type": "unitsRepresented", "value": "', uint256ToString(details.unitsRepresented),
            '"}, {"trait_type": "issuerUSDValuationAtTimeOfInvestment", "value": "', uint256ToString(details.issuerUSDValuationAtTimeOfInvestment),
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
        // Start building the JSON string with ERC-721 metadata standard format
        string memory json = string(abi.encodePacked(
            '{"title": "MetaLeX Tokenized Certificate",',
            '"type": "', securityClassToString(securityType),
            '", "image": "', buildCertificateImage(
                cyberCORPName,
                securityClassToString(securityType),
                owner.name,
                uint256ToString(details.investmentAmountUSD),
                uint256ToString(details.issuerUSDValuationAtTimeOfInvestment),
                certificateUri
            ),
            '", "attributes": [', buildAttributes(owner, details),
            '],'
        ));

        // Add all existing properties at root level
        json = string.concat(
            json,
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
            '", "investmentAmountUSD": "', uint256ToString(details.investmentAmountUSD),
            '", "issuerUSDValuationAtTimeOfInvestment": "', uint256ToString(details.issuerUSDValuationAtTimeOfInvestment),
            '", "unitsRepresented": "', uint256ToString(details.unitsRepresented),
            '", "legalDetails": "', details.legalDetails,
            '"'
        );

        //add extensionData
        if (extension != address(0) && details.extensionData.length > 0) {
            json = string.concat(json, ICertificateExtension(extension).getExtensionURI(details.extensionData));
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
        json = string.concat(json, ', "restrictiveLegends": ', arrayToJsonString(certLegend));

        // Close the main JSON object
        json = string.concat(json, '}');
        json = Base64.encode(bytes(string(json)));
        json = string(abi.encodePacked('data:application/json;base64,', json));
        return json;
    }

    function buildCertificateImage(
        string memory companyName,
        string memory securityType,
        string memory investorName,
        string memory investmentAmount,
        string memory companyValuation,
        string memory certificateUri
    ) public pure returns (string memory) {
        string memory svg = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:xhtml="http://www.w3.org/1999/xhtml" version="1.1" width="600" height="500">',
            '<rect width="100%" height="100%" fill="#191a18"/>',
            '<svg x="240" y="280" width="104" height="276" viewBox="0 0 574 276" fill="none" xmlns="http://www.w3.org/2000/svg">',
            '<path opacity=".2" d="M276.107 0C272.902 0 269.767 0.940887 267.092 2.70596L7.35497 174.071C2.76314 177.101 0 182.234 0 187.735V259.581C0 268.622 7.3291 275.951 16.37 275.951H53.9509C57.1472 275.951 60.2736 275.016 62.9443 273.26L286.745 126.113C291.35 123.086 294.122 117.945 294.122 112.435V16.37C294.122 7.32911 286.793 0 277.752 0H276.107Z" fill="#DAFF00"/>',
            '<path opacity=".2" d="M513.301 0.00178097C510.096 0.00178097 506.962 0.942667 504.286 2.70774L244.549 174.073C239.958 177.102 237.194 182.236 237.194 187.737V259.583C237.194 268.624 244.524 275.953 253.564 275.953H291.145C294.342 275.953 297.468 275.018 300.139 273.262L523.94 126.115C528.544 123.087 531.316 117.947 531.316 112.436V16.3718C531.316 7.33089 523.987 0.00178097 514.946 0.00178097H513.301Z" fill="#DAFF00"/>',
            '<path opacity=".2" d="M573.382 156.377C573.382 146.485 562.335 140.604 554.128 146.128L448.154 216.923C444.118 219.64 441.698 224.186 441.698 229.052V261.332C441.698 269.407 448.244 275.953 456.318 275.953H558.762C566.836 275.953 573.382 269.407 573.382 261.332V156.377Z" fill="#DAFF00"/>',
            '</svg>',
            '<text x="200" y="126" font-family="serif" font-size="30" fill="#daff00">', companyName, '</text>',
            '<text x="285" y="156" font-family="serif" font-size="13" fill="#f2f2f2">', securityType, '</text>',
            '<text x="198" y="176" font-family="serif" font-size="13" fill="#f2f2f2">(Simple Agreement for Future Equity)</text>',
            '<defs>',
            '<radialGradient id="grad1" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">',
            '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.07" />',
            '<stop offset="100%" style="stop-color:#191a18; stop-opacity:.07" />',
            '</radialGradient>',
            '</defs>',
            '<rect width="100%" height="100%" fill="url(#grad1)" />',
            '<text x="175" y="480" font-family="serif" font-size="10" fill="#a6a6a6">SEE RESTRICTIVE LEGENDS IN CERTIFICATE DATA</text>',
            '<text x="50" y="220" font-family="serif" font-size="12" fill="#f2f2f2">THIS CERTIFIES THAT</text>',
            '<text x="180" y="220" font-family="serif" font-size="12" fill="#daff00">', investorName, '</text>',
            '<text x="310" y="220" font-family="serif" font-size="12" fill="#f2f2f2">is the owner of the</text>',
            '<text x="413" y="220" font-family="serif" font-size="12" fill="#daff00">', securityType, '</text>',
            '<text x="50" y="240" font-family="serif" font-size="12" fill="#f2f2f2">issued by</text>',
            '<text x="115" y="240" font-family="serif" font-size="12" fill="#daff00">', companyName, '</text>',
            '<text x="260" y="240" font-family="serif" font-size="12" fill="#f2f2f2">(the "Company") in exchange for</text>',
            '<text x="437" y="240" font-family="serif" font-size="12" fill="#daff00">', investmentAmount, '</text>',
            '<text x="50" y="260" font-family="serif" font-size="12" fill="#f2f2f2">at a Company valuation of</text>',
            '<text x="193" y="260" font-family="serif" font-size="12" fill="#daff00">', companyValuation, '</text>',
            '<text x="270" y="260" font-family="serif" font-size="12" fill="#f2f2f2">and represented by a certain Non-Fungible Tokenized</text>',
            '<text x="50" y="280" font-family="serif" font-size="12" fill="#f2f2f2">Certificate as further set forth at:</text>',
            '<text x="50" y="305" font-family="serif" font-size="12" fill="#daff00">', certificateUri, '</text>',
            '</svg>'
        ));

        // Encode the SVG as base64
        string memory base64Svg = Base64.encode(bytes(svg));
        
        // Return the complete data URI
        return string(abi.encodePacked('data:image/svg+xml;base64,', base64Svg));
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

        assembly {
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

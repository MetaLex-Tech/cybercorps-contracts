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
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bodP' Y8P 
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
import "./ICyberCorpExtension.sol";
import "../../libs/auth.sol";

/// @notice One line of the SPV's portfolio: which portfolio company it holds, the kind of security, and
/// how many underlying shares/units. The SPV-unit-to-underlying ratio is derived offchain as
/// totalUnitsOutstanding : underlyingShares (per holding).
struct PortfolioHolding {
    string portfolioCompany;   // e.g. "Anthropic, PBC"
    string securityKind;       // e.g. "Series C Preferred Stock"
    uint256 underlyingShares;  // underlying shares/units the SPV holds
}

/// @notice Per-SPV fund metadata carried by the fund entity's cyberCORP. Fund name, jurisdiction of
/// domicile and legal designation live on the base CyberCorp fields (cyberCORPName / cyberCORPJurisdiction
/// / cyberCORPType); this extension carries the fund-specific compliance and portfolio configuration.
/// Informational counterparts of enforced values (holderCap vs HolderCapCondition.cap, regSIssuerCategory
/// vs RegSDistributionComplianceCondition.regSConfigs) should be kept in sync by the SPV's admin.
struct CyberCorpFundData {
    string fundEntityType;                  // LLC, LP, or non-U.S. equivalent
    string icaExceptionRelied;              // §3(c)(1), §3(c)(1)(C) QVCF, or §3(c)(7); note Touche Remnant
                                            // modified counting for non-U.S. funds with U.S. resident BOs
    uint8 regSIssuerCategory;               // Reg S issuer category 1/2/3 → distribution compliance period
    uint256 holderCap;                      // 100 (§3(c)(1)) / 250 (§3(c)(1)(C)); 0 = none beyond the QP
    uint256 totalUnitsOutstanding;          // ratio numerator base when unitized
    bool ratioStable;                       // unit-to-underlying ratio "stable" vs "subject-to-change"
    PortfolioHolding[] portfolioHoldings;
    bool cfiusSensitive;                    // FIRRMA fund exception not met and portfolio co. is a TID U.S. business
    bytes32 provenanceAttestationHash;      // GP underlying-asset provenance attestation (§4.1.0)
    string documentRegistryURI;             // disclosure package referencing the provenance attestation
    string[] governingDocumentURIs;         // operating agreement, PPM, subscription agreement templates
    string metadataURI;
}

contract CyberCorpFundExtension is
    UUPSUpgradeable,
    ICyberCorpExtension,
    BorgAuthACL
{
    bytes32 public constant EXTENSION_TYPE = keccak256("CYBERCORP_FUND");

    uint256[30] private __gap;

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodeExtensionData(
        bytes memory data
    ) external pure returns (CyberCorpFundData memory) {
        return abi.decode(data, (CyberCorpFundData));
    }

    function encodeExtensionData(
        CyberCorpFundData memory data
    ) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsExtensionType(
        bytes32 extensionType
    ) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(
        bytes memory data
    ) external pure override returns (string memory) {
        CyberCorpFundData memory decoded = abi.decode(
            data,
            (CyberCorpFundData)
        );

        // Built in parts to stay within stack limits
        return string.concat(
            ', "CyberCorpFundDetails": {',
            _entityAndExceptionJson(decoded),
            _portfolioJson(decoded),
            _attestationAndDocsJson(decoded),
            "}"
        );
    }

    function _entityAndExceptionJson(
        CyberCorpFundData memory decoded
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"fundEntityType": "',
                decoded.fundEntityType,
                '", "icaExceptionRelied": "',
                decoded.icaExceptionRelied,
                '", "regSIssuerCategory": ',
                uint256ToString(decoded.regSIssuerCategory),
                ', "holderCap": ',
                uint256ToString(decoded.holderCap)
            )
        );
    }

    function _portfolioJson(
        CyberCorpFundData memory decoded
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                ', "totalUnitsOutstanding": ',
                uint256ToString(decoded.totalUnitsOutstanding),
                ', "ratioStable": ',
                boolToString(decoded.ratioStable),
                ', "portfolioHoldings": ',
                portfolioHoldingsToJson(decoded.portfolioHoldings)
            )
        );
    }

    function _attestationAndDocsJson(
        CyberCorpFundData memory decoded
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                ', "cfiusSensitive": ',
                boolToString(decoded.cfiusSensitive),
                ', "provenanceAttestationHash": "',
                _toHexString(abi.encodePacked(decoded.provenanceAttestationHash)),
                '", "documentRegistryURI": "',
                decoded.documentRegistryURI,
                '", "governingDocumentURIs": ',
                stringArrayToJson(decoded.governingDocumentURIs),
                ', "metadataURI": "',
                decoded.metadataURI,
                '"'
            )
        );
    }

    function portfolioHoldingsToJson(
        PortfolioHolding[] memory holdings
    ) internal pure returns (string memory) {
        string memory json = "[";

        for (uint256 i = 0; i < holdings.length; i++) {
            if (i > 0) {
                json = string.concat(json, ", ");
            }
            json = string.concat(
                json,
                '{"portfolioCompany": "',
                holdings[i].portfolioCompany,
                '", "securityKind": "',
                holdings[i].securityKind,
                '", "underlyingShares": ',
                uint256ToString(holdings[i].underlyingShares),
                "}"
            );
        }

        return string.concat(json, "]");
    }

    function boolToString(bool value) internal pure returns (string memory) {
        return value ? "true" : "false";
    }

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function stringArrayToJson(
        string[] memory values
    ) internal pure returns (string memory) {
        string memory json = "[";

        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) {
                json = string.concat(json, ", ");
            }
            json = string.concat(json, '"', values[i], '"');
        }

        return string.concat(json, "]");
    }

    function _toHexString(bytes memory data) internal pure returns (string memory) {
        bytes16 symbols = 0x30313233343536373839616263646566;
        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = symbols[uint8(data[i] >> 4)];
            str[3 + i * 2] = symbols[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}

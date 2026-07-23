/*    .o.
     .888.
    .8"888.
   .8' `888.
  .88ooo8888.
 .8'     `888.
o88o     o8888o

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
import "../../libs/auth.sol";

/// @notice Security identification fields (spec §4.2.2). Names reference FIX tags for interoperability;
/// the protocol does not emit FIX messages.
struct SecurityIdentification {
    string securityID;
    string securityIDSource;
    string securityType;
    string securityDesc;
    string issuer;
}

/// @notice Per-LET fund-interest data. Acquisition and affiliate status belong to the holder's individual
/// lot; the Rule 144 tacking anchor is likewise per-token.
struct FundInterestData {
    uint64 acquisitionDate;
    uint64 tackedFromAcquisitionDate;
    bool isAffiliateOrControlPerson;
    string customProvisions;
}

/// @notice Fund-interest terms shared by all LETs issued from one printer (the class/series scope).
struct FundInterestSeriesData {
    string interestClass;
    string fundEntityType;
    string icaExceptionRelied;
    uint16 managementFeeRateBps;
    uint16 carriedInterestRateBps;
    string distributionWaterfallPosition;
    string[] governingDocumentURIs;
    SecurityIdentification securityIdentification;
}

/// @dev Canonical fund-interest extension-type key.
bytes32 constant FUND_INTEREST_EXTENSION_TYPE = keccak256("FUND_INTEREST");

/// @title FundInterestExtension - split LET and series data for fund interests
/// @notice The printer's `seriesData` encodes FundInterestSeriesData; each certificate's
/// `CertificateDetails.extensionData` encodes FundInterestData.
contract FundInterestExtension is UUPSUpgradeable, IFundInterestExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = FUND_INTEREST_EXTENSION_TYPE;

    uint256[30] private __gap;

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    /// @notice Typed accessors so consumers read/rewrite the payload without knowing its layout. Each
    /// deployed version decodes/encodes against its own FundInterestData, keeping the layout private here.
    /// Like the sibling decode accessors these revert on empty/malformed data rather than defaulting; the
    /// "no extension data" case is the caller's to guard (both current callers do).
    function acquisitionDate(bytes memory data) external pure returns (uint64) {
        return abi.decode(data, (FundInterestData)).acquisitionDate;
    }

    function tackedFromAcquisitionDate(bytes memory data) external pure returns (uint64) {
        return abi.decode(data, (FundInterestData)).tackedFromAcquisitionDate;
    }

    function withTackedFrom(bytes memory data, uint64 ts) external pure returns (bytes memory) {
        FundInterestData memory fid = abi.decode(data, (FundInterestData));
        fid.tackedFromAcquisitionDate = ts;
        return abi.encode(fid);
    }

    function decodeExtensionData(bytes memory data) external pure returns (FundInterestData memory) {
        return abi.decode(data, (FundInterestData));
    }

    function encodeExtensionData(FundInterestData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function decodeSeriesExtensionData(
        bytes memory data
    ) external pure returns (FundInterestSeriesData memory) {
        return abi.decode(data, (FundInterestSeriesData));
    }

    function encodeSeriesExtensionData(
        FundInterestSeriesData memory data
    ) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsSeriesExtensionData() external pure returns (bool) {
        return true;
    }

    function getExtensionURI(bytes memory data) external pure override returns (string memory) {
        if (data.length == 0) return "";
        FundInterestData memory decoded = abi.decode(data, (FundInterestData));
        return string(
            abi.encodePacked(
                ', "FundInterestTokenDetails": {',
                '"acquisitionDate": "', _uintToString(decoded.acquisitionDate),
                '", "tackedFromAcquisitionDate": "', _uintToString(decoded.tackedFromAcquisitionDate),
                '", "isAffiliateOrControlPerson": ', decoded.isAffiliateOrControlPerson ? "true" : "false",
                "}"
            )
        );
    }

    function getSeriesExtensionURI(bytes memory data) external pure returns (string memory) {
        if (data.length == 0) return "";
        FundInterestSeriesData memory decoded = abi.decode(data, (FundInterestSeriesData));
        return string.concat(
            ', "FundInterestSeriesDetails": {',
            _seriesIdentityJson(decoded),
            _seriesTermsJson(decoded),
            _securityIdentificationJson(decoded.securityIdentification),
            "}"
        );
    }

    function _seriesIdentityJson(
        FundInterestSeriesData memory data
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"interestClass": "', data.interestClass,
                '", "fundEntityType": "', data.fundEntityType,
                '", "icaExceptionRelied": "', data.icaExceptionRelied,
                '"'
            )
        );
    }

    function _seriesTermsJson(
        FundInterestSeriesData memory data
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                ', "managementFeeRateBps": ', _uintToString(data.managementFeeRateBps),
                ', "carriedInterestRateBps": ', _uintToString(data.carriedInterestRateBps),
                ', "distributionWaterfallPosition": "', data.distributionWaterfallPosition,
                '", "governingDocumentURIs": ', _stringArrayToJson(data.governingDocumentURIs)
            )
        );
    }

    function _securityIdentificationJson(
        SecurityIdentification memory data
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                ', "securityIdentification": {',
                '"securityID": "', data.securityID,
                '", "securityIDSource": "', data.securityIDSource,
                '", "securityType": "', data.securityType,
                '", "securityDesc": "', data.securityDesc,
                '", "issuer": "', data.issuer,
                '"}'
            )
        );
    }

    function _stringArrayToJson(string[] memory values) internal pure returns (string memory) {
        string memory json = "[";
        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) json = string.concat(json, ", ");
            json = string.concat(json, '"', values[i], '"');
        }
        return string.concat(json, "]");
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
/*
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

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/
/*

pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./ICertificateExtension.sol";
import "../../libs/auth.sol";

/// @notice Security identification fields (spec §4.2.2). Names reference FIX tags for interoperability;
/// the protocol does not emit FIX messages.
struct SecurityIdentification {
    string securityID;        // FIX Tag 48: unique identifier — the SPV's EIN, LEI, or a platform id
    string securityIDSource;  // FIX Tag 22: source of the identifier ("EIN", "LEI", "PLATFORM")
    string securityType;      // FIX Tag 167: e.g. "FUND", or a CFI Code (Tag 461) for ISO 10962
    string securityDesc;      // FIX Tag 107: e.g. "Class A Member Interest in [SPV Name]"
    string issuer;            // FIX Tag 106: the SPV's name
}

/// @notice Per-certificate fund-interest data (spec §§4.2.2, 12B.3). Each field is specific to the
/// holder's LET. The two dates drive the Rule 144 holding period (HoldingPeriodCondition) and the Reg S
/// distribution compliance period; acquisitionDate is the offchain closing date, not the token minting
/// date, and is also mirrored into the printer's base acquisitionTimestamp mapping.
struct FundInterestData {
    uint64 acquisitionDate;
    uint64 tackedFromAcquisitionDate;
    bool isAffiliateOrControlPerson;
}

/// @notice V3 series-scope fund-interest data. One CyberCertPrinter represents one series, so this data
/// is stored once in the printer's `seriesData` and applies uniformly to its LETs.
struct FundInterestSeriesData {
    string interestClass;
    string fundEntityType;
    string icaExceptionRelied;
    address transferRestrictionHookAddress;
    uint16 managementFeeRateBps;
    uint16 carriedInterestRateBps;
    string distributionWaterfallPosition;
    string[] governingDocumentURIs;
    SecurityIdentification securityIdentification;
}

/// @dev Canonical FUND_INTEREST extension-type key. File-level so guards elsewhere reference it by name
/// instead of re-hashing the literal (the contract's EXTENSION_TYPE and every supportsExtensionType check).
bytes32 constant FUND_INTEREST_EXTENSION_TYPE = keccak256("FUND_INTEREST");

/// @title FundInterestExtension - certificate extension for SPV fund interests
/// @author MetaLeX Labs, Inc.
contract FundInterestExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = FUND_INTEREST_EXTENSION_TYPE;

    //offset to leave for future upgrades
    uint256[30] private __gap;

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    function decodeExtensionData(bytes memory data) external pure returns (FundInterestData memory) {
        return abi.decode(data, (FundInterestData));
    }

    function encodeExtensionData(FundInterestData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function supportsExtensionType(bytes32 extensionType) external pure virtual override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(bytes memory data) external view override returns (string memory) {
        if (data.length == 0) return "";
        FundInterestData memory decoded = abi.decode(data, (FundInterestData));
        return string(
            abi.encodePacked(
                ', "FundInterestTokenDetails": {',
                '"acquisitionDate": "', uint256ToString(decoded.acquisitionDate),
                '", "tackedFromAcquisitionDate": "', uint256ToString(decoded.tackedFromAcquisitionDate),
                '", "isAffiliateOrControlPerson": ',
                decoded.isAffiliateOrControlPerson ? "true" : "false",
                "}"
            )
        );
    }

    function supportsSeriesExtensionData() external pure returns (bool) {
        return true;
    }

    function decodeSeriesExtensionData(
        bytes memory data
    ) external pure returns (FundInterestSeriesData memory) {
        return abi.decode(data, (FundInterestSeriesData));
    }

    function encodeSeriesExtensionData(
        FundInterestSeriesData memory data
    ) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    function getSeriesExtensionURI(bytes memory data) external view returns (string memory) {
        if (data.length == 0) return "";
        FundInterestSeriesData memory decoded = abi.decode(data, (FundInterestSeriesData));
        return string.concat(
            ', "FundInterestSeriesDetails": {',
            _seriesIdentityJson(decoded),
            _seriesTermsJson(decoded),
            _securityIdentificationJson(decoded.securityIdentification),
            "}"
        );
    }

    function _seriesIdentityJson(
        FundInterestSeriesData memory decoded
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"interestClass": "', decoded.interestClass,
                '", "fundEntityType": "', decoded.fundEntityType,
                '", "icaExceptionRelied": "', decoded.icaExceptionRelied,
                '", "transferRestrictionHookAddress": "',
                addressToString(decoded.transferRestrictionHookAddress),
                '"'
            )
        );
    }

    function _seriesTermsJson(
        FundInterestSeriesData memory decoded
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                ', "managementFeeRateBps": ',
                uint256ToString(decoded.managementFeeRateBps),
                ', "carriedInterestRateBps": ',
                uint256ToString(decoded.carriedInterestRateBps),
                ', "distributionWaterfallPosition": "',
                decoded.distributionWaterfallPosition,
                '"',
                ', "governingDocumentURIs": ',
                stringArrayToJson(decoded.governingDocumentURIs)
            )
        );
    }

    function _securityIdentificationJson(
        SecurityIdentification memory sid
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                ', "securityIdentification": {',
                '"securityID": "',
                sid.securityID,
                '", "securityIDSource": "',
                sid.securityIDSource,
                '", "securityType": "',
                sid.securityType,
                '", "securityDesc": "',
                sid.securityDesc,
                '", "issuer": "',
                sid.issuer,
                '"}'
            )
        );
    }

    function stringArrayToJson(string[] memory values) internal pure returns (string memory) {
        string memory json = "[";

        for (uint256 i = 0; i < values.length; i++) {
            if (i > 0) {
                json = string.concat(json, ", ");
            }
            json = string.concat(json, '"', values[i], '"');
        }

        return string.concat(json, "]");
    }

    function addressToString(address account) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(account);
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

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}*/

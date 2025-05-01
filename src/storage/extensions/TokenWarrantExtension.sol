// SPDX-License-Identifier: Proprietary
pragma solidity 0.8.28;

import "./ICertificateExtension.sol";
import "../../CyberCorpConstants.sol";

// Helper function to convert uint256 to string
function uint256ToString(uint256 _i) pure returns (string memory) {
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

// Helper functions to convert enums to strings
function exercisePriceTypeToString(ExercisePriceType _type) pure returns (string memory) {
    if (_type == ExercisePriceType.perWarrant) return "perWarrant";
    if (_type == ExercisePriceType.perToken) return "perToken";
    return "Unknown";
}

function conversionTypeToString(ConversionType _type) pure returns (string memory) {
    if (_type == ConversionType.equityProRataToCompanyReserveModel) return "equityProRataToCompanyReserveModel";
    if (_type == ConversionType.equityProRataToTokenSupplyModel) return "equityProRataToTokenSupplyModel";
    return "Unknown";
}

function lockupStartTypeToString(LockupStartType _type) pure returns (string memory) {
    if (_type == LockupStartType.timeOfTokenWarrant) return "timeOfTokenWarrant";
    if (_type == LockupStartType.timeOfTGE) return "timeOfTGE";
    if (_type == LockupStartType.arbitraryTime) return "arbitraryTime";
    return "Unknown";
}

function lockupIntervalTypeToString(LockupIntervalType _type) pure returns (string memory) {
    if (_type == LockupIntervalType.byBlock) return "byBlock";
    if (_type == LockupIntervalType.monthly) return "monthly";
    if (_type == LockupIntervalType.quarterly) return "quarterly";
    return "Unknown";
}

struct TokenWarrantData {
    ExercisePriceType exercisePriceType;
    uint256 exercisePrice;
    ConversionType conversionType;
    uint256 reservePercent;
    uint256 networkPremiumMultiplier;
    LockupStartType lockupStartType;
    uint256 lockupLength;
    uint256 lockupCliffInMonths;
    LockupIntervalType lockupIntervalType;
    uint256 latestExpirationTime;
}

contract TokenWarrantExtension is ICertificateExtension {
    bytes32 public constant EXTENSION_TYPE = keccak256("TOKEN_WARRANT");

    mapping(uint256 => TokenWarrantData) private warrantData;

    function getExtensionData(uint256 tokenId) external view override returns (bytes memory) {
        return abi.encode(warrantData[tokenId]);
    }

    function setExtensionData(uint256 tokenId, bytes memory data) external override {
        TokenWarrantData memory decoded = abi.decode(data, (TokenWarrantData));
        warrantData[tokenId] = decoded;
    }

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function getExtensionURI(bytes memory data) external view override returns (string memory) {
        TokenWarrantData memory decoded = abi.decode(data, (TokenWarrantData));
        
        string memory json = string(abi.encodePacked(
            ', "warrantDetails": {',
            '"exercisePriceType": "', exercisePriceTypeToString(decoded.exercisePriceType),
            '", "exercisePrice": "', uint256ToString(decoded.exercisePrice),
            '", "conversionType": "', conversionTypeToString(decoded.conversionType),
            '", "reservePercent": "', uint256ToString(decoded.reservePercent),
            '", "networkPremiumMultiplier": "', uint256ToString(decoded.networkPremiumMultiplier),
            '", "lockupStartType": "', lockupStartTypeToString(decoded.lockupStartType),
            '", "lockupLength": "', uint256ToString(decoded.lockupLength),
            '", "lockupCliffInMonths": "', uint256ToString(decoded.lockupCliffInMonths),
            '", "lockupIntervalType": "', lockupIntervalTypeToString(decoded.lockupIntervalType),
            '", "latestExpirationTime": "', uint256ToString(decoded.latestExpirationTime),
            '"}'
        ));
        
        return json;
    }
}
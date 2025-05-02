// SPDX-License-Identifier: Proprietary
pragma solidity 0.8.28;

import "./ICertificateExtension.sol";
import "../../CyberCorpConstants.sol";

/*enum ExercisePriceMethod {
    perToken,
    perWarrant
}

enum TokenCalculationMethod {
    equityProRataToCompanyReserve,
    equityProRataToTokenSupply 
}

enum unlockStartTimeType {
    tokenWarrentTime,
    tgeTime,
    setTime
}

enum UnlockingIntervalType {
    byBlock,
    seconds,
    hourly,
    daily,
    monthly,
    quarterly
}*/

struct TokenWarrantData {
    ExercisePriceMethod exercisePriceMethod;  // perToken or perWarrant
    uint256 exercisePrice;                   // 18 decimals
    UnlockStartTimeType unlockStartTimeType;     // enum of different types, can be tokenWarrantTime, tgeTime, or setTime
    uint256 unlockStartTime;                 // seconds (relative unless type is fixed)
    uint256 unlockingPeriod;
    uint256 latestExpirationTime; //latest time at which the Warrant can expire (cease to be exercisable)--denominated in seconds
    uint256 unlockingCliffPeriod; // seconds
    uint256 unlockingCliffPercentage; // what precision??
    UnlockingIntervalType unlockingIntervalType; // blockly, seconds, daily, weekly, monthly
    TokenCalculationMethod tokenCalculationMethod; //equityProRataToTokenSupply or equityProRataToCompanyReserve
    uint256 minCompanyReserve; //minimum company reserve within an equityProRataToCompanyReserve method--set to 0 if there is no minimum
    uint256 tokenPremiumMultiplier; //multiplier of network valuation over company equity valuation, to be used within equityProRataToTokenSupply method (set to 0 if no premium)
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
            '"exercisePriceMethod": "', ExercisePriceMethodToString(decoded.exercisePriceMethod),
            '", "exercisePrice": "', uint256ToString(decoded.exercisePrice),
            '", "unlockStartTimeType": "', UnlockStartTimeTypeToString(decoded.unlockStartTimeType),
            '", "unlockStartTime": "', uint256ToString(decoded.unlockStartTime),
            '", "unlockingPeriod": "', uint256ToString(decoded.unlockingPeriod),
            '", "latestExpirationTime": "', uint256ToString(decoded.latestExpirationTime),
            '", "unlockingCliffPeriod": "', uint256ToString(decoded.unlockingCliffPeriod),
            '", "unlockingCliffPercentage": "', uint256ToString(decoded.unlockingCliffPercentage),
            '", "unlockingIntervalType": "', UnlockingIntervalTypeToString(decoded.unlockingIntervalType),
            '", "tokenCalculationMethod": "', conversionTypeToString(decoded.tokenCalculationMethod),
            '", "minCompanyReserve": "', uint256ToString(decoded.minCompanyReserve),
            '", "tokenPremiumMultiplier": "', uint256ToString(decoded.tokenPremiumMultiplier),
            '"}'
        ));
        
        return json;
    }

        // Helper function to convert uint256 to string
    function uint256ToString(uint256 _i) internal pure returns (string memory) {
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
    function ExercisePriceMethodToString(ExercisePriceMethod _type) internal pure returns (string memory) {
        if (_type == ExercisePriceMethod.perWarrant) return "perWarrant";
        if (_type == ExercisePriceMethod.perToken) return "perToken";
        return "Unknown";
    }

    function conversionTypeToString(TokenCalculationMethod _type) internal pure returns (string memory) {
        if (_type == TokenCalculationMethod.equityProRataToCompanyReserve) return "equityProRataToCompanyReserve";
        if (_type == TokenCalculationMethod.equityProRataToTokenSupply) return "equityProRataToTokenSupply";
        return "Unknown";
    }

    function UnlockStartTimeTypeToString(UnlockStartTimeType _type) internal pure returns (string memory) {
        if (_type == UnlockStartTimeType.tokenWarrentTime) return "tokenWarrentTime";
        if (_type == UnlockStartTimeType.tgeTime) return "tgeTime";
        if (_type == UnlockStartTimeType.setTime) return "setTime";
        return "Unknown";
    }

    function UnlockingIntervalTypeToString(UnlockingIntervalType _type) internal pure returns (string memory) {
        if (_type == UnlockingIntervalType.byBlock) return "byBlock";
        if (_type == UnlockingIntervalType.second) return "seconds";
        if (_type == UnlockingIntervalType.hourly) return "hourly";
        if (_type == UnlockingIntervalType.daily) return "daily";
        if (_type == UnlockingIntervalType.monthly) return "monthly";
        return "Unknown";
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {UnlockStartTimeType, UnlockingIntervalType} from "../../CyberCorpConstants.sol";
import {JsonLib} from "../../libs/JsonLib.sol";
import {BorgAuthACL} from "../../libs/auth.sol";
import {ICertificateExtension} from "./ICertificateExtension.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Terms of one SAFO, encoded in CertificateDetails.extensionData.
/// @dev Amount and project valuation remain in the core CertificateDetails fields.
/// Structure elections and launch notices remain offchain; this payload does not
/// elect a structure, determine a conversion method or calculate an entitlement.
struct SAFOData {
    uint8 schemaVersion;
    // Percentage points, four decimals: 20% = 200_000; 100% = 1_000_000.
    uint256 minProjectReserve;
    // Maximum durations in seconds, each measured from the Token Launch Event.
    uint256 maxUnlockingCliffPeriod;
    uint256 maxUnlockingPeriod;
    bool requiresTokenholderGovernance;
    bool outsideDateEnabled;
    // Whole calendar years after the original Issue Date, not a Unix timestamp.
    // Zero is an express immediate outside date when enabled, not "disabled".
    uint256 outsideDate;
    // Optional record of the schedule established by the offchain Launch Configuration.
    bool hasUnlockParameters;
    UnlockStartTimeType unlockStartTimeType;
    uint256 unlockStartTime; // Unix seconds, used only for setTime.
    uint256 unlockingPeriod; // Count of unlockingIntervalType units.
    uint256 unlockingCliffPeriod; // Count of unlockingIntervalType units.
    uint256 unlockingCliffPercentage; // Percentage points, four decimals.
    UnlockingIntervalType unlockingIntervalType;
    string customProvisions;
}

/// @title Per-LET metadata extension for the Simple Agreement for Future Ownership
/// @dev Implements the base extension surface and makes no printer/series/class reads.
/// Validation here is not an issuance hook: callers must validate opaque payloads
/// before writing them to a LET. Never replace another instrument's extension with this decoder.
contract SAFOExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {
    bytes32 public constant EXTENSION_TYPE = keccak256("SAFO");
    uint8 public constant SCHEMA_VERSION = 1;
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;
    uint256 public constant ONE_HUNDRED_PERCENT = 100 * PERCENTAGE_PRECISION;

    error UnsupportedSchemaVersion(uint8 version);
    error InvalidPercentage(uint256 value);
    error UnexpectedOutsideDate();
    error UnexpectedUnlockParameters();
    error UnexpectedUnlockStartTime();
    error NoncanonicalEncoding();

    uint256[30] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(auth);
    }

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    function encodeExtensionData(SAFOData memory data) external pure returns (bytes memory) {
        _validate(data);
        return abi.encode(data);
    }

    function decodeExtensionData(bytes memory encoded) public pure returns (SAFOData memory data) {
        data = abi.decode(encoded, (SAFOData));
        _validate(data);
        // ABI decoding ignores trailing bytes and unused string padding. Require
        // one byte representation so reviewed terms have one payload hash.
        if (keccak256(encoded) != keccak256(abi.encode(data))) revert NoncanonicalEncoding();
    }

    /// @notice Validates the payload's schema, units' bounds and optional-field consistency.
    /// @dev Does not determine whether an offchain launch or schedule complies with the SAFO.
    function validateExtensionData(bytes memory encoded) external pure returns (bool) {
        decodeExtensionData(encoded);
        return true;
    }

    function getExtensionURI(bytes memory encoded) public pure override returns (string memory) {
        SAFOData memory data = decodeExtensionData(encoded);
        string memory json = string.concat(
            ', "SAFODetails": {"schemaVersion": "',
            Strings.toString(data.schemaVersion),
            '", "minProjectReserve": "',
            Strings.toString(data.minProjectReserve),
            '", "maxUnlockingCliffPeriod": "',
            Strings.toString(data.maxUnlockingCliffPeriod),
            '", "maxUnlockingPeriod": "',
            Strings.toString(data.maxUnlockingPeriod),
            '", "requiresTokenholderGovernance": ',
            JsonLib.boolToString(data.requiresTokenholderGovernance),
            ', "outsideDateEnabled": ',
            JsonLib.boolToString(data.outsideDateEnabled)
        );
        if (data.outsideDateEnabled) {
            json = string.concat(json, ', "outsideDate": "', Strings.toString(data.outsideDate), '"');
        }
        json = string.concat(json, ', "hasUnlockParameters": ', JsonLib.boolToString(data.hasUnlockParameters));
        if (data.hasUnlockParameters) {
            json = string.concat(
                json,
                ', "unlockStartTimeType": "',
                _startType(data.unlockStartTimeType),
                '", "unlockStartTime": "',
                Strings.toString(data.unlockStartTime),
                '", "unlockingPeriod": "',
                Strings.toString(data.unlockingPeriod),
                '", "unlockingCliffPeriod": "',
                Strings.toString(data.unlockingCliffPeriod),
                '", "unlockingCliffPercentage": "',
                Strings.toString(data.unlockingCliffPercentage),
                '", "unlockingIntervalType": "',
                _intervalType(data.unlockingIntervalType),
                '"'
            );
        }
        return string.concat(json, ', "customProvisions": "', JsonLib.jsonEscape(data.customProvisions), '"}');
    }

    function _validate(SAFOData memory data) private pure {
        if (data.schemaVersion != SCHEMA_VERSION) revert UnsupportedSchemaVersion(data.schemaVersion);
        if (data.minProjectReserve > ONE_HUNDRED_PERCENT) revert InvalidPercentage(data.minProjectReserve);
        if (!data.outsideDateEnabled && data.outsideDate != 0) revert UnexpectedOutsideDate();
        if (!data.hasUnlockParameters) {
            if (
                uint8(data.unlockStartTimeType) != 0 || data.unlockStartTime != 0 || data.unlockingPeriod != 0
                    || data.unlockingCliffPeriod != 0 || data.unlockingCliffPercentage != 0
                    || uint8(data.unlockingIntervalType) != 0
            ) revert UnexpectedUnlockParameters();
        } else {
            if (data.unlockingCliffPercentage > ONE_HUNDRED_PERCENT) {
                revert InvalidPercentage(data.unlockingCliffPercentage);
            }
            if (data.unlockStartTimeType != UnlockStartTimeType.setTime && data.unlockStartTime != 0) {
                revert UnexpectedUnlockStartTime();
            }
        }
    }

    function _startType(UnlockStartTimeType value) private pure returns (string memory) {
        if (value == UnlockStartTimeType.tokenWarrantTime) return "agreementExecutionTime";
        if (value == UnlockStartTimeType.tgeTime) return "tgeTime";
        return "setTime";
    }

    function _intervalType(UnlockingIntervalType value) private pure returns (string memory) {
        if (value == UnlockingIntervalType.blockly) return "blockly";
        if (value == UnlockingIntervalType.secondly) return "secondly";
        if (value == UnlockingIntervalType.hourly) return "hourly";
        if (value == UnlockingIntervalType.daily) return "daily";
        return "monthly";
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

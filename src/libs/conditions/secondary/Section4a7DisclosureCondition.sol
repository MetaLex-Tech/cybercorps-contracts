// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ICyberAgreementRegistry.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  Section4a7DisclosureCondition - §4(a)(7) information-delivery gate
/// @author MetaLeX Labs, Inc.
/// @notice Shared threshold condition. Two-part test per §4(a)(7)(d)(3):
///  1. The SPV's information package (incl. two years of GAAP financials) must be on record and fresh —
///     the SPV's admin anchors its URI + as-of timestamp here; checked from posting onward.
///  2. The buyer must have acknowledged receipt — read from the buyer's party values on the settlement
///     agreement (recorded at acceptance), matched against the configured acknowledgment string.
contract Section4a7DisclosureCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    struct DisclosureRecord {
        string uri;         // offchain §4(a)(7)(d)(3) information package
        uint64 asOf;        // freshness timestamp
    }

    error InvalidSpv();
    error InvalidMaxAge();
    error InvalidTimestamp();
    error InvalidRegistry();
    error InvalidAcknowledgment();

    event DisclosurePackageUpdated(address indexed spv, string uri, uint64 asOf);
    event MaxAgeUpdated(uint256 maxAge);
    event RegistryUpdated(address registry);
    event AcknowledgmentValueUpdated(string acknowledgmentValue);

    ICyberAgreementRegistry public registry;
    /// @notice Exact party-value string the buyer must record as their acknowledgment of receipt
    string public acknowledgmentValue;
    /// @notice Freshness policy in seconds for the information package
    uint256 public maxAge;

    /// @notice Per-SPV (cyberCORP address) disclosure record
    mapping(address => DisclosureRecord) public disclosures;

    uint256[46] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _registry,
        string memory _acknowledgmentValue,
        uint256 _maxAge
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_registry == address(0)) revert InvalidRegistry();
        if (bytes(_acknowledgmentValue).length == 0) revert InvalidAcknowledgment();
        if (_maxAge == 0) revert InvalidMaxAge();
        registry = ICyberAgreementRegistry(_registry);
        acknowledgmentValue = _acknowledgmentValue;
        maxAge = _maxAge;
        emit RegistryUpdated(_registry);
        emit AcknowledgmentValueUpdated(_acknowledgmentValue);
        emit MaxAgeUpdated(_maxAge);
    }

    function updateRegistry(address _registry) external onlyAdmin {
        if (_registry == address(0)) revert InvalidRegistry();
        registry = ICyberAgreementRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    function updateAcknowledgmentValue(string memory _acknowledgmentValue) external onlyAdmin {
        if (bytes(_acknowledgmentValue).length == 0) revert InvalidAcknowledgment();
        acknowledgmentValue = _acknowledgmentValue;
        emit AcknowledgmentValueUpdated(_acknowledgmentValue);
    }

    function updateMaxAge(uint256 _maxAge) external onlyAdmin {
        if (_maxAge == 0) revert InvalidMaxAge();
        maxAge = _maxAge;
        emit MaxAgeUpdated(_maxAge);
    }

    /// @notice Records/refreshes an SPV's information package; only the SPV's own BorgAuth admin
    function setDisclosurePackage(address spv, string memory uri, uint64 asOf) external {
        if (spv == address(0)) revert InvalidSpv();
        if (asOf == 0 || asOf > block.timestamp) revert InvalidTimestamp();
        _requireAuthAdmin(spv);
        disclosures[spv] = DisclosureRecord({uri: uri, asOf: asOf});
        emit DisclosurePackageUpdated(spv, uri, asOf);
    }

    /// @notice True when the SPV's information package exists and is within the freshness policy
    function isDisclosureCurrent(address spv) public view returns (bool) {
        DisclosureRecord storage record = disclosures[spv];
        if (record.asOf == 0) return false;
        return block.timestamp <= uint256(record.asOf) + maxAge;
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);

        // Part 1 — SPV-wide, enforced from posting onward: the package must exist and be fresh
        if (!isDisclosureCurrent(offer.spvAddress)) return false;

        // TODO review: do we want to check it as CyberAgreement strings?
        // Part 2 — buyer acknowledgment, which lives on the settlement agreement (acceptance onward)
        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);
        if (agreementId == bytes32(0) || buyer == address(0)) return true;

        string[] memory values = registry.getSignerValues(agreementId, buyer);
        bytes32 expected = keccak256(bytes(acknowledgmentValue));
        for (uint256 i = 0; i < values.length; i++) {
            if (keccak256(bytes(values[i])) == expected) return true;
        }
        return false;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

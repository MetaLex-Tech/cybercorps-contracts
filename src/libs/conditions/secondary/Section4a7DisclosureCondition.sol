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
///     agreement (recorded at acceptance), matched against the acknowledgment string that SPV requires.
contract Section4a7DisclosureCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    struct DisclosureRecord {
        string uri;                  // offchain §4(a)(7)(d)(3) information package
        uint64 asOf;                 // freshness timestamp
        string acknowledgmentValue;  // exact party-value string this SPV's buyers must record
    }

    error InvalidSpv();
    error InvalidMaxAge();
    error InvalidTimestamp();
    error InvalidRegistry();
    error InvalidAcknowledgment();

    event DisclosurePackageUpdated(address indexed spv, string uri, uint64 asOf, string acknowledgmentValue);
    event MaxAgeUpdated(uint256 maxAge);
    event RegistryUpdated(address registry);

    struct Section4a7Storage {
        ICyberAgreementRegistry registry;
        uint256 maxAge;
        mapping(address => DisclosureRecord) disclosures;
    }

    bytes32 private constant STORAGE_POSITION = keccak256("metalex.condition.secondary.section-4a7-disclosure.storage.v1");

    // Upgrade notes: reduced gap to account for the contract's variables (50 - 3 = 47)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, address _registry, uint256 _maxAge) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_registry == address(0)) revert InvalidRegistry();
        if (_maxAge == 0) revert InvalidMaxAge();
        Section4a7Storage storage $ = _section4a7Storage();
        $.registry = ICyberAgreementRegistry(_registry);
        $.maxAge = _maxAge;
        emit RegistryUpdated(_registry);
        emit MaxAgeUpdated(_maxAge);
    }

    function updateRegistry(address _registry) external onlyAdmin {
        if (_registry == address(0)) revert InvalidRegistry();
        _section4a7Storage().registry = ICyberAgreementRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    function updateMaxAge(uint256 _maxAge) external onlyAdmin {
        if (_maxAge == 0) revert InvalidMaxAge();
        _section4a7Storage().maxAge = _maxAge;
        emit MaxAgeUpdated(_maxAge);
    }

    /// @notice Records/refreshes an SPV's information package; only the SPV's own BorgAuth admin
    function setDisclosurePackage(
        address spv,
        string memory uri,
        uint64 asOf,
        string memory _acknowledgmentValue
    ) external {
        if (spv == address(0)) revert InvalidSpv();
        if (asOf == 0 || asOf > block.timestamp) revert InvalidTimestamp();
        if (bytes(_acknowledgmentValue).length == 0) revert InvalidAcknowledgment();
        _requireAuthAdmin(spv);
        _section4a7Storage().disclosures[spv] = DisclosureRecord({uri: uri, asOf: asOf, acknowledgmentValue: _acknowledgmentValue});
        emit DisclosurePackageUpdated(spv, uri, asOf, _acknowledgmentValue);
    }

    /// @notice True when the SPV's information package exists and is within the freshness policy
    function isDisclosureCurrent(address spv) public view returns (bool) {
        Section4a7Storage storage $ = _section4a7Storage();
        DisclosureRecord storage record = $.disclosures[spv];
        if (record.asOf == 0) return false;
        return block.timestamp <= uint256(record.asOf) + $.maxAge;
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

        Section4a7Storage storage $ = _section4a7Storage();
        string[] memory values = $.registry.getSignerValues(agreementId, buyer);
        bytes32 expected = keccak256(bytes($.disclosures[offer.spvAddress].acknowledgmentValue));
        for (uint256 i = 0; i < values.length; i++) {
            if (keccak256(bytes(values[i])) == expected) return true;
        }
        return false;
    }

    /// @notice The agreement registry the acknowledgment is read from
    function registry() public view returns (ICyberAgreementRegistry) {
        return _section4a7Storage().registry;
    }

    /// @notice Freshness policy in seconds
    function maxAge() public view returns (uint256) {
        return _section4a7Storage().maxAge;
    }

    /// @notice An SPV's disclosure record
    function disclosures(address spv) public view returns (DisclosureRecord memory) {
        return _section4a7Storage().disclosures[spv];
    }

    function _section4a7Storage() private pure returns (Section4a7Storage storage $) {
        bytes32 position = STORAGE_POSITION; // assembly cannot reference a computed constant directly
        assembly {
            $.slot := position
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

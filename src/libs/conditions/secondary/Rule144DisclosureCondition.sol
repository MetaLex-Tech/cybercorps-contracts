// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import {Offer} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  Rule144DisclosureCondition - current public information gate for Rule 144 trades
/// @author MetaLeX Labs, Inc.
/// @notice Shared threshold condition implementing Rule 144(c)(2) / 15c2-11(b)(5): the SPV must have a
/// current disclosure package on record. The package itself stays offchain; the SPV's admin records its
/// URI and as-of timestamp here (the cyberCORP-metadata anchor), and the condition fails when the record
/// is missing or stale (e.g. balance sheet older than 16 months per the freshness policy encoded at
/// configuration). No party lookup: the gate is SPV-wide and enforced at posting, acceptance, and finalize.
contract Rule144DisclosureCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    struct DisclosureRecord {
        string uri;         // offchain 144(c)(2) information package
        uint64 asOf;        // freshness timestamp (e.g. balance-sheet date)
    }

    error InvalidSpv();
    error InvalidMaxAge();
    error InvalidTimestamp();

    event DisclosurePackageUpdated(address indexed spv, string uri, uint64 asOf);
    event MaxAgeUpdated(uint256 maxAge);

    /// @notice Freshness policy in seconds (Rule 144(c)(2) practice: balance sheet no older than 16 months)
    uint256 public maxAge;

    /// @notice Per-SPV (cyberCORP address) disclosure record
    mapping(address => DisclosureRecord) public disclosures;

    uint256[48] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, uint256 _maxAge) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_maxAge == 0) revert InvalidMaxAge();
        maxAge = _maxAge;
        emit MaxAgeUpdated(_maxAge);
    }

    function updateMaxAge(uint256 _maxAge) external onlyAdmin {
        if (_maxAge == 0) revert InvalidMaxAge();
        maxAge = _maxAge;
        emit MaxAgeUpdated(_maxAge);
    }

    /// @notice Records/refreshes an SPV's disclosure package; only the SPV's own BorgAuth admin
    function setDisclosurePackage(address spv, string memory uri, uint64 asOf) external {
        if (spv == address(0)) revert InvalidSpv();
        if (asOf == 0 || asOf > block.timestamp) revert InvalidTimestamp();
        _requireAuthAdmin(spv);
        disclosures[spv] = DisclosureRecord({uri: uri, asOf: asOf});
        emit DisclosurePackageUpdated(spv, uri, asOf);
    }

    /// @notice True when the SPV's disclosure record exists and is within the freshness policy
    function isDisclosureCurrent(address spv) public view returns (bool) {
        DisclosureRecord storage record = disclosures[spv];
        if (record.asOf == 0) return false;
        return block.timestamp <= uint256(record.asOf) + maxAge;
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);
        return isDisclosureCurrent(offer.spvAddress);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

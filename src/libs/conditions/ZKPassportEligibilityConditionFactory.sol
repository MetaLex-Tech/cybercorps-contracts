// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {EligibilityRules} from "../../interfaces/IZKPassportEligibilityCondition.sol";
import {BorgAuthACL} from "../auth.sol";
import {ZKPassportEligibilityCondition} from "./ZKPassportEligibilityCondition.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BeaconProxy} from "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "openzeppelin-contracts/proxy/beacon/IBeacon.sol";
import {Create2} from "openzeppelin-contracts/utils/Create2.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

/// @title ZKPassportEligibilityConditionFactory
/// @notice Deterministic CREATE2 BeaconProxy factory deploying immutable-rule ZKPassportEligibilityCondition
///         instances that can be attached directly to any RoundManager (FCFS or FounderApproved) or DealManager.
/// @dev Acts as the IBeacon for all deployed condition proxies so MetaLeX core BorgAuth can upgrade the
///      shared implementation if ZKPassport verifier compatibility changes, while each proxy keeps its own
///      immutable eligibility rules, scope, domain, and devModeAllowed flag.
contract ZKPassportEligibilityConditionFactory is UUPSUpgradeable, BorgAuthACL, IBeacon {
    error InvalidImplementation();
    error InvalidVerifier();
    error InvalidDomain();
    error InvalidMaxValidityPeriod();

    event ImplementationUpdated(address indexed previousImplementation, address indexed newImplementation);
    event DefaultMaxValidityPeriodUpdated(uint256 maxValidityPeriod);
    event ExpectedDomainUpdated(string expectedDomain);
    event VerifierUpdated(address indexed verifier);
    event ConditionDeployed(
        address indexed condition, bytes32 indexed create2Salt, string expectedScope, EligibilityRules rules
    );

    string public constant DEPLOY_VERSION = "1.0";
    string public constant SCOPE_PREFIX = "metalex-eligibility-v1:";
    address public constant DEFAULT_ZKPASSPORT_VERIFIER = 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;

    address private _implementation;
    address public verifier;
    string public expectedDomain;
    uint256 public defaultMaxValidityPeriod;
    bool public devModeAllowed;

    mapping(address => bool) public isCondition;

    uint256[44] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _auth,
        address _initialImplementation,
        string memory _expectedDomain,
        address _verifier,
        uint256 _defaultMaxValidityPeriod,
        bool _devModeAllowed
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        if (_initialImplementation == address(0) || _initialImplementation.code.length == 0) {
            revert InvalidImplementation();
        }
        if (bytes(_expectedDomain).length == 0) revert InvalidDomain();
        if (_defaultMaxValidityPeriod == 0) revert InvalidMaxValidityPeriod();

        address resolvedVerifier = _verifier == address(0) ? DEFAULT_ZKPASSPORT_VERIFIER : _verifier;
        if (resolvedVerifier == address(0)) revert InvalidVerifier();

        _implementation = _initialImplementation;
        expectedDomain = _expectedDomain;
        verifier = resolvedVerifier;
        defaultMaxValidityPeriod = _defaultMaxValidityPeriod;
        devModeAllowed = _devModeAllowed;

        emit ImplementationUpdated(address(0), _initialImplementation);
        emit ExpectedDomainUpdated(_expectedDomain);
        emit VerifierUpdated(resolvedVerifier);
        emit DefaultMaxValidityPeriodUpdated(_defaultMaxValidityPeriod);
    }

    /// @notice Returns the current implementation address for all BeaconProxy condition instances.
    function implementation() external view override returns (address) {
        return _implementation;
    }

    /// @notice Upgrade the beacon implementation for all deployed condition proxies.
    function setImplementation(address newImplementation) external onlyOwner {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidImplementation();
        }
        address previous = _implementation;
        _implementation = newImplementation;
        emit ImplementationUpdated(previous, newImplementation);
    }

    /// @notice Update default proof max validity period for newly deployed condition instances.
    function setDefaultMaxValidityPeriod(uint256 _maxValidityPeriod) external onlyAdmin {
        if (_maxValidityPeriod == 0) revert InvalidMaxValidityPeriod();
        defaultMaxValidityPeriod = _maxValidityPeriod;
        emit DefaultMaxValidityPeriodUpdated(_maxValidityPeriod);
    }

    /// @notice Update expected domain for newly deployed condition instances.
    function setExpectedDomain(string calldata _expectedDomain) external onlyOwner {
        if (bytes(_expectedDomain).length == 0) revert InvalidDomain();
        expectedDomain = _expectedDomain;
        emit ExpectedDomainUpdated(_expectedDomain);
    }

    /// @notice Update verifier address for newly deployed condition instances.
    function setVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) revert InvalidVerifier();
        verifier = _verifier;
        emit VerifierUpdated(_verifier);
    }

    /// @notice Canonical hash of the eligibility rules.
    function computeRulesHash(EligibilityRules calldata rules) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                rules.allowedNationalities, rules.excludedNationalities, rules.minimumAge, rules.enforceSanctions
            )
        );
    }

    /// @notice Deterministic CREATE2 salt bound to expectedDomain, rules, and optional scopeSalt.
    /// @dev Pass scopeSalt = bytes32(0) to share one canonical condition per rule-set, or pass
    ///      a round-specific salt (e.g. roundId) for a round-isolated scope and nullifier domain.
    function computeCreate2Salt(EligibilityRules calldata rules, bytes32 scopeSalt) public view returns (bytes32) {
        return keccak256(abi.encode(expectedDomain, computeRulesHash(rules), scopeSalt));
    }

    /// @notice Deterministic ZKPassport scope derived from expectedDomain, rules, and scopeSalt.
    function computeExpectedScope(EligibilityRules calldata rules, bytes32 scopeSalt)
        public
        view
        returns (string memory)
    {
        bytes32 salt = computeCreate2Salt(rules, scopeSalt);
        return string.concat(SCOPE_PREFIX, Strings.toHexString(uint256(salt), 32));
    }

    /// @notice Predict the deterministic address of a condition for (rules, scopeSalt).
    function predictConditionAddress(EligibilityRules calldata rules, bytes32 scopeSalt) public view returns (address) {
        bytes32 salt = computeCreate2Salt(rules, scopeSalt);
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(this), bytes(""))));
        return Create2.computeAddress(salt, initCodeHash, address(this));
    }

    /// @notice Deploy (or return existing) deterministic condition instance for (rules, scopeSalt).
    /// @dev Idempotent: if a condition for this (expectedDomain, rules, scopeSalt) already exists,
    ///      returns its address directly. Rules are validated inside `initialize`.
    function deployCondition(EligibilityRules calldata rules, bytes32 scopeSalt) external returns (address condition) {
        address predicted = predictConditionAddress(rules, scopeSalt);
        if (isCondition[predicted]) {
            return predicted;
        }

        bytes32 salt = computeCreate2Salt(rules, scopeSalt);
        string memory scope = string.concat(SCOPE_PREFIX, Strings.toHexString(uint256(salt), 32));

        condition = address(new BeaconProxy{salt: salt}(address(this), ""));
        isCondition[condition] = true;

        ZKPassportEligibilityCondition(condition)
            .initialize(address(AUTH), expectedDomain, scope, verifier, defaultMaxValidityPeriod, devModeAllowed, rules);

        emit ConditionDeployed(condition, salt, scope, rules);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

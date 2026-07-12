// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ICyberAgreementRegistry.sol";

/// @title  AgreementSignedCondition - both parties' signatures recorded on the trade agreement
/// @author MetaLeX Labs, Inc.
/// @notice Shared threshold condition. True only once every party's signature is recorded on the
/// settlement agreement in the CyberAgreementRegistry. Trivially satisfied at the acceptance transaction
/// itself (acceptOffer creates the settlement fully signed); useful as a defensive invariant for any
/// flow that composes conditions independently. Silent at posting — no settlement agreement exists yet.
contract AgreementSignedCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidRegistry();

    event RegistryUpdated(address registry);

    ICyberAgreementRegistry public registry;

    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, address _registry) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_registry == address(0)) revert InvalidRegistry();
        registry = ICyberAgreementRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    function updateRegistry(address _registry) external onlyAdmin {
        if (_registry == address(0)) revert InvalidRegistry();
        registry = ICyberAgreementRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    function checkCondition(
        IDealManager,
        bytes4,
        bytes32,
        bytes32 agreementId
    ) external view override returns (bool) {
        // Posting context: the settlement agreement does not exist yet
        if (agreementId == bytes32(0)) return true;
        return registry.allPartiesSigned(agreementId);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

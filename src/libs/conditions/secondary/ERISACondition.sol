// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";
import "../../../interfaces/ICyberAgreementRegistry.sol";
import {Offer, ExemptionPathway} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  ERISACondition - verifies the buyer's ERISA negative attestation (no plan assets)
/// @author MetaLeX Labs, Inc.
/// @notice Shared threshold condition. Reads the buyer's attestation from their party values on the
/// settlement agreement (partyB values, recorded at acceptance) and fails if it is absent. Not applied
/// to Reg S trades — the Reg S pathway already requires a Rule 902(k) non-U.S. buyer via its own
/// conditions, so this condition is silent there.
contract ERISACondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidRegistry();
    error InvalidAttestation();

    event RegistryUpdated(address registry);
    event AttestationValueUpdated(string attestationValue);

    ICyberAgreementRegistry public registry;
    /// @notice Exact party-value string the buyer must record as their ERISA negative attestation
    string public attestationValue;

    uint256[47] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth, address _registry, string memory _attestationValue) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        if (_registry == address(0)) revert InvalidRegistry();
        if (bytes(_attestationValue).length == 0) revert InvalidAttestation();
        registry = ICyberAgreementRegistry(_registry);
        attestationValue = _attestationValue;
        emit RegistryUpdated(_registry);
        emit AttestationValueUpdated(_attestationValue);
    }

    function updateRegistry(address _registry) external onlyAdmin {
        if (_registry == address(0)) revert InvalidRegistry();
        registry = ICyberAgreementRegistry(_registry);
        emit RegistryUpdated(_registry);
    }

    function updateAttestationValue(string memory _attestationValue) external onlyAdmin {
        if (bytes(_attestationValue).length == 0) revert InvalidAttestation();
        attestationValue = _attestationValue;
        emit AttestationValueUpdated(_attestationValue);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        Offer memory offer = dealManager.getOffer(offerId);

        // Silent for Reg S: non-U.S. buyer status is enforced by the pathway's own conditions
        if (offer.exemptionPathway == ExemptionPathway.REGULATION_S) return true;

        (, address buyer,) = _resolveParties(dealManager, offer, agreementId);

        // The attestation lives on the settlement agreement, which only exists from acceptance onward
        if (agreementId == bytes32(0) || buyer == address(0)) return true;

        string[] memory values = registry.getSignerValues(agreementId, buyer);
        bytes32 expected = keccak256(bytes(attestationValue));
        for (uint256 i = 0; i < values.length; i++) {
            if (keccak256(bytes(values[i])) == expected) return true;
        }
        return false;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

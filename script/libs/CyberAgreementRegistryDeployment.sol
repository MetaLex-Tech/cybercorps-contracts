// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CyberAgreementRegistry} from "../../src/CyberAgreementRegistry.sol";
import {CyberAgreementBoundFacet} from "../../src/registry/CyberAgreementBoundFacet.sol";
import {CyberAgreementFacet} from "../../src/registry/CyberAgreementFacet.sol";
import {CyberAgreementViewFacet} from "../../src/registry/CyberAgreementViewFacet.sol";

/// @notice Deploys the registry facets, then a router that uses them.
library CyberAgreementRegistryDeployment {
    function deployRouter() internal returns (CyberAgreementRegistry) {
        return new CyberAgreementRegistry(
            address(new CyberAgreementFacet()),
            address(new CyberAgreementBoundFacet()),
            address(new CyberAgreementViewFacet())
        );
    }

    /// @dev All four contracts use `salt`, so the same code gives the same addresses on each chain.
    function deployRouter(bytes32 salt) internal returns (CyberAgreementRegistry) {
        return new CyberAgreementRegistry{salt: salt}(
            address(new CyberAgreementFacet{salt: salt}()),
            address(new CyberAgreementBoundFacet{salt: salt}()),
            address(new CyberAgreementViewFacet{salt: salt}())
        );
    }
}

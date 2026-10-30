/*    .o.
     .888.
    .8"888.
   .8' `888.
  .88ooo8888.
 .8'     `888.
o88o     o8888o



ooo        ooooo               .             ooooo                  ooooooo  ooooo
`88.       .888'             .o8             `888'                   `8888    d8'
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o



  .oooooo.                .o8                            .oooooo.
 d8P'  `Y8b              "888                           d8P'  `Y8b
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o.
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
             .o..P'                                                                     888
             `Y8P'                                                                     o888o
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published,
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system,
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import {CyberAgreementRegistry} from "./CyberAgreementRegistry.sol";
import {CyberAgreementRegistryLib} from "./libs/CyberAgreementRegistryLib.sol";
import {BorgAuthACL} from "./libs/auth.sol";
import {CyberAgreementBoundFacet} from "./registry/CyberAgreementBoundFacet.sol";
import {CyberAgreementFacet} from "./registry/CyberAgreementFacet.sol";
import {CyberAgreementViewFacet} from "./registry/CyberAgreementViewFacet.sol";
import {CyberAgreementRegistryStorage} from "./storage/CyberAgreementRegistryStorage.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

/// @title CyberAgreementRegistryRouter
/// @notice The implementation behind the registry proxy. It holds initialize, upgrade and auth. It sends every
/// other call to the facet that holds the function. The facets run in the proxy's storage.
/// @dev The facets are fixed for one router. To change a facet, deploy the new facet and a new router that uses
/// it, then upgrade the proxy to the new router.
contract CyberAgreementRegistryRouter is Initializable, UUPSUpgradeable, BorgAuthACL, Proxy {
    // CyberAgreementRegistryStorage keeps its struct in these slots. Keep them so no inherited
    // variable uses them.
    uint256[49] private __reservedForStorageData;

    address private immutable agreementFacet;
    address private immutable boundFacet;
    address private immutable viewFacet;

    error FunctionNotFound(bytes4 selector);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _agreementFacet, address _boundFacet, address _viewFacet) {
        agreementFacet = _agreementFacet;
        boundFacet = _boundFacet;
        viewFacet = _viewFacet;
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        CyberAgreementRegistryStorage.StorageData storage s = CyberAgreementRegistryStorage.getStorageData();
        s.version = "1";
        s.domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(CyberAgreementRegistryLib.NAME)),
                keccak256(bytes(s.version)),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice The facet that holds the function with `selector`. Zero if no facet holds it.
    function facetOf(bytes4 selector) public view returns (address) {
        if (
            selector == CyberAgreementFacet.createTemplate.selector
                || selector == CyberAgreementFacet.createContract.selector
                || selector == CyberAgreementFacet.createStandaloneContractAndSign.selector
                || selector == CyberAgreementFacet.createStandaloneContractAndSignFor.selector
                || selector == CyberAgreementFacet.signContract.selector
                || selector == CyberAgreementFacet.signContractFor.selector
                || selector == CyberAgreementFacet.signContractWithEscrow.selector
                || selector == CyberAgreementFacet.voidContractFor.selector
                || selector == CyberAgreementFacet.finalizeContract.selector
                || selector == CyberAgreementFacet.setDelegation.selector
                || selector == CyberAgreementFacet.revokeDelegation.selector
        ) return agreementFacet;

        if (
            // createBoundContract and createBoundContractAndSignFor are overloaded, so `.selector` cannot name them.
            selector
                    == bytes4(
                        keccak256(
                            "createBoundContract((string,string,string[],string[]),uint256,string[],address[],string[][],uint256)"
                        )
                    )
                || selector
                    == bytes4(
                        keccak256(
                            "createBoundContract((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,(bytes32,bytes)[][])"
                        )
                    )
                || selector
                    == bytes4(
                        keccak256(
                            "createBoundContractAndSignFor((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,bytes)"
                        )
                    )
                || selector
                    == bytes4(
                        keccak256(
                            "createBoundContractAndSignFor((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,(bytes32,bytes)[][],bytes[],bytes)"
                        )
                    ) || selector == CyberAgreementBoundFacet.boundIdsOf.selector
                || selector == CyberAgreementBoundFacet.signContractWithEvidenceFor.selector
                || selector == CyberAgreementBoundFacet.setSignerConditionConfig.selector
                || selector == CyberAgreementBoundFacet.getSignerConditionConfig.selector
        ) {
            return boundFacet;
        }

        if (
            selector == CyberAgreementRegistry.name.selector
                || selector == CyberAgreementRegistry.SIGNATUREDATA_TYPEHASH.selector
                || selector == CyberAgreementRegistry.VOIDSIGNATUREDATA_TYPEHASH.selector
                || selector == CyberAgreementRegistry.BOUND_TEMPLATE_DOMAIN.selector
                || selector == CyberAgreementRegistry.BOUND_AGREEMENT_DOMAIN.selector
                || selector == CyberAgreementRegistry.CONDITIONED_BOUND_AGREEMENT_DOMAIN.selector
                || selector == CyberAgreementRegistry.SIGNATUREWITHEVIDENCEDATA_TYPEHASH.selector
                || selector == CyberAgreementViewFacet.version.selector
                || selector == CyberAgreementViewFacet.DOMAIN_SEPARATOR.selector
                || selector == CyberAgreementViewFacet.templates.selector
                || selector == CyberAgreementViewFacet.agreements.selector
                || selector == CyberAgreementViewFacet.agreementsForParty.selector
                || selector == CyberAgreementViewFacet.delegations.selector
                || selector == CyberAgreementViewFacet.getDelegation.selector
                || selector == CyberAgreementViewFacet.isValidDelegation.selector
                || selector == CyberAgreementViewFacet.isValidDelegate.selector
                || selector == CyberAgreementViewFacet.getParties.selector
                || selector == CyberAgreementViewFacet.hasSigned.selector
                || selector == CyberAgreementViewFacet.getSignatureTimestamp.selector
                || selector == CyberAgreementViewFacet.allPartiesSigned.selector
                || selector == CyberAgreementViewFacet.getContractDetails.selector
                || selector == CyberAgreementViewFacet.getTemplateDetails.selector
                || selector == CyberAgreementViewFacet.getSignerValues.selector
                || selector == CyberAgreementViewFacet.getAgreementsForParty.selector
                || selector == CyberAgreementViewFacet.getVoidRequestedBy.selector
                || selector == CyberAgreementViewFacet.isFinalized.selector
                || selector == CyberAgreementViewFacet.isVoided.selector
                || selector == CyberAgreementViewFacet.getContractJson.selector
                || selector == CyberAgreementViewFacet._bytes32ToString.selector
        ) return viewFacet;

        return address(0);
    }

    function _implementation() internal view override returns (address facet) {
        facet = facetOf(msg.sig);
        if (facet == address(0)) revert FunctionNotFound(msg.sig);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

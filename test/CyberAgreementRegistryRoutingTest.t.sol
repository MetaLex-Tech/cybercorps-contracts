// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CyberAgreementRegistryDeployment} from "../script/libs/CyberAgreementRegistryDeployment.sol";
import {CyberAgreementRegistryRouter} from "../src/CyberAgreementRegistryRouter.sol";
import {Test} from "forge-std/Test.sol";

// Checks the router table against the ABIs in the build output.
contract CyberAgreementRegistryRoutingTest is Test {
    CyberAgreementRegistryRouter router = CyberAgreementRegistryDeployment.deployRouter();

    function testEveryFacetSelectorRoutesToItsFacet() public view {
        address agreementFacet = _routeAll(_selectorsOf("CyberAgreementFacet"));
        address boundFacet = _routeAll(_selectorsOf("CyberAgreementBoundFacet"));
        address viewFacet = _routeAll(_selectorsOf("CyberAgreementViewFacet"));
        assertTrue(agreementFacet != boundFacet && boundFacet != viewFacet && agreementFacet != viewFacet);
    }

    function testNoFacetHoldsARouterSelector() public view {
        string[] memory routerSignatures = _signaturesOf("CyberAgreementRegistryRouter");
        for (uint256 i = 0; i < routerSignatures.length; i++) {
            assertEq(router.facetOf(bytes4(keccak256(bytes(routerSignatures[i])))), address(0), routerSignatures[i]);
        }
    }

    function testEveryLiveSelectorIsServed() public view {
        string[] memory liveSignatures = _liveSignatures();
        string[] memory routerSignatures = _signaturesOf("CyberAgreementRegistryRouter");
        for (uint256 i = 0; i < liveSignatures.length; i++) {
            bool served = router.facetOf(bytes4(keccak256(bytes(liveSignatures[i])))) != address(0);
            for (uint256 j = 0; j < routerSignatures.length && !served; j++) {
                served = keccak256(bytes(liveSignatures[i])) == keccak256(bytes(routerSignatures[j]));
            }
            assertTrue(served, liveSignatures[i]);
        }
    }

    function _routeAll(bytes4[] memory selectors) private view returns (address facet) {
        facet = router.facetOf(selectors[0]);
        assertTrue(facet != address(0));
        for (uint256 i = 0; i < selectors.length; i++) {
            assertEq(router.facetOf(selectors[i]), facet, vm.toString(abi.encodePacked(selectors[i])));
        }
    }

    function _selectorsOf(string memory name) private view returns (bytes4[] memory selectors) {
        string[] memory signatures = _signaturesOf(name);
        selectors = new bytes4[](signatures.length);
        for (uint256 i = 0; i < signatures.length; i++) {
            selectors[i] = bytes4(keccak256(bytes(signatures[i])));
        }
    }

    function _signaturesOf(string memory name) private view returns (string[] memory) {
        string memory artifact = vm.readFile(string.concat("out/", name, ".sol/", name, ".json"));
        return vm.parseJsonKeys(artifact, ".methodIdentifiers");
    }

    // The public ABI of the live registry at 7ce4e1c8, without the removed `closedAgreementValues(bytes32,uint256)`.
    function _liveSignatures() private pure returns (string[] memory s) {
        s = new string[](54);
        s[0] = "_bytes32ToString(bytes32)";
        s[1] = "agreements(bytes32)";
        s[2] = "agreementsForParty(address,uint256)";
        s[3] = "allPartiesSigned(bytes32)";
        s[4] = "AUTH()";
        s[5] = "BOUND_AGREEMENT_DOMAIN()";
        s[6] = "BOUND_TEMPLATE_DOMAIN()";
        s[7] =
            "boundIdsOf(address,(string,string,string[],string[]),uint256,string[],address[],string[][],uint256,(bytes32,bytes)[][])";
        s[8] = "CONDITIONED_BOUND_AGREEMENT_DOMAIN()";
        s[9] = "createBoundContract((string,string,string[],string[]),uint256,string[],address[],string[][],uint256)";
        s[10] =
            "createBoundContract((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,(bytes32,bytes)[][])";
        s[11] =
            "createBoundContractAndSignFor((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,(bytes32,bytes)[][],bytes[],bytes)";
        s[12] =
            "createBoundContractAndSignFor((string,string,string[],string[]),uint256,string[],address[],string[][],uint256,bytes)";
        s[13] = "createContract(bytes32,uint256,string[],address[],string[][],bytes32,address,uint256)";
        s[14] =
            "createStandaloneContractAndSign(string,string,string[],string[],uint256,string[],address[],string[][],uint256,bytes)";
        s[15] =
            "createStandaloneContractAndSignFor(string,string,string[],string[],uint256,string[],address[],string[][],uint256,address,bytes)";
        s[16] = "createTemplate(bytes32,string,string,string[],string[])";
        s[17] = "delegations(address)";
        s[18] = "DOMAIN_SEPARATOR()";
        s[19] = "finalizeContract(bytes32)";
        s[20] = "getAgreementsForParty(address)";
        s[21] = "getContractDetails(bytes32)";
        s[22] = "getContractJson(bytes32)";
        s[23] = "getDelegation(address)";
        s[24] = "getParties(bytes32)";
        s[25] = "getSignatureTimestamp(bytes32,address)";
        s[26] = "getSignerConditionConfig(bytes32)";
        s[27] = "getSignerValues(bytes32,address)";
        s[28] = "getTemplateDetails(bytes32)";
        s[29] = "getVoidRequestedBy(bytes32)";
        s[30] = "hasSigned(bytes32,address)";
        s[31] = "initialize(address)";
        s[32] = "isFinalized(bytes32)";
        s[33] = "isValidDelegate(address,address)";
        s[34] = "isValidDelegation(address)";
        s[35] = "isVoided(bytes32)";
        s[36] = "name()";
        s[37] = "proxiableUUID()";
        s[38] = "revokeDelegation()";
        s[39] = "setDelegation(address,uint256)";
        s[40] = "setSignerConditionConfig(bytes32,bytes)";
        s[41] = "SIGNATUREDATA_TYPEHASH()";
        s[42] = "SIGNATUREWITHEVIDENCEDATA_TYPEHASH()";
        s[43] = "signContract(bytes32,string[],bytes,bool,string)";
        s[44] = "signContractFor(address,bytes32,string[],bytes,bool,string)";
        s[45] = "signContractWithEscrow(address,bytes32,string[],bytes,bool,string)";
        s[46] = "signContractWithEvidenceFor(address,bytes32,string[],bytes[],bytes)";
        s[47] = "templates(bytes32)";
        s[48] = "UPGRADE_INTERFACE_VERSION()";
        s[49] = "upgradeToAndCall(address,bytes)";
        s[50] = "userRoles(address)";
        s[51] = "version()";
        s[52] = "voidContractFor(bytes32,address,bytes)";
        s[53] = "VOIDSIGNATUREDATA_TYPEHASH()";
    }
}

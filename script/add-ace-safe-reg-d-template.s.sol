// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

contract AddAceSafeTemplatesScript is Script {
    string internal constant REG_D_TEMPLATE_ID_STR = "ace_safe_reg_d_v1";
    string internal constant REG_D_TITLE =
        "MetaLeX cyberSAFE jx-neutral-style / Reg D ACE raise v 1";
    string internal constant REG_D_LEGAL_URI =
        "IPFS://bafybeifca22x3r2vkcanj446pe2bcn465rseff6ff3h7lwuaeaw54mjugi";

    string internal constant REG_S_TEMPLATE_ID_STR = "ace_safev1";
    string internal constant REG_S_TITLE =
        "MetaLeX cyberSAFE jx-neutral-style / Reg S ACE raise v 1";
    string internal constant REG_S_LEGAL_URI =
        "IPFS://bafybeibwtm7irbxar76nmmg37uxw6oi5mts7flar4wzndsgfhy4tyq36hq";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        address registry = DeploymentConstants.coreV2(block.chainid).cyberAgreementRegistry;

        console2.log("==== Configs ====");
        console2.log("chainId: %d", block.chainid);
        console2.log("deployer: %s", deployer);
        console2.log("registry: %s", registry);
        console2.log("");

        _createTemplate(
            registry,
            REG_D_TEMPLATE_ID_STR,
            REG_D_TITLE,
            REG_D_LEGAL_URI
        );
        _createTemplate(
            registry,
            REG_S_TEMPLATE_ID_STR,
            REG_S_TITLE,
            REG_S_LEGAL_URI
        );

        vm.stopBroadcast();
    }

    function _createTemplate(
        address registry,
        string memory templateIdStr,
        string memory title,
        string memory legalUri
    ) internal {
        bytes32 templateId = bytes32(bytes(templateIdStr));
        string[] memory globalFields = _globalFields();
        string[] memory partyFields = _partyFields();

        console2.log("==== Creating template ====");
        console2.log("templateIdStr: %s", templateIdStr);
        console2.log("title: %s", title);
        console2.log("legalUri: %s", legalUri);

        CyberAgreementRegistry(registry).createTemplate(
            templateId,
            title,
            legalUri,
            globalFields,
            partyFields
        );

        console2.log("templateId:");
        console2.logBytes32(templateId);
        console2.log("");
    }

    function _globalFields() internal pure returns (string[] memory fields) {
        fields = new string[](5);
        fields[0] = "purchaseAmount";
        fields[1] = "postMoneyValuationCap";
        fields[2] = "expirationTime";
        fields[3] = "governingJurisdiction";
        fields[4] = "disputeResolution";
    }

    function _partyFields() internal pure returns (string[] memory fields) {
        fields = new string[](5);
        fields[0] = "name";
        fields[1] = "evmAddress";
        fields[2] = "contactDetails";
        fields[3] = "investorType";
        fields[4] = "investorJurisdiction";
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

contract AddCyberstockTemplateScript is Script {
    // TODO update before production
    string internal constant TEMPLATE_ID_STR = "mlx_cyberstock_reg_d_v1_0_dev1";
    // TODO replace with CID assigned at pinning of cyberSTOCK Purchase Agreement v6
    string internal constant LEGAL_URI = "IPFS://bafybeid4xxgesjbxpdwx3dmcxlupzscurpnh6c3k7lukhzt2fsfkbxjr34";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        address registry = DeploymentConstants.coreV2(block.chainid).cyberAgreementRegistry;
        bytes32 templateId = bytes32(bytes(TEMPLATE_ID_STR));

        console2.log("==== Configs ====");
        console2.log("chainId: %d", block.chainid);
        console2.log("deployer: %s", deployer);
        console2.log("TEMPLATE_ID_STR: %s", TEMPLATE_ID_STR);
        console2.log("LEGAL_URI: %s", LEGAL_URI);
        console2.log("");

        CyberAgreementRegistry(registry).createTemplate(
            templateId,
            TEMPLATE_ID_STR,
            LEGAL_URI,
            _globalFields(),
            _partyFields()
        );

        vm.stopBroadcast();

        console2.log("==== Deployed ====");
        console2.log("templateId:");
        console2.logBytes32(templateId);
        console2.log("");
    }

    function _globalFields() internal pure returns (string[] memory fields) {
        fields = new string[](4);
        fields[0] = "purchasePricePerShare";
        fields[1] = "numTokenizedShares";
        fields[2] = "governingJurisdiction";
        fields[3] = "disputeResolution";
    }

    function _partyFields() internal pure returns (string[] memory fields) {
        fields = new string[](5);
        fields[0] = "name";
        fields[1] = "evmAddress";
        fields[2] = "contactDetails";
        fields[3] = "entityType";
        fields[4] = "entityJurisdiction";
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {ERC1967ProxyLib} from "../test/libs/ERC1967ProxyLib.sol";

contract AcceptUpgradeIssuanceManagerScript is Script {
    using ERC1967ProxyLib for address;

    function run(address corpAddr) public {
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants.coreV2(block.chainid);

        address cyberCorpFactoryAddr = vm.envOr("CYBERCORP_FACTORY", deployment.cyberCorpFactory);
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(
            CyberCorpFactory(cyberCorpFactoryAddr).issuanceManagerFactory()
        );

        IssuanceManager im = IssuanceManager(CyberCorp(corpAddr).issuanceManager());
        address currentImplAddr = address(im).getErc1967Implementation();
        address refImplAddr = imFactory.getRefImplementation();

        console2.log("==== Configs ====");
        console2.log("Current implementation: %s, DEPLOY_VERSION: %s", currentImplAddr, im.DEPLOY_VERSION());
        console2.log("Reference implementation: %s, DEPLOY_VERSION: %s", refImplAddr, IssuanceManager(refImplAddr).DEPLOY_VERSION());
        console2.log("");

        vm.assertNotEq(
            currentImplAddr,
            refImplAddr,
            "Already at reference implementation, no need to upgrade"
        );

        vm.startBroadcast(vm.envUint("PRIVATE_KEY_MAIN"));

        im.upgradeToAndCall(refImplAddr, "");
        console2.log("CyberCorp: %s accepted IssuanceManager upgrade to: %s", corpAddr, refImplAddr);

        vm.stopBroadcast();
    }
}

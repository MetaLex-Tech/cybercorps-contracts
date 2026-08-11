// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IShareClassTermsController} from "../src/interfaces/IShareClassTermsController.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";
import {ICertificateExtension} from "../src/storage/extensions/ICertificateExtension.sol";
import {ERC1967ProxyLib} from "../test/libs/ERC1967ProxyLib.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {Script, console2} from "forge-std/Script.sol";

contract AcceptUpgradeIssuanceManagerScript is Script {
    using ERC1967ProxyLib for address;

    function run(address corpAddr) public {
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants.coreV2(block.chainid);

        address cyberCorpFactoryAddr = vm.envOr("CYBERCORP_FACTORY", deployment.cyberCorpFactory);
        IssuanceManagerFactory imFactory =
            IssuanceManagerFactory(CyberCorpFactory(cyberCorpFactoryAddr).issuanceManagerFactory());

        IssuanceManager im = IssuanceManager(CyberCorp(corpAddr).issuanceManager());
        address currentImplAddr = address(im).getErc1967Implementation();
        address refImplAddr = imFactory.getRefImplementation();

        console2.log("==== Configs ====");
        console2.log("Current implementation: %s, DEPLOY_VERSION: %s", currentImplAddr, im.DEPLOY_VERSION());
        console2.log(
            "Reference implementation: %s, DEPLOY_VERSION: %s",
            refImplAddr,
            IssuanceManager(refImplAddr).DEPLOY_VERSION()
        );
        console2.log("");

        vm.assertNotEq(currentImplAddr, refImplAddr, "Already at reference implementation, no need to upgrade");

        // 4.2 fails closed on legacy SHARE printers: after the upgrade, any printer whose
        // extension advertises SHARE but is not a class-terms controller has issuance,
        // assignment, and scrip operations reverting until it is migrated. Refuse the bare
        // acceptance for such corps — the manager upgrade and the per-printer migrations must
        // land in one transaction via upgrade-and-migrate-share-class-terms.s.sol, whose
        // upgradeToAndCall payload rolls everything back if any migration fails.
        bytes32 shareType = keccak256("SHARE");
        for (uint256 i = 0;; i++) {
            address printer;
            try im.printers(i) returns (address p) {
                printer = p;
            } catch {
                break;
            }
            address ext = ILedgerEntryToken(printer).getExtension(0);
            if (ext == address(0) || ext.code.length == 0) continue;
            (bool ok, bytes memory ret) =
                ext.staticcall(abi.encodeCall(ICertificateExtension.supportsExtensionType, (shareType)));
            if (!ok || ret.length < 32 || !abi.decode(ret, (bool))) continue;
            (bool isController,) =
                ext.staticcall(abi.encodeCall(IShareClassTermsController.getClassTerms, (printer)));
            vm.assertTrue(
                isController,
                string.concat(
                    "Legacy SHARE printer without class-terms controller detected; use "
                    "upgrade-and-migrate-share-class-terms.s.sol for the atomic upgrade+migration instead: ",
                    vm.toString(printer)
                )
            );
        }

        vm.startBroadcast(vm.envUint("PRIVATE_KEY_MAIN"));

        im.upgradeToAndCall(refImplAddr, "");
        console2.log("CyberCorp: %s accepted IssuanceManager upgrade to: %s", corpAddr, refImplAddr);

        vm.assertEq(im.DEPLOY_VERSION(), "4.2", "IssuanceManager version mismatch");

        vm.stopBroadcast();
    }
}

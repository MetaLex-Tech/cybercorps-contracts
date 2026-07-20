// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";

/// @notice Upgrades an existing ShareExtension proxy with the P2 terms extractor.
/// @dev Run without `--broadcast` first. Broadcasting requires the extension
///      proxy's BorgAuth owner and an explicit SHARE_EXTENSION_PROXY.
contract UpgradeShareExtensionScript is Script {
    bytes32 internal constant UPGRADE_SALT =
        keccak256("MetaLexCyberCorp.ShareExtension.P2.v1");

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        address proxyAddress = vm.envAddress("SHARE_EXTENSION_PROXY");
        ShareExtension proxy = ShareExtension(proxyAddress);
        BorgAuth auth = BorgAuth(address(proxy.AUTH()));

        if (auth.userRoles(deployer) < auth.OWNER_ROLE()) {
            revert("Deployer is not ShareExtension AUTH owner");
        }

        vm.startBroadcast(privateKey);
        address implementation = address(
            new ShareExtension{salt: UPGRADE_SALT}()
        );
        proxy.upgradeToAndCall(implementation, "");
        vm.stopBroadcast();

        vm.assertTrue(
            proxy.supportsExtensionType(keccak256("SHARE")),
            "Upgraded extension does not advertise SHARE"
        );
        console2.log("ShareExtension proxy:", proxyAddress);
        console2.log("ShareExtension implementation:", implementation);
    }
}

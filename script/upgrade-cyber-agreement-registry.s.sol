// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract UpgradeCyberAgreementRegistryScript is Script {
    function run() public {
        bytes32 salt = bytes32(
            keccak256("MetaLex.CyberAgreementRegistry.UpgradeV3.3.0")
        );
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address registryProxy = vm.envOr(
            "CYBER_AGREEMENT_REGISTRY",
            0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134
        );

        address deployer = vm.addr(deployerPrivateKey);
        console2.log("deployer: %s", deployer);
        console2.log("registry proxy: %s", registryProxy);

        CyberAgreementRegistry registry = CyberAgreementRegistry(registryProxy);
        BorgAuth auth = BorgAuth(registry.AUTH());
        console2.log("auth: %s", address(auth));

        uint256 role = auth.userRoles(deployer);
        console2.log("upgrader role: %s", role);
        if (role < auth.OWNER_ROLE()) {
            revert("Deployer is not AUTH owner");
        }

        vm.startBroadcast(deployerPrivateKey);

        address newRegistryImpl = address(
            new CyberAgreementRegistry{salt: salt}()
        );
        console2.log(
            "New CyberAgreementRegistry implementation: %s",
            newRegistryImpl
        );

        registry.upgradeToAndCall(newRegistryImpl, "");
        console2.log(
            "CyberAgreementRegistry upgraded (proxy): %s",
            registryProxy
        );

        vm.stopBroadcast();
    }
}

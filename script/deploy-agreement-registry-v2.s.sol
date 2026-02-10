// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {CyberAgreementRegistryV2} from "../src/CyberAgreementRegistryV2.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAgreementRegistryV2 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        bytes32 salt = bytes32(keccak256("CyberAgreementRegistryV2Deploy001"));

        BorgAuth auth = new BorgAuth{salt: salt}(deployerAddress);

        address implementation = address(
            new CyberAgreementRegistryV2{salt: salt}()
        );

        address proxy = address(
            new ERC1967Proxy{salt: salt}(
                implementation,
                abi.encodeWithSelector(
                    CyberAgreementRegistryV2.initialize.selector,
                    address(auth)
                )
            )
        );

        vm.stopBroadcast();

        console.log(
            "CyberAgreementRegistryV2 Implementation: `%s`",
            implementation
        );
        console.log("CyberAgreementRegistryV2 Proxy: `%s`", proxy);
        console.log("BorgAuth: `%s`", address(auth));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ACESAFEExtension} from "../src/storage/extensions/ACESAFEExtension.sol";

contract DeployACESAFEExtensionScript is Script {
    function run() public returns (address aceSafeExtension) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);

        bytes32 salt = bytes32(
            keccak256("MetaLexCyberCorpLaunchV2.2-ACESAFEExtension")
        );
        BorgAuth auth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);

        aceSafeExtension = address(
            new ERC1967Proxy{salt: salt}(
                address(new ACESAFEExtension{salt: salt}()),
                abi.encodeWithSelector(
                    ACESAFEExtension.initialize.selector,
                    address(auth)
                )
            )
        );

        console.log("ACESAFEExtension:", aceSafeExtension);

        vm.stopBroadcast();
    }
}

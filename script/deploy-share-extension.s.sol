// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";

contract DeployShareExtensionScript is Script {
    bytes32 internal constant DEFAULT_SALT = keccak256("MetaLexCyberCorp-ShareExtension");

    function run() external returns (address implementation, address proxy) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address auth = vm.envAddress("AUTH_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        implementation = address(new ShareExtension{salt: DEFAULT_SALT}());
        proxy = address(
            new ERC1967Proxy{salt: DEFAULT_SALT}(
                implementation,
                abi.encodeWithSelector(ShareExtension.initialize.selector, auth)
            )
        );

        vm.stopBroadcast();

        console.log("ShareExtension implementation:", implementation);
        console.log("ShareExtension proxy:", proxy);
        console.log("AUTH_ADDRESS:", auth);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SAFEExtension} from "../src/storage/extensions/SAFEExtension.sol";
import {SAFTEExtensionV2} from "../src/storage/extensions/SAFTEExtensionV2.sol";
import {SAFTExtensionV2} from "../src/storage/extensions/SAFTExtensionV2.sol";
import {TokenWarrantExtensionV2} from "../src/storage/extensions/TokenWarrantExtensionV2.sol";

contract BaseScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);

        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.2-Extensions"));
        BorgAuth auth = BorgAuth(0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01);

        address safeExtension = address(
            new ERC1967Proxy{salt: salt}(
                address(new SAFEExtension{salt: salt}()),
                abi.encodeWithSelector(SAFEExtension.initialize.selector, address(auth))
            )
        );

        address safteExtensionV2 = address(
            new ERC1967Proxy{salt: salt}(
                address(new SAFTExtensionV2{salt: salt}()),
                abi.encodeWithSelector(SAFTExtensionV2.initialize.selector, address(auth))
            )
        );

        address safteExtensionV2Long = address(
            new ERC1967Proxy{salt: salt}(
                address(new SAFTEExtensionV2{salt: salt}()),
                abi.encodeWithSelector(SAFTEExtensionV2.initialize.selector, address(auth))
            )
        );

        address tokenWarrantExtensionV2 = address(
            new ERC1967Proxy{salt: salt}(
                address(new TokenWarrantExtensionV2{salt: salt}()),
                abi.encodeWithSelector(TokenWarrantExtensionV2.initialize.selector, address(auth))
            )
        );

        console.log("SAFEExtension: ", safeExtension);
        console.log("SAFTExtensionV2: ", safteExtensionV2);
        console.log("SAFTEExtensionV2: ", safteExtensionV2Long);
        console.log("TokenWarrantExtensionV2: ", tokenWarrantExtensionV2);
    }
}

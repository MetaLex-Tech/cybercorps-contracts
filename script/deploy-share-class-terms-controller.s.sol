// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";

import {BorgAuth} from "../src/libs/auth.sol";
import {ShareClassTermsController} from "../src/storage/extensions/ShareClassTermsController.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";

/// @notice Deploys the externalized P2 class-terms controller as a UUPS proxy.
/// @dev The existing ShareExtension remains the renderer/parser. New and
///      migrated share printers point at this facade instead.
contract DeployShareClassTermsControllerScript is Script {
    bytes32 internal constant IMPLEMENTATION_SALT = keccak256("MetaLexCyberCorp.ShareClassTermsController.1");
    bytes32 internal constant PROXY_SALT = keccak256("MetaLexCyberCorp.ShareClassTermsController.Proxy.1");

    function run() external returns (address controllerProxy) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        address rendererAddress = vm.envAddress("SHARE_EXTENSION_RENDERER");
        ShareExtension renderer = ShareExtension(rendererAddress);
        address authAddress = address(renderer.AUTH());
        BorgAuth auth = BorgAuth(authAddress);

        if (auth.userRoles(deployer) < auth.OWNER_ROLE()) {
            revert("Deployer is not ShareExtension AUTH owner");
        }

        vm.startBroadcast(privateKey);
        address implementation = address(new ShareClassTermsController{salt: IMPLEMENTATION_SALT}());
        controllerProxy = address(
            new ERC1967Proxy{salt: PROXY_SALT}(
                implementation, abi.encodeCall(ShareClassTermsController.initialize, (authAddress, rendererAddress))
            )
        );
        vm.stopBroadcast();

        ShareClassTermsController controller = ShareClassTermsController(controllerProxy);
        vm.assertEq(controller.renderer(), rendererAddress, "Controller renderer mismatch");
        vm.assertTrue(controller.supportsExtensionType(keccak256("SHARE")), "Controller does not advertise SHARE");

        console2.log("ShareClassTermsController proxy:", controllerProxy);
        console2.log("ShareClassTermsController implementation:", implementation);
        console2.log("ShareExtension renderer:", rendererAddress);
    }
}

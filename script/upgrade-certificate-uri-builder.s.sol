// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {BorgAuth} from "../src/libs/auth.sol";

import {ERC1967ProxyLib} from "../test/libs/ERC1967ProxyLib.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

/// @notice Refresh the full certificate URI rendering path with the current sources.
/// @dev Uses PRIVATE_KEY_MAIN and the chain's core V2 proxy, overridden by URI_BUILDER.
///      Dry run: forge script script/upgrade-certificate-uri-builder.s.sol:UpgradeCertificateUriBuilder --rpc-url <RPC_URL>
///      Add --broadcast --verify to deploy and upgrade.
contract UpgradeCertificateUriBuilder is Script {
    using ERC1967ProxyLib for address;

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        address proxy = vm.envOr("URI_BUILDER", address(0));
        if (proxy == address(0)) {
            proxy = DeploymentConstants.coreV2(block.chainid).uriBuilder;
        }
        require(proxy.code.length > 0, "URI_BUILDER has no code");

        CertificateUriBuilder uriBuilder = CertificateUriBuilder(proxy);
        BorgAuth auth = uriBuilder.AUTH();
        auth.onlyRole(auth.OWNER_ROLE(), deployer);

        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("CertificateUriBuilder proxy:", proxy);
        console.log("Old implementation:", proxy.getErc1967Implementation());
        console.log("Old image builder:", uriBuilder.imageBuilder());

        vm.startBroadcast(privateKey);

        // Fresh CREATE deployments allow rerunning without fixed CREATE2 salt collisions.
        address imageBuilder = address(new CertificateImageBuilderContract());
        address implementation = address(new CertificateUriBuilder());

        // Switch both parts of the rendering path in the same transaction.
        uriBuilder.upgradeToAndCall(
            implementation, abi.encodeCall(CertificateUriBuilder.setImageBuilder, (imageBuilder))
        );

        vm.stopBroadcast();

        require(proxy.getErc1967Implementation() == implementation, "Implementation update failed");
        require(uriBuilder.imageBuilder() == imageBuilder, "Image builder update failed");
        require(address(uriBuilder.AUTH()) == address(auth), "AUTH changed unexpectedly");

        console.log("New implementation:", implementation);
        console.log("New image builder:", imageBuilder);
    }
}

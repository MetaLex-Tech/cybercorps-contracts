// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateImageBuilderContract} from "../src/CertificateImageBuilderContract.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {DeploymentUtils} from "./libs/DeploymentUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ShareExtension} from "../src/storage/extensions/ShareExtension.sol";
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";

/// @notice Install the current certificate renderers and the Share extensions that feed them.
/// @dev The URI builder calls the image builder through one entry point, and that entry point can change
///      between releases. So one Safe call switches both parts with `upgradeToAndCall`. The Safe sets the
///      image builder alone only when the URI implementation already has the current code.
///      The image shows the series name that a Share extension gives through `seriesNameOf`. So the same
///      Safe batch also upgrades the Share extension proxies. A Safe batch runs as one transaction.
///      Configure RPC, sender and signing through Forge's normal options. No script-specific env vars.
///      Forge links/deploys CertificateImageContentBuilder using the configured wallet.
contract UpgradeCertificateFooterScript is DeploymentScript {
    function run() external {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        DeploymentConstants.ExtensionDeployment memory ext = DeploymentConstants.extensions(block.chainid);
        runWithArgs(block.chainid, core.uriBuilder, ext.shareExtension, ext.shareExtensionV3, core.metalexSafe,
            batchPath(block.chainid, core.uriBuilder));
    }

    function batchPath(uint256 chainId, address proxy) public pure returns (string memory) {
        return string.concat("script/res/gnosis-batch-certificate-footer-", vm.toString(chainId),
            "-", vm.toString(proxy), ".unverified.json");
    }

    /// @notice Optional wrapper entrypoint; expected chain and output path are ordinary Forge --sig arguments.
    function runForChain(uint256 expectedChain, string memory path) external {
        if (expectedChain != block.chainid) revert ChainIdMismatch(expectedChain, block.chainid);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        DeploymentConstants.ExtensionDeployment memory ext = DeploymentConstants.extensions(block.chainid);
        runWithArgs(expectedChain, core.uriBuilder, ext.shareExtension, ext.shareExtensionV3, core.metalexSafe, path);
    }

    /// @notice Explicit targets for local rehearsals or separately inventoried custom proxies.
    /// @param shareExtension The ShareExtension proxy to upgrade, or zero to leave it out
    /// @param shareExtensionV3 The ShareExtensionV3 proxy to upgrade, or zero to leave it out
    function runWithArgs(
        uint256 chainId,
        address proxy,
        address shareExtension,
        address shareExtensionV3,
        address ownerSafe,
        string memory path
    ) public returns (GnosisTransaction[] memory) {
        if (chainId != block.chainid) revert ChainIdMismatch(chainId, block.chainid);
        safe = ownerSafe;
        delete safeTxs;
        address oldImplementation = _requireSafeOwnedProxy(proxy, ownerSafe, "URI_BUILDER");
        CertificateUriBuilder builder = CertificateUriBuilder(proxy);
        address auth = address(builder.AUTH());
        address oldImage = builder.imageBuilder();
        console2.log("URI proxy:", proxy);
        console2.log("Previous URI implementation:", oldImplementation);
        console2.log("Previous image builder:", oldImage);

        address image = _deployIfChanged(oldImage, type(CertificateImageBuilderContract).creationCode, "image builder");
        address implementation =
            _deployIfChanged(oldImplementation, type(CertificateUriBuilder).creationCode, "URI implementation");
        bytes memory imageCall = abi.encodeCall(CertificateUriBuilder.setImageBuilder, (image));
        // Always require multisig execution, even when the deployment key is also an owner.
        if (implementation != oldImplementation) {
            _queue(proxy, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, imageCall)));
        } else if (image != oldImage) {
            _queue(proxy, imageCall);
        }
        _upgradeIfChanged(shareExtension, ownerSafe, type(ShareExtension).creationCode, "ShareExtension");
        _upgradeIfChanged(shareExtensionV3, ownerSafe, type(ShareExtensionV3).creationCode, "ShareExtensionV3");

        finish("[renderer Safe batch]", path);
        require(implementationOf(proxy) == implementation, "URI implementation update failed");
        require(address(builder.AUTH()) == auth, "AUTH changed");
        require(builder.imageBuilder() == image, "Image builder update failed");
        if (safeTxs.length == 0) vm.writeFile(path, DeploymentUtils.formatSafeTxJson(safeTxs, chainId));
        console2.log("Verified URI implementation (simulation):", implementation);
        console2.log("Verified image builder (simulation):", image);
        console2.log("Batch output (verify deployment receipts before Safe import):", path);
        return safeTxs;
    }

    /// @param label The proxy name in the revert messages
    /// @return implementation The current implementation of `proxy`
    function _requireSafeOwnedProxy(address proxy, address ownerSafe, string memory label)
        private
        view
        returns (address implementation)
    {
        require(proxy.code.length > 0, string.concat(label, " has no code"));
        implementation = implementationOf(proxy);
        require(implementation.code.length > 0, string.concat(label, " is not an implementation proxy"));
        address auth = address(CertificateUriBuilder(proxy).AUTH());
        require(ownerSafe != address(0) && DeploymentUtils.hasOwnerRole(auth, ownerSafe),
            string.concat("Safe does not own ", label));
    }

    /// @notice Deploys `creationCode` unless `current` already has the same code.
    /// @dev The step deploys a copy only in the simulation and compares the runtime code. The comparison masks
    ///      the contract's own address, which a UUPS implementation keeps as an immutable.
    function _deployIfChanged(address current, bytes memory creationCode, string memory name)
        private
        returns (address)
    {
        if (_sameCode(current, _create(creationCode, name))) return current;
        vm.broadcast(msg.sender); // Forge's --sender; the matching wallet signs outside this script.
        address deployed = _create(creationCode, name);
        console2.log(string.concat("Deployed new ", name, ":"), deployed);
        return deployed;
    }

    /// @notice Queues a Safe upgrade of `proxy` when the current source differs from its implementation.
    function _upgradeIfChanged(address proxy, address ownerSafe, bytes memory creationCode, string memory name)
        private
    {
        if (proxy == address(0)) return;
        address current = _requireSafeOwnedProxy(proxy, ownerSafe, name);
        address implementation = _deployIfChanged(current, creationCode, name);
        if (implementation != current) {
            _queue(proxy, abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (implementation, "")));
        }
    }

    function _queue(address to, bytes memory data) private {
        safeTxs.push(GnosisTransaction({to: to, value: 0, data: data}));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ACESAFEExtensionV3} from "../src/storage/extensions/ACESAFEExtensionV3.sol";
import {FundInterestExtensionV3} from "../src/storage/extensions/FundInterestExtensionV3.sol";
import {SAFEExtensionV3} from "../src/storage/extensions/SAFEExtensionV3.sol";
import {SAFTEExtensionV3} from "../src/storage/extensions/SAFTEExtensionV3.sol";
import {SAFTExtensionV3} from "../src/storage/extensions/SAFTExtensionV3.sol";
import {ShareExtensionV3} from "../src/storage/extensions/ShareExtensionV3.sol";
import {TokenWarrantExtensionV3} from "../src/storage/extensions/TokenWarrantExtensionV3.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console2} from "forge-std/Script.sol";

/// @notice Deploys a new proxy for each extension that renders the whole certificate.
/// @dev Do not upgrade a V1 or V2 proxy to these implementations. A v4 printer on that proxy
///      then reverts in `tokenURI`. Forge deploys and links ShareCertDataLayerLib for ShareExtensionV3.
contract DeployExtensionsV3Script is Script {
    error ProxyAddressMismatch(address expected, address actual);

    function run() public returns (DeploymentConstants.ExtensionDeployment memory deployed) {
        return runWithArgs(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-ExtensionsV3",
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey

            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            "CyberCorpV5-ExtensionsV3",
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    function runWithArgs(
        uint256 chainId,
        string memory saltStr,
        uint256 deployerPrivateKey
    ) public returns (DeploymentConstants.ExtensionDeployment memory deployed) {
        address deployerAddress = vm.addr(deployerPrivateKey);

        bytes32 salt = keccak256(bytes(saltStr));

        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants.coreV2(chainId);

        console2.log("==== Configs ====");
        console2.log("chainId: %d", chainId);
        console2.log("salt string: %s", saltStr);
        console2.log("deployer: %s", deployerAddress);
        console2.log("AUTH:", deployment.auth);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);
        deployed.aceSafeExtensionV3 =
            _deployProxy(address(new ACESAFEExtensionV3{salt: salt}()), deployment.auth, salt);
        deployed.safeExtensionV3 = _deployProxy(address(new SAFEExtensionV3{salt: salt}()), deployment.auth, salt);
        deployed.saftExtensionV3 = _deployProxy(address(new SAFTExtensionV3{salt: salt}()), deployment.auth, salt);
        deployed.safteExtensionV3 =
            _deployProxy(address(new SAFTEExtensionV3{salt: salt}()), deployment.auth, salt);
        deployed.tokenWarrantExtensionV3 =
            _deployProxy(address(new TokenWarrantExtensionV3{salt: salt}()), deployment.auth, salt);
        deployed.shareExtensionV3 =
            _deployProxy(address(new ShareExtensionV3{salt: salt}()), deployment.auth, salt);
        deployed.fundInterestExtensionV3 =
            _deployProxy(address(new FundInterestExtensionV3{salt: salt}()), deployment.auth, salt);
        vm.stopBroadcast();

        // Forge simulates the whole run before it broadcasts, so a mismatch here sends no transaction.
        DeploymentConstants.ExtensionDeployment memory expected = DeploymentConstants.extensions(chainId);
        _requireMatch(expected.aceSafeExtensionV3, deployed.aceSafeExtensionV3);
        _requireMatch(expected.safeExtensionV3, deployed.safeExtensionV3);
        _requireMatch(expected.saftExtensionV3, deployed.saftExtensionV3);
        _requireMatch(expected.safteExtensionV3, deployed.safteExtensionV3);
        _requireMatch(expected.tokenWarrantExtensionV3, deployed.tokenWarrantExtensionV3);
        _requireMatch(expected.shareExtensionV3, deployed.shareExtensionV3);
        _requireMatch(expected.fundInterestExtensionV3, deployed.fundInterestExtensionV3);

        console2.log("==== Deployed ====");
        console2.log("ACESAFEExtensionV3:", deployed.aceSafeExtensionV3);
        console2.log("SAFEExtensionV3:", deployed.safeExtensionV3);
        console2.log("SAFTExtensionV3:", deployed.saftExtensionV3);
        console2.log("SAFTEExtensionV3:", deployed.safteExtensionV3);
        console2.log("TokenWarrantExtensionV3:", deployed.tokenWarrantExtensionV3);
        console2.log("ShareExtensionV3:", deployed.shareExtensionV3);
        console2.log("FundInterestExtensionV3:", deployed.fundInterestExtensionV3);
        console2.log("");
    }

    function _deployProxy(address implementation, address auth, bytes32 salt) internal returns (address) {
        return address(
            new ERC1967Proxy{salt: salt}(implementation, abi.encodeWithSignature("initialize(address)", auth))
        );
    }

    /// @dev A zero `expected` means DeploymentConstants does not know the proxy yet, so no check applies.
    function _requireMatch(address expected, address actual) internal pure {
        if (expected != address(0) && actual != expected) revert ProxyAddressMismatch(expected, actual);
    }
}

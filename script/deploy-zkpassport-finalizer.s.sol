// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ZKPassportFinalizer} from "../src/ZKPassportFinalizer.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Deploys the ZKPassportFinalizer proxy, or upgrades it to the current code.
/// @dev The domain, the scope and dev mode go into `initialize` only, so an existing proxy keeps its values.
///      A passport id depends on the domain and the scope.
///      A testnet gets dev mode, so a mock passport can sign there. A production chain does not.
///      A chain with no ZKPassport verifier reverts at `initialize`.
///      Add the new proxy address to DeploymentConstants afterwards.
///      See `DeploymentScript` for the checks and for who sends each call.
contract DeployZKPassportFinalizerScript is DeploymentScript {
    function run() public {
        runAndExecute(
            // Production
            DeploymentConstants.ETH,
            "CyberCorpV5-ZKPassportFinalizerV1.0.1", // proxySaltStr
            DeploymentConstants.zkpassportDomain(DeploymentConstants.ETH),
            DeploymentConstants.ZKPASSPORT_SCOPE,
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
//            // Staging
//            DeploymentConstants.ETH_SEPOLIA,
//            "CyberCorpV5-ZKPassportFinalizerV1.0.1", // proxySaltStr
//            DeploymentConstants.zkpassportDomain(DeploymentConstants.ETH_SEPOLIA),
//            DeploymentConstants.ZKPASSPORT_SCOPE,
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Deploys, then writes the Safe batch for the calls that the deployer cannot send.
    function runAndExecute(
        uint256 chainId,
        string memory proxySaltStr,
        string memory expectedDomain,
        string memory expectedScope,
        uint256 deployerPrivateKey
    ) public {
        runWithArgs(chainId, proxySaltStr, expectedDomain, expectedScope, deployerPrivateKey);
        finish(
            "[Safe batch]",
            string.concat("script/res/gnosis-batch-deploy-zkpassport-finalizer-", vm.toString(chainId), ".json")
        );
    }

    function runWithArgs(
        uint256 chainId,
        string memory proxySaltStr,
        string memory expectedDomain,
        string memory expectedScope,
        uint256 deployerPrivateKey
    ) public returns (GnosisTransaction[] memory) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);
        bool devMode = DeploymentConstants.isTestnet(chainId);

        console2.log("==== DeployZKPassportFinalizerScript Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] proxy salt string: %s", proxySaltStr);
        console2.log("[config] AUTH:", core.auth);
        console2.log("[config] CyberAgreementRegistry:", core.cyberAgreementRegistry);
        console2.log("[config] ZKPassport verifier:", core.zkpassportVerifier);
        console2.log("[config] expected domain (new proxy only): %s", expectedDomain);
        console2.log("[config] expected scope (new proxy only): %s", expectedScope);
        console2.log("[config] dev mode (new proxy only):", devMode);
        console2.log("");

        (address finalizer,) = upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "ZKPassportFinalizer",
            core.zkpassportFinalizer,
            type(ZKPassportFinalizer).creationCode,
            abi.encodeCall(
                ZKPassportFinalizer.initialize,
                (core.auth, core.cyberAgreementRegistry, core.zkpassportVerifier, expectedDomain, expectedScope, devMode)
            )
        );

        console2.log("==== DeployZKPassportFinalizerScript Deployed ====");
        console2.log("ZKPassportFinalizer:", finalizer);
        console2.log(" ");
        return safeTxs;
    }
}

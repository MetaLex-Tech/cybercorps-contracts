// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {PassportFinalizer} from "../src/PassportFinalizer.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Deploys the PassportFinalizer proxy, or upgrades it to the current code.
/// @dev The domain and the scope go into `initialize` only. A passport id depends on them, so an existing proxy
///      keeps its values. A chain with no ZKPassport verifier reverts at `initialize`.
///      Add the new proxy address to DeploymentConstants afterwards.
///      See `DeploymentScript` for the checks and for who sends each call.
contract DeployPassportFinalizerScript is DeploymentScript {
    function run() public {
        runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            "CyberCorpV5-PassportFinalizerV1.0.0", // proxySaltStr
//            "app.metalex.tech", // TODO: confirm the webapp domain that requests the proof
//            "cyberagreement-passport", // TODO: confirm the scope. See specs/analysis/cyberagreement-zkpassport-gate.md
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
            // Staging
            DeploymentConstants.ETH_SEPOLIA,
            "CyberCorpV5-PassportFinalizerV1.0.0", // proxySaltStr
            "preview.cybercorps.metalex.tech", // TODO: confirm the webapp domain that requests the proof
            "cyberagreement-passport", // TODO: confirm the scope. See specs/analysis/cyberagreement-zkpassport-gate.md
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
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
            string.concat("script/res/gnosis-batch-deploy-passport-finalizer-", vm.toString(chainId), ".json")
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

        console2.log("==== DeployPassportFinalizerScript Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] proxy salt string: %s", proxySaltStr);
        console2.log("[config] AUTH:", core.auth);
        console2.log("[config] CyberAgreementRegistry:", core.cyberAgreementRegistry);
        console2.log("[config] ZKPassport verifier:", core.zkpassportVerifier);
        console2.log("[config] expected domain (new proxy only): %s", expectedDomain);
        console2.log("[config] expected scope (new proxy only): %s", expectedScope);
        console2.log("");

        (address finalizer,) = upgradeOrDeployProxyIfDiffImpl(
            core.auth,
            proxySaltStr,
            "PassportFinalizer",
            core.passportFinalizer,
            type(PassportFinalizer).creationCode,
            abi.encodeCall(
                PassportFinalizer.initialize,
                (core.auth, core.cyberAgreementRegistry, core.zkpassportVerifier, expectedDomain, expectedScope)
            )
        );

        console2.log("==== DeployPassportFinalizerScript Deployed ====");
        console2.log("PassportFinalizer:", finalizer);
        console2.log(" ");
        return safeTxs;
    }
}

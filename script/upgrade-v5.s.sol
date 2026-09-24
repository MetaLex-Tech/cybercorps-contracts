// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberCorp} from "../src/CyberCorp.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";

import {DeployExtensionsV2Script} from "./deploy-extensions-v2.s.sol";
import {DeployExtensionsV3Script} from "./deploy-extensions-v3.s.sol";
import {DeploySecondaryConditionsScript} from "./deploy-secondary-conditions.s.sol";
import {UpgradeCoreScript} from "./upgrade-core.s.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {DeploymentUtils} from "./libs/DeploymentUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @notice Runs the whole v5 release: the core singletons (`UpgradeCoreScript`), the live V1 and V2
///         certificate extensions, the V3 extensions and the secondary-trading condition singletons.
/// @dev Run this once per production chain, or on a testnet as a rehearsal.
///      The deployer deploys all new contracts. An upgrade or a setter needs the owner role on its auth.
///      The deployer sends it when it holds that role. Otherwise the MetaLeX Safe must sign it, and the
///      script writes the Safe batch JSON for the Safe Transaction Builder. See `DeploymentScript`.
///      On a production chain, the script also moves the owner role of each core auth from the
///      deployer to the Safe. See `DeploymentScript.handOffAuthOwner`.
///      Corp upgrades intentionally are not broadcast here:
///      `corpUpgradeCalls` returns the six calls that a corp owner must execute in one Safe batch.
contract UpgradeV5Script is DeploymentScript {
    // A new contract uses CREATE3 with the proxy salt, so its address depends only on the deployer and the
    // proxy salt. The proxy salt must stay the same. An existing contract is not deployed again.
    // An implementation is deployed only when its code changed. See `DeploymentScript`.
    string private constant EXTENSIONS_V2_PROXY_SALT = "CyberCorpV5-ExtensionsV2.0.1";
    string private constant EXTENSIONS_V3_PROXY_SALT = "CyberCorpV5-ExtensionsV3";
    string private constant SECONDARY_CONDITIONS_PROXY_SALT = "CyberCorpV5-SecondaryConditionsV1.0.0";

    /// @dev The implementations that a corp owner upgrades to. See `corpUpgradeCalls`.
    struct Implementations {
        address cyberCorp;
        address issuanceManager;
        address dealManager;
        address roundManager;
        address ledgerEntryToken;
        address cyberScrip;
    }

    function run() external {
        // The call reverts on a chain that DeploymentConstants does not support.
        bool testnet = DeploymentConstants.isTestnet(block.chainid);

        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);

        console2.log("==== UpgradeV5Script Configs ====");
        initDeployment("[config]", block.chainid, privateKey, core.metalexSafe);
        console2.log("[config] AUTH:", core.auth);

        // Each called script returns the calls that only the Safe can do.
        appendSafeTxs("[sub-script]", (new UpgradeCoreScript()).runWithArgs(block.chainid, privateKey), "core");
        appendSafeTxs(
            "[sub-script]",
            (new DeployExtensionsV2Script()).runWithArgs(block.chainid, EXTENSIONS_V2_PROXY_SALT, privateKey),
            "extensions V2"
        );
        appendSafeTxs(
            "[sub-script]",
            (new DeployExtensionsV3Script()).runWithArgs(block.chainid, EXTENSIONS_V3_PROXY_SALT, privateKey),
            "extensions V3"
        );
        appendSafeTxs(
            "[sub-script]",
            (new DeploySecondaryConditionsScript()).runWithArgs(
                block.chainid, SECONDARY_CONDITIONS_PROXY_SALT, privateKey
            ),
            "secondary conditions"
        );

        // On a testnet the deployer keeps its roles, so that it can send the next rehearsal itself.
        if (!testnet) {
            handOffAuthOwner("[hand off auth]", core.auth, "core AUTH");
            handOffAuthOwner("[hand off auth]", core.lexchexAuth, "LeXcheX AUTH");
            handOffAuthOwner("[hand off auth]", core.lexchexBadgeAuth, "LeXcheX badge AUTH");
        }

        finish(
            "[Safe batch]", string.concat("script/res/gnosis-batch-upgrade-v5-", vm.toString(block.chainid), ".json")
        );
    }

    /// @notice Returns the atomic Safe batch for a single corp after singleton deployment.
    /// @dev Set all V5_*_IMPLEMENTATION environment variables to the implementation addresses
    ///      logged by `run`. Execute the returned calls as one Safe transaction, never individually.
    function corpUpgradeCalls(address cyberCorpAddress)
        external
        returns (address[] memory targets, uint256[] memory values, bytes[] memory data)
    {
        return _corpUpgradeCalls(cyberCorpAddress);
    }

    /// @notice Prints an importable Safe Transaction Builder batch for one corp.
    /// @dev Run without `--broadcast`; import the six calls and execute them
    ///      atomically from the corp's authorized Safe.
    function printCorpUpgradeSafeBatch(address cyberCorpAddress) external returns (string memory safeTxJson) {
        (address[] memory targets, uint256[] memory values, bytes[] memory data) = _corpUpgradeCalls(cyberCorpAddress);
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            safeTxs[i] = GnosisTransaction({to: targets[i], value: values[i], data: data[i]});
        }

        safeTxJson = DeploymentUtils.formatSafeTxJson(safeTxs, block.chainid);
        console2.log("Safe Transaction Builder JSON for v5 corp upgrade:");
        console2.log("==== JSON data start ====");
        console2.log(safeTxJson);
        console2.log("==== JSON data end ====");
    }

    function _corpUpgradeCalls(address cyberCorpAddress)
        internal
        returns (address[] memory targets, uint256[] memory values, bytes[] memory data)
    {
        Implementations memory impls = _implementationsFromEnv();
        CyberCorp corp = CyberCorp(cyberCorpAddress);
        address issuanceManager = corp.issuanceManager();
        address dealManager = corp.dealManager();
        address roundManager = corp.roundManager();
        if (issuanceManager == address(0) || dealManager == address(0) || roundManager == address(0)) {
            revert("Corp stack is incomplete");
        }

        targets = new address[](6);
        values = new uint256[](6);
        data = new bytes[](6);

        targets[0] = cyberCorpAddress;
        data[0] = abi.encodeCall(IUUPS.upgradeToAndCall, (impls.cyberCorp, bytes("")));
        targets[1] = issuanceManager;
        data[1] = abi.encodeCall(IUUPS.upgradeToAndCall, (impls.issuanceManager, bytes("")));
        targets[2] = dealManager;
        data[2] = abi.encodeCall(IUUPS.upgradeToAndCall, (impls.dealManager, bytes("")));
        targets[3] = roundManager;
        data[3] = abi.encodeCall(IUUPS.upgradeToAndCall, (impls.roundManager, bytes("")));
        targets[4] = issuanceManager;
        data[4] = abi.encodeCall(IssuanceManager.upgradeCertPrinterBeaconImplementation, (impls.ledgerEntryToken));
        targets[5] = issuanceManager;
        data[5] = abi.encodeCall(IssuanceManager.upgradeScripBeaconImplementation, (impls.cyberScrip));
    }

    function _implementationsFromEnv() internal view returns (Implementations memory impls) {
        impls.cyberCorp = vm.envAddress("V5_CYBERCORP_IMPLEMENTATION");
        impls.issuanceManager = vm.envAddress("V5_ISSUANCE_MANAGER_IMPLEMENTATION");
        impls.dealManager = vm.envAddress("V5_DEAL_MANAGER_IMPLEMENTATION");
        impls.roundManager = vm.envAddress("V5_ROUND_MANAGER_IMPLEMENTATION");
        impls.ledgerEntryToken = vm.envAddress("V5_LEDGER_ENTRY_TOKEN_IMPLEMENTATION");
        impls.cyberScrip = vm.envAddress("V5_CYBER_SCRIP_IMPLEMENTATION");
    }
}

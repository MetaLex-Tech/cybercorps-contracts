// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {ZKPassportConditionLib, ZKPassportConfig} from "../src/libs/ZKPassportConditionLib.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Upgrades the MetaLeX-owned core singletons and the implementations that their factories use.
///         It also sets two new settings:
///         - the secondary-trade fee ratio, which the upgraded DealManagerFactory starts at zero;
///         - the ZKPassport config of CyberAgreementRegistry, which checks the passport proofs of signers.
/// @dev All core singletons exist, so this script deploys only implementations.
///      The certificate renderers are not here. `DeployBuildersScript` upgrades them in one call.
///      For each singleton: deploy a new implementation when the code changed, then upgrade the proxy
///      and set the factory references. See `DeploymentScript` for the checks and for who sends each call.
contract UpgradeCoreScript is DeploymentScript {
    /// @dev Secondary trades are priced apart from primary issuance. The primary rate keeps its
    ///      stored value through the upgrade; the secondary rate is new state and starts at zero.
    uint256 private constant SECONDARY_FEE_RATIO_BPS = 500; // 5% of the ticket

    function run() public {
        runAndExecute(
//            // Production
//            DeploymentConstants.BASE,
//            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
            // Staging
            DeploymentConstants.BASE_SEPOLIA,
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    /// @notice Upgrades, then writes the Safe batch for the calls that the deployer cannot send.
    function runAndExecute(uint256 chainId, uint256 deployerPrivateKey) public {
        runWithArgs(chainId, deployerPrivateKey);
        finish("[Safe batch]", string.concat("script/res/gnosis-batch-upgrade-core-", vm.toString(chainId), ".json"));
    }

    function runWithArgs(uint256 chainId, uint256 deployerPrivateKey) public returns (GnosisTransaction[] memory) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(chainId);

        console2.log("==== UpgradeCoreScript Configs ====");
        initDeployment("[config]", chainId, deployerPrivateKey, core.metalexSafe);
        console2.log("[config] AUTH:", core.auth);
        console2.log("[config] ZKPassport verifier:", core.zkpassportVerifier);
        console2.log("[config] ZKPassport domain: %s", DeploymentConstants.zkpassportDomain(chainId));
        console2.log("[config] ZKPassport scope: %s", DeploymentConstants.ZKPASSPORT_SCOPE);
        console2.log("[config] ZKPassport dev mode:", DeploymentConstants.isTestnet(chainId));
        console2.log("");

        // This must happen before CyberCorpFactory is upgraded: its v5 deployment
        // path invokes RoundManager.createRound using the new CyberCertData selector.
        // MTLX1-41 changes every component factory's salt namespace, including Base.
        RoundManagerFactory rmFactory = RoundManagerFactory(core.roundManagerFactory);
        upgradeProxy(core.auth, address(rmFactory), "RoundManagerFactory", type(RoundManagerFactory).creationCode);
        deployAndSetRefImplementation(
            core.auth,
            address(rmFactory),
            rmFactory.getRefImplementation(),
            RoundManagerFactory.setRefImplementation.selector,
            "RoundManager",
            type(RoundManager).creationCode
        );

        CyberCorpSingleFactory singleFactory = CyberCorpSingleFactory(core.cyberCorpSingleFactory);
        upgradeProxy(
            core.auth, address(singleFactory), "CyberCorpSingleFactory", type(CyberCorpSingleFactory).creationCode
        );
        deployAndSetRefImplementation(
            core.auth,
            address(singleFactory),
            singleFactory.getRefImplementation(),
            CyberCorpSingleFactory.setRefImplementation.selector,
            "CyberCorp",
            type(CyberCorp).creationCode
        );

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(core.issuanceManagerFactory);
        upgradeProxy(core.auth, address(imFactory), "IssuanceManagerFactory", type(IssuanceManagerFactory).creationCode);
        deployAndSetRefImplementation(
            core.auth,
            address(imFactory),
            imFactory.getRefImplementation(),
            IssuanceManagerFactory.setRefImplementation.selector,
            "IssuanceManager",
            type(IssuanceManager).creationCode
        );
        deployAndSetRefImplementation(
            core.auth,
            address(imFactory),
            imFactory.getCyberCertPrinterRefImplementation(),
            IssuanceManagerFactory.setCyberCertPrinterRefImplementation.selector,
            "LedgerEntryToken",
            type(LedgerEntryToken).creationCode
        );
        deployAndSetRefImplementation(
            core.auth,
            address(imFactory),
            imFactory.getCyberScripRefImplementation(),
            IssuanceManagerFactory.setCyberScripRefImplementation.selector,
            "CyberScrip",
            type(CyberScrip).creationCode
        );

        DealManagerFactory dmFactory = DealManagerFactory(core.dealManagerFactory);
        upgradeProxy(core.auth, address(dmFactory), "DealManagerFactory", type(DealManagerFactory).creationCode);
        deployAndSetRefImplementation(
            core.auth,
            address(dmFactory),
            dmFactory.getRefImplementation(),
            DealManagerFactory.setRefImplementation.selector,
            "DealManager",
            type(DealManager).creationCode
        );
        setParamIfDifferent(
            core.auth,
            address(dmFactory),
            dmFactory.getUnderlyingDefaultSecondaryFeeRatio.selector, // after upgrade, use this getter to check values
            bytes4(0), // before upgrade, no getter since the legacy DealManagerFactory has no secondary fee ratio
            dmFactory.setDefaultSecondaryFeeRatio.selector,
            abi.encode(SECONDARY_FEE_RATIO_BPS),
            string.concat("default secondary fee ratio (bps): ", vm.toString(SECONDARY_FEE_RATIO_BPS))
        );

        // TODO: LegalDocRegistry is disabled on all chains for now. Put it back for production: add it to
        //       DeploymentConstants and upgrade it to the CyberAgreementRegistry implementation.
        upgradeCyberAgreementRegistry(chainId, core);

        upgradeProxy(core.lexchexAuth, core.lexchexMinter, "LeXcheXMinter", type(LeXcheXMinter).creationCode);

        // Keep last: all factory references and the RoundManager deployment dependency are now live.
        upgradeProxy(core.auth, core.cyberCorpFactory, "CyberCorpFactory", type(CyberCorpFactory).creationCode);
        // PumpCorpFactory exists on Base only.
        if (chainId == DeploymentConstants.BASE) {
            upgradeProxy(
                core.auth,
                DeploymentConstants.pump(chainId).pumpCorpFactory,
                "PumpCorpFactory",
                type(PumpCorpFactory).creationCode
            );
        }

        console2.log(" ");
        return safeTxs;
    }

    /// @notice Upgrades CyberAgreementRegistry, then sets its ZKPassport config.
    /// @dev The config call goes after the upgrade, because only the new implementation has the setter. Both use
    ///      the same auth, so both go to the deployer or both go to the Safe, in this order.
    function upgradeCyberAgreementRegistry(uint256 chainId, DeploymentConstants.CoreDeployment memory core) internal {
        upgradeProxy(
            core.auth, core.cyberAgreementRegistry, "CyberAgreementRegistry", type(CyberAgreementRegistry).creationCode
        );
        setZKPassportConfig(chainId, core);
    }

    /// @notice Sets the config that the registry uses to check ZKPassport proofs. It applies to all agreements
    ///         with a ZKPassport condition. It uses the same domain and scope as ZKPassportFinalizer, so a passport
    ///         has the same unique identifier in both.
    /// @dev A chain with no ZKPassport verifier gets no config. A creator cannot add a ZKPassport condition there.
    ///      A testnet gets dev mode, so a mock passport can sign there. A production chain does not.
    function setZKPassportConfig(uint256 chainId, DeploymentConstants.CoreDeployment memory core) internal {
        if (core.zkpassportVerifier == address(0)) {
            console2.log("[set param] no ZKPassport verifier on this chain, ZKPassport config not set");
            return;
        }
        bytes memory config = abi.encode(
            ZKPassportConfig({
                verifier: core.zkpassportVerifier,
                domain: DeploymentConstants.zkpassportDomain(chainId),
                scope: DeploymentConstants.ZKPASSPORT_SCOPE,
                devMode: DeploymentConstants.isTestnet(chainId)
            })
        );
        setParamIfDifferent(
            core.auth,
            core.cyberAgreementRegistry,
            abi.encodeCall(CyberAgreementRegistry.getSignerConditionConfig, (ZKPassportConditionLib.KIND)),
            abi.encode(config), // the getter returns `config` as ABI-encoded bytes
            abi.encodeCall(CyberAgreementRegistry.setSignerConditionConfig, (ZKPassportConditionLib.KIND, config)),
            "CyberAgreementRegistry ZKPassport config"
        );
    }
}

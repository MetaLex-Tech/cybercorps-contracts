// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
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
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";
import {DeploymentScript} from "./libs/DeploymentScript.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Upgrades the MetaLeX-owned core singletons and the implementations that their factories use.
///         It sets the secondary-trade fee ratio, which the upgraded DealManagerFactory starts at zero.
/// @dev All core singletons exist, so this script deploys only implementations.
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
        execute(
            "[set fee ratio]",
            core.auth,
            address(dmFactory),
            abi.encodeCall(DealManagerFactory.setDefaultSecondaryFeeRatio, (SECONDARY_FEE_RATIO_BPS)),
            string.concat("setting default secondary fee ratio (bps): ", vm.toString(SECONDARY_FEE_RATIO_BPS))
        );

        upgradeProxy(core.auth, core.uriBuilder, "CertificateUriBuilder", type(CertificateUriBuilder).creationCode);
        // TODO: LegalDocRegistry is disabled on all chains for now. Put it back for production: add it to
        //       DeploymentConstants and upgrade it to the CyberAgreementRegistry implementation.
        upgradeProxy(
            core.auth, core.cyberAgreementRegistry, "CyberAgreementRegistry", type(CyberAgreementRegistry).creationCode
        );

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
}

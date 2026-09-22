// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";

import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {PumpCorpFactory} from "../src/PumpCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";

import {CyberScrip} from "../src/CyberScrip.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";

import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";

import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";

import {DeployExtensionsV2Script} from "./deploy-extensions-v2.s.sol";
import {DeployExtensionsV3Script} from "./deploy-extensions-v3.s.sol";
import {DeploySecondaryConditionsScript} from "./deploy-secondary-conditions.s.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

import {SafeUtils} from "./libs/SafeUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {Script, console2} from "forge-std/Script.sol";

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @notice Deploys v5 implementations and upgrades MetaLeX-owned singleton proxies.
///         It also upgrades the live V1 and V2 certificate extensions, deploys the V3 extensions
///         and deploys the secondary-trading condition singletons that the chain does not have.
///         It sets the secondary-trade fee ratio, which the upgraded DealManagerFactory starts at zero.
/// @dev Run this once per production chain, or on a testnet as a rehearsal.
///      The deployer deploys all new contracts. The upgrades and setters need the owner role, so the
///      script collects them as gated calls. On a testnet where the deployer is owner, the deployer
///      sends them. Otherwise the MetaLeX Safe must sign them as one batch, and the script writes
///      the batch JSON for the Safe Transaction Builder.
///      Corp upgrades intentionally are not broadcast here:
///      `corpUpgradeCalls` returns the six calls that a corp owner must execute in one Safe batch.
contract UpgradeV5Script is Script {
    // Each sub-script takes two salts. The proxy salt fixes the address of a proxy this run creates,
    // so it stays as recorded. Bump the implementation salt to re-run on a chain that already holds
    // these implementations, because the same code under the same salt gives an occupied address.
    string private constant EXTENSIONS_V2_PROXY_SALT = "CyberCorpV5-ExtensionsV2.0.1";
    string private constant EXTENSIONS_V3_PROXY_SALT = "CyberCorpV5-ExtensionsV3";
    string private constant SECONDARY_CONDITIONS_PROXY_SALT = "CyberCorpV5-SecondaryConditionsV1.0.0";

    string private constant EXTENSIONS_V2_IMPL_SALT = "CyberCorpV5-ExtensionsV2.0.1-impl0";
    string private constant EXTENSIONS_V3_IMPL_SALT = "CyberCorpV5-ExtensionsV3-impl0";
    string private constant SECONDARY_CONDITIONS_IMPL_SALT = "CyberCorpV5-SecondaryConditions-impl-V1.0.0-impl0";

    /// @dev Secondary trades are priced apart from primary issuance. The primary rate keeps its
    ///      stored value through the upgrade; the secondary rate is new state and starts at zero.
    uint256 private constant SECONDARY_FEE_RATIO_BPS = 600; // 6% of the ticket

    struct Implementations {
        address cyberCorpFactory;
        address pumpCorpFactory;
        address cyberCorpSingleFactory;
        address issuanceManagerFactory;
        address cyberCorp;
        address issuanceManager;
        address dealManager;
        address roundManager;
        address ledgerEntryToken;
        address cyberScrip;
        address dealManagerFactory;
        address roundManagerFactory;
        address registry;
        address certificateUriBuilder;
        address lexchexMinter;
    }

    struct Targets {
        address cyberCorpFactory;
        address pumpCorpFactory;
        address cyberCorpSingleFactory;
        address issuanceManagerFactory;
        address dealManagerFactory;
        address roundManagerFactory;
        address registry;
        address legalDocRegistry;
        address certificateUriBuilder;
        address lexchexMinter;
    }

    GnosisTransaction[] internal gatedCalls;

    function run() external {
        // The call reverts on a chain that DeploymentConstants does not support.
        bool testnet = DeploymentConstants.isTestnet(block.chainid);
        if (!vm.envOr("CONFIRM_V5_SINGLETON_UPGRADE", false)) {
            revert("Set CONFIRM_V5_SINGLETON_UPGRADE=true");
        }

        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        Targets memory targets = _targets();

        vm.startBroadcast(privateKey);
        Implementations memory impls = _deployImplementations();
        vm.stopBroadcast();

        _queueSingletonCalls(targets, impls);

        // Each called script deploys in its own broadcast and returns its gated calls.
        _queueAll((new DeployExtensionsV2Script()).runWithArgs(
            block.chainid, EXTENSIONS_V2_PROXY_SALT, EXTENSIONS_V2_IMPL_SALT, privateKey
        ));
        (, GnosisTransaction[] memory v3Calls) = (new DeployExtensionsV3Script()).runWithArgs(
            block.chainid, EXTENSIONS_V3_PROXY_SALT, EXTENSIONS_V3_IMPL_SALT, privateKey
        );
        _queueAll(v3Calls);
        (, GnosisTransaction[] memory conditionCalls) = (new DeploySecondaryConditionsScript()).runWithArgs(
            block.chainid, SECONDARY_CONDITIONS_PROXY_SALT, SECONDARY_CONDITIONS_IMPL_SALT, privateKey
        );
        _queueAll(conditionCalls);

        // On a testnet the deployer must own the core AUTH, the LeXcheX AUTH and the LeXcheX badge AUTH.
        // A zero badge AUTH means this run deploys a new one, and the deployer owns it.
        bool direct = testnet && SafeUtils.hasOwnerRole(core.auth, deployer)
            && SafeUtils.hasOwnerRole(core.lexchexAuth, deployer)
            && (core.lexchexBadgeAuth == address(0) || SafeUtils.hasOwnerRole(core.lexchexBadgeAuth, deployer));
        SafeUtils.executeOrHandOff(
            gatedCalls,
            block.chainid,
            privateKey,
            core.metalexSafe,
            direct,
            string.concat("script/res/gnosis-batch-upgrade-v5-", vm.toString(block.chainid), ".json")
        );
    }

    function _queueSingletonCalls(Targets memory targets, Implementations memory impls) internal {
        // This must happen before CyberCorpFactory is upgraded: its v5 deployment
        // path invokes RoundManager.createRound using the new CyberCertData selector.
        // MTLX1-41 changes every component factory's salt namespace, including Base.
        _queueUpgrade(targets.roundManagerFactory, impls.roundManagerFactory, "RoundManagerFactory");
        _queue(targets.roundManagerFactory, abi.encodeCall(RoundManagerFactory.setRefImplementation, (impls.roundManager)));

        _queueUpgrade(targets.cyberCorpSingleFactory, impls.cyberCorpSingleFactory, "CyberCorpSingleFactory");
        _queueUpgrade(targets.issuanceManagerFactory, impls.issuanceManagerFactory, "IssuanceManagerFactory");
        _queue(
            targets.cyberCorpSingleFactory,
            abi.encodeCall(CyberCorpSingleFactory.setRefImplementation, (impls.cyberCorp))
        );
        _queue(
            targets.issuanceManagerFactory,
            abi.encodeCall(IssuanceManagerFactory.setRefImplementation, (impls.issuanceManager))
        );
        _queue(
            targets.issuanceManagerFactory,
            abi.encodeCall(IssuanceManagerFactory.setCyberCertPrinterRefImplementation, (impls.ledgerEntryToken))
        );
        _queue(
            targets.issuanceManagerFactory,
            abi.encodeCall(IssuanceManagerFactory.setCyberScripRefImplementation, (impls.cyberScrip))
        );

        _queueUpgrade(targets.dealManagerFactory, impls.dealManagerFactory, "DealManagerFactory");
        _queue(targets.dealManagerFactory, abi.encodeCall(DealManagerFactory.setRefImplementation, (impls.dealManager)));
        _queue(
            targets.dealManagerFactory,
            abi.encodeCall(DealManagerFactory.setDefaultSecondaryFeeRatio, (SECONDARY_FEE_RATIO_BPS))
        );

        _queueUpgrade(targets.certificateUriBuilder, impls.certificateUriBuilder, "CertificateUriBuilder");
        _queueUpgrade(targets.registry, impls.registry, "CyberAgreementRegistry");
        if (targets.legalDocRegistry != address(0)) {
            _queueUpgrade(targets.legalDocRegistry, impls.registry, "LegalDocRegistry");
        } else {
            console2.log("LegalDocRegistry not set, skipping");
        }

        _queueUpgrade(targets.lexchexMinter, impls.lexchexMinter, "LeXcheXMinter");

        // Keep last: all factory references and the RoundManager deployment dependency are now live.
        _queueUpgrade(targets.cyberCorpFactory, impls.cyberCorpFactory, "CyberCorpFactory");
        if (targets.pumpCorpFactory != address(0)) {
            _queueUpgrade(targets.pumpCorpFactory, impls.pumpCorpFactory, "PumpCorpFactory");
        }
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

        safeTxJson = SafeUtils.formatSafeTxJson(safeTxs, block.chainid);
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

    function _targets() internal view returns (Targets memory targets) {
        DeploymentConstants.CoreDeployment memory core = DeploymentConstants.coreV2(block.chainid);
        targets.cyberCorpFactory = vm.envOr("CYBERCORP_FACTORY", core.cyberCorpFactory);
        targets.pumpCorpFactory = block.chainid == DeploymentConstants.BASE
            ? vm.envOr("PUMP_CORP_FACTORY", DeploymentConstants.pump(block.chainid).pumpCorpFactory)
            : vm.envOr("PUMP_CORP_FACTORY", address(0));
        targets.cyberCorpSingleFactory = vm.envOr("CYBERCORP_SINGLE_FACTORY", core.cyberCorpSingleFactory);
        targets.issuanceManagerFactory = vm.envOr("ISSUANCE_MANAGER_FACTORY", core.issuanceManagerFactory);
        targets.dealManagerFactory = vm.envOr("DEAL_MANAGER_FACTORY", core.dealManagerFactory);
        targets.roundManagerFactory = vm.envOr("ROUND_MANAGER_FACTORY", core.roundManagerFactory);
        targets.registry = vm.envOr("CYBER_AGREEMENT_REGISTRY", core.cyberAgreementRegistry);
        targets.certificateUriBuilder = vm.envOr("CERTIFICATE_URI_BUILDER", core.uriBuilder);
        targets.lexchexMinter = vm.envOr("LEXCHEX_MINTER", core.lexchexMinter);
        // TODO: LegalDocRegistry is disabled on all chains for now. Put it back for production:
        //       targets.legalDocRegistry = vm.envAddress("LEGAL_DOC_REGISTRY");
        targets.legalDocRegistry = address(0);
    }

    function _deployImplementations() internal returns (Implementations memory impls) {
        impls.cyberCorpFactory = address(new CyberCorpFactory());
        impls.pumpCorpFactory = address(new PumpCorpFactory());
        impls.cyberCorpSingleFactory = address(new CyberCorpSingleFactory());
        impls.issuanceManagerFactory = address(new IssuanceManagerFactory());
        impls.cyberCorp = address(new CyberCorp());
        impls.issuanceManager = address(new IssuanceManager());
        impls.dealManager = address(new DealManager());
        impls.roundManager = address(new RoundManager());
        impls.ledgerEntryToken = address(new LedgerEntryToken());
        impls.cyberScrip = address(new CyberScrip());
        impls.dealManagerFactory = address(new DealManagerFactory());
        impls.roundManagerFactory = address(new RoundManagerFactory());
        impls.registry = address(new CyberAgreementRegistry());
        impls.certificateUriBuilder = address(new CertificateUriBuilder());
        impls.lexchexMinter = address(new LeXcheXMinter());

        console2.log("V5 CyberCorpFactory:", impls.cyberCorpFactory);
        console2.log("V5 PumpCorpFactory:", impls.pumpCorpFactory);
        console2.log("V5 CyberCorpSingleFactory:", impls.cyberCorpSingleFactory);
        console2.log("V5 IssuanceManagerFactory:", impls.issuanceManagerFactory);
        console2.log("V5 CyberCorp:", impls.cyberCorp);
        console2.log("V5 IssuanceManager:", impls.issuanceManager);
        console2.log("V5 DealManager:", impls.dealManager);
        console2.log("V5 RoundManager:", impls.roundManager);
        console2.log("V5 LedgerEntryToken:", impls.ledgerEntryToken);
        console2.log("V5 CyberScrip:", impls.cyberScrip);
        console2.log("V5 DealManagerFactory:", impls.dealManagerFactory);
        console2.log("V5 RoundManagerFactory:", impls.roundManagerFactory);
        console2.log("V5 CyberAgreementRegistry:", impls.registry);
        console2.log("V5 CertificateUriBuilder:", impls.certificateUriBuilder);
        console2.log("V5 LeXcheXMinter:", impls.lexchexMinter);
    }

    function _implementationsFromEnv() internal view returns (Implementations memory impls) {
        impls.cyberCorp = vm.envAddress("V5_CYBERCORP_IMPLEMENTATION");
        impls.issuanceManager = vm.envAddress("V5_ISSUANCE_MANAGER_IMPLEMENTATION");
        impls.dealManager = vm.envAddress("V5_DEAL_MANAGER_IMPLEMENTATION");
        impls.roundManager = vm.envAddress("V5_ROUND_MANAGER_IMPLEMENTATION");
        impls.ledgerEntryToken = vm.envAddress("V5_LEDGER_ENTRY_TOKEN_IMPLEMENTATION");
        impls.cyberScrip = vm.envAddress("V5_CYBER_SCRIP_IMPLEMENTATION");
    }

    function _queueUpgrade(address proxy, address implementation, string memory name) internal {
        if (proxy == address(0)) revert("Missing proxy address");
        _queue(proxy, abi.encodeCall(IUUPS.upgradeToAndCall, (implementation, "")));
        console2.log("Queued upgrade", name, proxy);
    }

    function _queue(address to, bytes memory data) internal {
        gatedCalls.push(GnosisTransaction({to: to, value: 0, data: data}));
    }

    function _queueAll(GnosisTransaction[] memory calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            gatedCalls.push(calls[i]);
        }
    }
}

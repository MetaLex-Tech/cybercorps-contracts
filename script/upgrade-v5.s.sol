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
import {ParentCoFactory} from "../src/ParentCoFactory.sol";

import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {BorgAuth} from "../src/libs/auth.sol";

import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

import {SafeUtils} from "./libs/SafeUtils.sol";
import {GnosisTransaction} from "./libs/safe.sol";
import {Script, console2} from "forge-std/Script.sol";

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @notice Deploys v5 implementations and upgrades MetaLeX-owned singleton proxies.
/// @dev Run this once per production chain, or on Base Sepolia as a rehearsal.
///      Corp upgrades intentionally are not broadcast here:
///      `corpUpgradeCalls` returns the six calls that a corp owner must execute in one Safe batch.
contract UpgradeV5Script is Script {
    uint256 private constant ETHEREUM = 1;
    uint256 private constant BASE = 8453;
    uint256 private constant BASE_SEPOLIA = 84532;
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    struct Implementations {
        address cyberCorpFactory;
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
        address parentCoFactory;
        address lexchexMinter;
    }

    struct Targets {
        address cyberCorpFactory;
        address cyberCorpSingleFactory;
        address issuanceManagerFactory;
        address dealManagerFactory;
        address roundManagerFactory;
        address registry;
        address legalDocRegistry;
        address certificateUriBuilder;
        address pumpCertificateUriBuilder;
        address parentCoFactory;
        address lexchexMinter;
        address pumpLexchexMinter;
    }

    function run() external {
        if (block.chainid != ETHEREUM && block.chainid != BASE && block.chainid != BASE_SEPOLIA) {
            revert("v5 upgrade supports Ethereum, Base and Base Sepolia only");
        }
        if (!vm.envOr("CONFIRM_V5_SINGLETON_UPGRADE", false)) {
            revert("Set CONFIRM_V5_SINGLETON_UPGRADE=true");
        }

        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(privateKey);
        Targets memory targets = _targets();
        _requireOwner(targets.cyberCorpFactory, deployer);
        _requireLexchexOwner(deployer);

        vm.startBroadcast(privateKey);
        Implementations memory impls = _deployImplementations();

        // This must happen before CyberCorpFactory is upgraded: its v5 deployment
        // path invokes RoundManager.createRound using the new CyberCertData selector.
        // The Base mainnet proxy already matches HEAD, so only the other chains upgrade it.
        if (block.chainid != BASE) {
            _upgradeProxy(targets.roundManagerFactory, impls.roundManagerFactory, "RoundManagerFactory");
        }
        RoundManagerFactory(targets.roundManagerFactory).setRefImplementation(impls.roundManager);

        // Unchanged factory proxies still need their v5 reference implementations.
        CyberCorpSingleFactory(targets.cyberCorpSingleFactory).setRefImplementation(impls.cyberCorp);
        IssuanceManagerFactory issuanceFactory = IssuanceManagerFactory(targets.issuanceManagerFactory);
        issuanceFactory.setRefImplementation(impls.issuanceManager);
        issuanceFactory.setCyberCertPrinterRefImplementation(impls.ledgerEntryToken);
        issuanceFactory.setCyberScripRefImplementation(impls.cyberScrip);

        _upgradeProxy(targets.dealManagerFactory, impls.dealManagerFactory, "DealManagerFactory");
        DealManagerFactory(targets.dealManagerFactory).setRefImplementation(impls.dealManager);

        _upgradeProxy(targets.certificateUriBuilder, impls.certificateUriBuilder, "CertificateUriBuilder");
        _upgradeProxy(targets.registry, impls.registry, "CyberAgreementRegistry");
        if (targets.legalDocRegistry != address(0)) {
            _upgradeProxy(targets.legalDocRegistry, impls.registry, "LegalDocRegistry");
        } else {
            console2.log("LegalDocRegistry not set, skipping");
        }

        // The pump stack exists on Base mainnet only.
        if (block.chainid == BASE) {
            _upgradeProxy(targets.pumpCertificateUriBuilder, impls.certificateUriBuilder, "Pump CertificateUriBuilder");
            _upgradeProxy(targets.pumpLexchexMinter, impls.lexchexMinter, "Pump LeXcheXMinter");
        }
        // Zero on Ethereum mainnet, where the proxy already matches HEAD.
        if (targets.parentCoFactory != address(0)) {
            _upgradeProxy(targets.parentCoFactory, impls.parentCoFactory, "ParentCoFactory");
        }
        _upgradeProxy(targets.lexchexMinter, impls.lexchexMinter, "LeXcheXMinter");

        // Keep last: all factory references and the RoundManager deployment dependency are now live.
        _upgradeProxy(targets.cyberCorpFactory, impls.cyberCorpFactory, "CyberCorpFactory");

        vm.stopBroadcast();
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
        targets.cyberCorpSingleFactory = vm.envOr("CYBERCORP_SINGLE_FACTORY", core.cyberCorpSingleFactory);
        targets.issuanceManagerFactory = vm.envOr("ISSUANCE_MANAGER_FACTORY", core.issuanceManagerFactory);
        targets.dealManagerFactory = vm.envOr("DEAL_MANAGER_FACTORY", core.dealManagerFactory);
        targets.roundManagerFactory = vm.envOr("ROUND_MANAGER_FACTORY", core.roundManagerFactory);
        targets.registry = vm.envOr("CYBER_AGREEMENT_REGISTRY", core.cyberAgreementRegistry);
        targets.certificateUriBuilder = vm.envOr("CERTIFICATE_URI_BUILDER", core.uriBuilder);
        targets.lexchexMinter = vm.envOr("LEXCHEX_MINTER", core.lexchexMinter);
        // Optional on Base Sepolia so a rehearsal works without a LegalDocRegistry deployment.
        targets.legalDocRegistry = block.chainid == BASE_SEPOLIA
            ? vm.envOr("LEGAL_DOC_REGISTRY", address(0))
            : vm.envAddress("LEGAL_DOC_REGISTRY");

        if (block.chainid == BASE) {
            targets.pumpCertificateUriBuilder = vm.envAddress("PUMP_CERTIFICATE_URI_BUILDER");
            targets.parentCoFactory = vm.envAddress("PARENTCO_FACTORY");
            targets.pumpLexchexMinter = vm.envAddress("PUMP_LEXCHEX_MINTER");
        } else if (block.chainid == BASE_SEPOLIA) {
            targets.parentCoFactory =
                vm.envOr("PARENTCO_FACTORY", DeploymentConstants.umia(block.chainid).parentCoFactory);
        }
    }

    function _deployImplementations() internal returns (Implementations memory impls) {
        impls.cyberCorpFactory = address(new CyberCorpFactory());
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
        impls.parentCoFactory = address(new ParentCoFactory());
        impls.lexchexMinter = address(new LeXcheXMinter());

        console2.log("V5 CyberCorpFactory:", impls.cyberCorpFactory);
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
        console2.log("V5 ParentCoFactory:", impls.parentCoFactory);
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

    function _requireOwner(address factory, address caller) internal view {
        address auth = address(CyberCorpFactory(factory).AUTH());
        if (BorgAuth(auth).userRoles(caller) < BorgAuth(auth).OWNER_ROLE()) {
            revert("PRIVATE_KEY_MAIN is not the core AUTH owner");
        }
    }

    /// @dev The LeXcheX stack has its own BorgAuth; check it up front so the
    ///      broadcast cannot fail partway through the LeXcheXMinter upgrades.
    function _requireLexchexOwner(address caller) internal view {
        BorgAuth auth = BorgAuth(DeploymentConstants.coreV2(block.chainid).lexchexAuth);
        if (auth.userRoles(caller) < auth.OWNER_ROLE()) {
            revert("PRIVATE_KEY_MAIN is not the LeXcheX AUTH owner");
        }
    }

    function _upgradeProxy(address proxy, address implementation, string memory name) internal {
        if (proxy == address(0)) revert("Missing proxy address");
        IUUPS(proxy).upgradeToAndCall(implementation, "");
        if (_implementationOf(proxy) != implementation) {
            revert("Implementation slot mismatch");
        }
        console2.log("Upgraded", name, proxy);
    }

    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}

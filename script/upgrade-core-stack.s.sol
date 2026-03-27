// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {DealManager} from "../src/DealManager.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IssuerApprovalRecertificationCondition} from "../src/libs/conditions/IssuerApprovalRecertificationCondition.sol";
import {ERC1967ProxyLib} from "../test/libs/ERC1967ProxyLib.sol";
import {DeploymentConstants} from "./libs/DeploymentConstants.sol";

interface IUUPS {
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

/// @notice Upgrade script for CyberCorp + IssuanceManager + CyberCertPrinter + CyberScrip.
/// @dev Default run updates factory reference implementations only.
///      To also upgrade a specific deployed stack, set CORP_ADDRESS env var
///      or call run(address[]) with explicit corp addresses.
contract BaseScript is Script {
    using ERC1967ProxyLib for address;
    bytes32 internal constant UPGRADE_SALT =
        keccak256("MetaLexCyberCorp.CoreStack.UpgradeV2.0.6");

    struct UpgradeImplementations {
        address cyberCorpImpl;
        address issuanceManagerImpl;
        address dealManagerImpl;
        address roundManagerImpl;
        address cyberCertPrinterImpl;
        address cyberScripImpl;
        address issuerApprovalRecertificationCondition;
    }

    function run() public {
        address[] memory cyberCorps = new address[](0);
        address maybeCorp = vm.envOr("CORP_ADDRESS", address(0));
        if (maybeCorp != address(0)) {
            cyberCorps = new address[](1);
            cyberCorps[0] = maybeCorp;
        }
        _run(cyberCorps);
    }

    function run(address[] memory cyberCorps) public {
        _run(cyberCorps);
    }

    function _run(address[] memory cyberCorps) internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);
        DeploymentConstants.CoreDeployment memory deployment = DeploymentConstants
            .coreV2(block.chainid);
        address cyberCorpFactoryProxyAddr = vm.envOr(
            "CYBERCORP_FACTORY",
            deployment.cyberCorpFactory
        );

        CyberCorpFactory cyberCorpFactory = CyberCorpFactory(
            cyberCorpFactoryProxyAddr
        );
        address auth = address(cyberCorpFactory.AUTH());

        uint256 role = BorgAuth(auth).userRoles(deployer);
        if (role < BorgAuth(auth).OWNER_ROLE()) {
            revert(
                "Deployer is not AUTH owner; use the AUTH owner key to run upgrades"
            );
        }

        vm.startBroadcast(deployerPrivateKey);

        UpgradeImplementations memory impls = _deployNewImplementations();
        _updateFactoryReferences(cyberCorpFactory, impls);
        _upgradeCyberCorpStacks(cyberCorps, impls);

        vm.stopBroadcast();
    }

    function _deployNewImplementations()
        internal
        returns (UpgradeImplementations memory impls)
    {
        impls.cyberCorpImpl = address(new CyberCorp{salt: UPGRADE_SALT}());
        impls.issuanceManagerImpl = address(
            new IssuanceManager{salt: UPGRADE_SALT}()
        );
        impls.dealManagerImpl = address(new DealManager{salt: UPGRADE_SALT}());
        impls.roundManagerImpl = address(
            new RoundManager{salt: UPGRADE_SALT}()
        );
        impls.cyberCertPrinterImpl = address(
            new CyberCertPrinter{salt: UPGRADE_SALT}()
        );
        impls.cyberScripImpl = address(new CyberScrip{salt: UPGRADE_SALT}());
        impls.issuerApprovalRecertificationCondition = address(
            new IssuerApprovalRecertificationCondition{salt: UPGRADE_SALT}()
        );

        console2.log("New CyberCorp implementation:", impls.cyberCorpImpl);
        console2.log(
            "New IssuanceManager implementation:",
            impls.issuanceManagerImpl
        );
        console2.log("New DealManager implementation:", impls.dealManagerImpl);
        console2.log("New RoundManager implementation:", impls.roundManagerImpl);
        console2.log(
            "New CyberCertPrinter implementation:",
            impls.cyberCertPrinterImpl
        );
        console2.log("New CyberScrip implementation:", impls.cyberScripImpl);
        console2.log(
            "New IssuerApprovalRecertificationCondition:",
            impls.issuerApprovalRecertificationCondition
        );
    }

    function _updateFactoryReferences(
        CyberCorpFactory cyberCorpFactory,
        UpgradeImplementations memory impls
    ) internal {
        // These refs must be set before proxy/beacon upgrades due to _authorizeUpgrade checks.
        CyberCorpSingleFactory corpSingleFactory = CyberCorpSingleFactory(
            cyberCorpFactory.cyberCorpSingleFactory()
        );
        IssuanceManagerFactory issuanceManagerFactory = IssuanceManagerFactory(
            cyberCorpFactory.issuanceManagerFactory()
        );
        DealManagerFactory dealManagerFactory = DealManagerFactory(
            cyberCorpFactory.dealManagerFactory()
        );
        RoundManagerFactory roundManagerFactory = RoundManagerFactory(
            cyberCorpFactory.roundManagerFactory()
        );

        corpSingleFactory.setRefImplementation(impls.cyberCorpImpl);
        issuanceManagerFactory.setRefImplementation(impls.issuanceManagerImpl);
        dealManagerFactory.setRefImplementation(impls.dealManagerImpl);
        roundManagerFactory.setRefImplementation(impls.roundManagerImpl);
        issuanceManagerFactory.setCyberCertPrinterRefImplementation(
            impls.cyberCertPrinterImpl
        );
        issuanceManagerFactory.setCyberScripRefImplementation(
            impls.cyberScripImpl
        );

        vm.assertEq(
            corpSingleFactory.getRefImplementation(),
            impls.cyberCorpImpl,
            "CyberCorpSingleFactory reference implementation mismatch"
        );
        vm.assertEq(
            issuanceManagerFactory.getRefImplementation(),
            impls.issuanceManagerImpl,
            "IssuanceManagerFactory reference implementation mismatch"
        );
        vm.assertEq(
            dealManagerFactory.getRefImplementation(),
            impls.dealManagerImpl,
            "DealManagerFactory reference implementation mismatch"
        );
        vm.assertEq(
            roundManagerFactory.getRefImplementation(),
            impls.roundManagerImpl,
            "RoundManagerFactory reference implementation mismatch"
        );
        vm.assertEq(
            issuanceManagerFactory.getCyberCertPrinterRefImplementation(),
            impls.cyberCertPrinterImpl,
            "IssuanceManagerFactory CyberCertPrinter reference implementation mismatch"
        );
        vm.assertEq(
            issuanceManagerFactory.getCyberScripRefImplementation(),
            impls.cyberScripImpl,
            "IssuanceManagerFactory CyberScrip reference implementation mismatch"
        );

        console2.log(
            "Factory refs updated: CyberCorp, IssuanceManager, DealManager, RoundManager, CyberCertPrinter, CyberScrip"
        );
    }

    function _upgradeCyberCorpStacks(
        address[] memory cyberCorps,
        UpgradeImplementations memory impls
    ) internal {
        if (cyberCorps.length == 0) {
            console2.log(
                "No CyberCorp addresses provided; skipped proxy/beacon upgrades."
            );
            return;
        }

        for (uint256 i = 0; i < cyberCorps.length; i++) {
            _upgradeSingleCyberCorpStack(cyberCorps[i], impls);
        }
    }

    function _upgradeSingleCyberCorpStack(
        address cyberCorpAddr,
        UpgradeImplementations memory impls
    ) internal {
        address oldCyberCorpImpl = cyberCorpAddr.getErc1967Implementation();

        CyberCorp cyberCorp = CyberCorp(cyberCorpAddr);
        address issuanceManagerAddr = cyberCorp.issuanceManager();
        address dealManagerAddr = cyberCorp.dealManager();
        address roundManagerAddr = cyberCorp.roundManager();
        if (issuanceManagerAddr == address(0)) {
            revert("CyberCorp has no IssuanceManager");
        }
        if (dealManagerAddr == address(0)) {
            revert("CyberCorp has no DealManager");
        }
        if (roundManagerAddr == address(0)) {
            revert("CyberCorp has no RoundManager");
        }
        address oldIssuanceManagerImpl = issuanceManagerAddr
            .getErc1967Implementation();
        address oldDealManagerImpl = dealManagerAddr.getErc1967Implementation();
        address oldRoundManagerImpl = roundManagerAddr.getErc1967Implementation();

        console2.log("Upgrading CyberCorp:", cyberCorpAddr);
        console2.log("  old CyberCorp impl:", oldCyberCorpImpl);
        console2.log("  old IssuanceManager impl:", oldIssuanceManagerImpl);
        console2.log("  old DealManager impl:", oldDealManagerImpl);
        console2.log("  old RoundManager impl:", oldRoundManagerImpl);

        IUUPS(cyberCorpAddr).upgradeToAndCall(impls.cyberCorpImpl, "");
        IUUPS(issuanceManagerAddr).upgradeToAndCall(
            impls.issuanceManagerImpl,
            ""
        );
        IUUPS(dealManagerAddr).upgradeToAndCall(impls.dealManagerImpl, "");
        IUUPS(roundManagerAddr).upgradeToAndCall(impls.roundManagerImpl, "");

        IssuanceManager issuanceManager = IssuanceManager(issuanceManagerAddr);
        issuanceManager.upgradeCertPrinterBeaconImplementation(
            impls.cyberCertPrinterImpl
        );
        issuanceManager.upgradeScripBeaconImplementation(impls.cyberScripImpl);

        vm.assertEq(
            cyberCorpAddr.getErc1967Implementation(),
            impls.cyberCorpImpl,
            "CyberCorp upgrade failed"
        );
        vm.assertEq(
            issuanceManagerAddr.getErc1967Implementation(),
            impls.issuanceManagerImpl,
            "IssuanceManager upgrade failed"
        );
        vm.assertEq(
            dealManagerAddr.getErc1967Implementation(),
            impls.dealManagerImpl,
            "DealManager upgrade failed"
        );
        vm.assertEq(
            roundManagerAddr.getErc1967Implementation(),
            impls.roundManagerImpl,
            "RoundManager upgrade failed"
        );
        vm.assertEq(
            issuanceManager.getCertPrinterBeaconImplementation(),
            impls.cyberCertPrinterImpl,
            "CyberCertPrinter beacon upgrade failed"
        );
        vm.assertEq(
            issuanceManager.getScripBeaconImplementation(),
            impls.cyberScripImpl,
            "CyberScrip beacon upgrade failed"
        );

        console2.log("  new CyberCorp impl:", cyberCorpAddr.getErc1967Implementation());
        console2.log(
            "  new IssuanceManager impl:",
            issuanceManagerAddr.getErc1967Implementation()
        );
        console2.log(
            "  new DealManager impl:",
            dealManagerAddr.getErc1967Implementation()
        );
        console2.log(
            "  new RoundManager impl:",
            roundManagerAddr.getErc1967Implementation()
        );
        console2.log(
            "  new CyberCertPrinter beacon impl:",
            issuanceManager.getCertPrinterBeaconImplementation()
        );
        console2.log(
            "  new CyberScrip beacon impl:",
            issuanceManager.getScripBeaconImplementation()
        );
    }
}

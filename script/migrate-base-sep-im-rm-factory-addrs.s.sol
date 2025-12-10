// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console2} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";
import {DealManagerStorage} from "../src/storage/DealManagerStorage.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {ILegacyFactory} from "./interfaces/ILegacyFactory.sol";
import {KnownAddressesLoader} from "./libs/KnownAddressesLoader.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManagerWithFactoryMigration} from "../src/IssuanceManagerWithFactoryMigration.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManagerWithFactoryMigration} from "../src/RoundManagerWithFactoryMigration.sol";

contract MigrateBaseSepImRmFactoryAddrsScript is Script {
    mapping(address => uint256) private corpOwnerPrivateKeyLookup;

    function run() public {
        runWithArgs(
            vm.envUint("PRIVATE_KEY_MAIN"), // deployerPrivateKey
            new uint256[](0), // corpOwnerPrivateKeys
            type(uint256).max // maxCount
        );
    }

    /// @dev Input argument is not private key because tests will prank the deployer for real-world simulation
    function runWithArgs(
        uint256 deployerPrivateKey,
        uint256[] memory corpOwnerPrivateKeys,
        uint256 maxCount
    ) public {
        address deployer = vm.addr(deployerPrivateKey);
        string memory saltStr = "MetaLexCyberCorp.PublicRounds.UpgradeV3.0.1";
        bytes32 salt = bytes32(keccak256(bytes(saltStr)));

        // Compile a lookup table of corp owners (for accepting upgrades)
        for (uint256 i = 0; i < corpOwnerPrivateKeys.length; i++) {
            address corpOwner = vm.addr(corpOwnerPrivateKeys[i]);
            corpOwnerPrivateKeyLookup[corpOwner] = corpOwnerPrivateKeys[i];
        }

        console2.log("deployer: %s", deployer);
        console2.log("salt string: %s", saltStr);
        console2.log("loaded corp owners: %d", corpOwnerPrivateKeys.length);

        CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
        RoundManagerFactory deprecatingRmFactory = RoundManagerFactory(0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34); // deprecated develop-version of v3 RoundManagerFactory

        // Get the current factory addresses
        CyberCorpSingleFactory cyberCorpSingleFactory = CyberCorpSingleFactory(cyberCorpFactory.cyberCorpSingleFactory());
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(cyberCorpFactory.issuanceManagerFactory());
        DealManagerFactory dmFactory = DealManagerFactory(cyberCorpFactory.dealManagerFactory());
        RoundManagerFactory rmFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());

        ILegacyFactory legacyImFactory = ILegacyFactory(0xA32547aAdAA4975082D729c79e79dBaE4385EBCf);

        // Load all known cyber corps
        address[] memory knownLegacyCyberCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps.json", maxCount);
        // TODO WIP
//        address[] memory knownDevV3CyberCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-dev-v3-cyber-corps.json", maxCount);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy temporary contracts for migration

        IssuanceManagerWithFactoryMigration imWithMigrationImpl = new IssuanceManagerWithFactoryMigration();
        RoundManagerWithFactoryMigration rmWithMigrationImpl = new RoundManagerWithFactoryMigration();

        // Sanity check: the hard-coded factory addresses should match the current factories
        vm.assertEq(
            imWithMigrationImpl.NEW_UPGRADE_FACTORY(),
            address(imFactory),
            string(abi.encodePacked("IssuanceManagerWithFactoryMigration.NEW_UPGRADE_FACTORY should point to the current factory"))
        );
        vm.assertEq(
            rmWithMigrationImpl.NEW_UPGRADE_FACTORY(),
            address(rmFactory),
            string(abi.encodePacked("RoundManagerWithFactoryMigration.NEW_UPGRADE_FACTORY should point to the current factory"))
        );

        // Upgrade issuance manager beacon to a special implementation with migration features
        legacyImFactory.upgradeImplementation(address(imWithMigrationImpl));
        vm.assertEq(legacyImFactory.getBeaconImplementation(), address(imWithMigrationImpl), "beacon implementation should be upgraded with migration features by now");
        console2.log("Set new beacon implementation (with migration features): %s for legacy IssuanceManagerFactory: %s", address(imWithMigrationImpl), address(legacyImFactory));

        // Set the reference implementation on the deprecating RoundManagerFactory (so the corps can accept it)
        deprecatingRmFactory.setRefImplementation(address(rmWithMigrationImpl));

        vm.stopBroadcast();

        // Migrate each legacy corp one-by-one
        for (uint256 i = 0; i < knownLegacyCyberCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownLegacyCyberCorps[i]);

            // Sanity check: all other factories should match
            vm.assertEq(
                corp.upgradeFactory(),
                address(cyberCorpSingleFactory),
                string(abi.encodePacked("legacy cyberCorp: ", vm.toString(address(corp)), " should point to the current CyberCorpSingleFactory"))
            );
            vm.assertEq(
                _getDealManagerUpgradeFactory(corp.dealManager()),
                address(dmFactory),
                string(abi.encodePacked("legacy cyberCorp: ", vm.toString(address(corp)), " should point to the current DealManagerFactory"))
            );

            // Migrate legacy corp's IssuanceManager (beacon-based)
            vm.startBroadcast(deployerPrivateKey);

            IssuanceManagerWithFactoryMigration im = IssuanceManagerWithFactoryMigration(corp.issuanceManager());
            im.migrateUpgradeFactory();
            vm.assertEq(
                im.getUpgradeFactory(),
                address(imFactory),
                string(abi.encodePacked("legacy cyberCorp: ", vm.toString(address(corp)), " should point to the current IssuanceManagerFactory after migration"))
            );

            vm.stopBroadcast();

            // Migrate legacy corp's RoundManager (UUPSUpgradeable-based, need co-approval)

            // TODO WIP: simulate co-approval for now, in production we should use `corpOwnerPrivateKeyLookup`
//            vm.startBroadcast(corpOwnerPrivateKeyLookup[corp.companyPayable()]);
            vm.startPrank(corp.companyPayable());

            // Accept round manager upgrade to the temporary implementation with migration feature
            RoundManagerWithFactoryMigration rm = RoundManagerWithFactoryMigration(corp.roundManager());
            rm.upgradeToAndCall(
                address(rmWithMigrationImpl),
                abi.encodeWithSelector(rm.migrateUpgradeFactory.selector) // perform migration atomically
            );
            vm.assertEq(
                rm.getUpgradeFactory(),
                address(rmFactory),
                string(abi.encodePacked("legacy cyberCorp: ", vm.toString(address(corp)), " should point to the current RoundManagerFactory after migration"))
            );

//            vm.stopBroadcast();
            vm.stopPrank();

            console2.log("Migrated legacy CyberCorp: %s", address(corp));
        }

        // Revert to the normal implementation since migration is done
        vm.startBroadcast(deployerPrivateKey);

        address imRefImpl = imFactory.getRefImplementation();
        legacyImFactory.upgradeImplementation(imRefImpl);
        vm.assertEq(legacyImFactory.getBeaconImplementation(), imRefImpl, "beacon implementation should be upgraded without migration features by now");
        console2.log("Set new beacon implementation (without migration features): %s for legacy CyberCorpSingleFactory: %s", address(imRefImpl), address(legacyImFactory));

        // No need to revert deprecatingRmFactory.refImplementation() since it is deprecating

        vm.stopBroadcast();
    }

    function _getDealManagerUpgradeFactory(address target) internal view returns (address) {
        // `upgradeFactory` is at slot 1 of `DealManagerStorage.STORAGE_POSITION`
        bytes32 slotData = vm.load(target, bytes32(uint256(DealManagerStorage.STORAGE_POSITION) + 1));
        return address(uint160(uint256(slotData)));
    }
}

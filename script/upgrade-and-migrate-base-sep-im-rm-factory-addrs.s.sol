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

contract UpgradeAndMigrateBaseSepImRmFactoryAddrsScript is Script {
    mapping(address => uint256) private corpOwnerPrivateKeyLookup;

    function run() public {
        runWithArgs(
            vm.envUint("PRIVATE_KEY_MAIN"), // deployerPrivateKey
            vm.envUint("CORP_OWNER_PKS", ","), // corpOwnerPrivateKeys
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
        CyberCorpSingleFactory cyberCorpSingleFactory = CyberCorpSingleFactory(cyberCorpFactory.cyberCorpSingleFactory());
        DealManagerFactory dmFactory = DealManagerFactory(cyberCorpFactory.dealManagerFactory());

        // Legacy corp's IssuanceManagerFactory (for upgrading beacons)
        ILegacyFactory legacyImFactory = ILegacyFactory(0xA32547aAdAA4975082D729c79e79dBaE4385EBCf);

        // Deprecated develop-version of v3 RoundManagerFactory (we need it later for providing reference implementation with migration features)
        IssuanceManagerFactory deprecatingImFactory = IssuanceManagerFactory(0xbbD386D237f3b407E6511A52488850b1Da0cCad2);
        RoundManagerFactory deprecatingRmFactory = RoundManagerFactory(0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34);

        // Newly deployed factories that we want to use
        IssuanceManagerFactory imFactory = IssuanceManagerFactory(0xD353972D7955F421d94d0eA8c42c88c417F7155A);
        RoundManagerFactory rmFactory = RoundManagerFactory(0xc9d5d0DeDD124f9351E5880469f25AB41869aeb9);

        vm.startBroadcast(deployerPrivateKey);

        // 1) Replace CyberCorpFactory's IssuanceManagerFactory with the newly deployed ones
        // Set new IssuanceManager's reference implementation to the old one since they are functionally identical
        address refIm = deprecatingImFactory.getRefImplementation();
        imFactory.setRefImplementation(refIm);
        cyberCorpFactory.setIssuanceManagerFactory(address(imFactory));
        vm.assertEq(cyberCorpFactory.issuanceManagerFactory(), address(imFactory), "unexpected IssuanceManagerFactory");
        vm.assertEq(imFactory.getRefImplementation(), refIm, "unexpected IssuanceManager reference implementation");
        console2.log("CyberCorpFactory.issuanceManagerFactory set to: %s", address(imFactory));

        // 2) Replace CyberCorpFactory's RoundManagerFactory with the newly deployed ones
        cyberCorpFactory.setRoundManagerFactory(address(rmFactory));
        vm.assertEq(cyberCorpFactory.roundManagerFactory(), address(rmFactory), "unexpected RoundManagerFactory");
        console2.log("CyberCorpFactory.roundManagerFactory set to: %s", address(rmFactory));

        // Load all known cyber corps
        address[] memory knownLegacyCyberCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps.json", maxCount);
        address[] memory knownDevV3CyberCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps-v3-dev.json", maxCount);

        // 3) Deploy temporary contracts for migration

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

        // 4a) Upgrade issuance manager beacon to a special implementation with migration features
        legacyImFactory.upgradeImplementation(address(imWithMigrationImpl));
        vm.assertEq(legacyImFactory.getBeaconImplementation(), address(imWithMigrationImpl), "beacon implementation should be upgraded with migration features by now");
        console2.log("Set new beacon implementation (with migration features): %s for legacy IssuanceManagerFactory: %s", address(imWithMigrationImpl), address(legacyImFactory));

        // 4b) Set the reference implementation on the deprecating IssuanceManagerFactory (so the dev-v3 corps can accept it)
        deprecatingImFactory.setRefImplementation(address(imWithMigrationImpl));

        // 4c) Set the reference implementation on the deprecating RoundManagerFactory (so the corps can accept it)
        deprecatingRmFactory.setRefImplementation(address(rmWithMigrationImpl));

        vm.stopBroadcast();

        // 5) Migrate each legacy corp one-by-one
        for (uint256 i = 0; i < knownLegacyCyberCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownLegacyCyberCorps[i]);

            // If we don't have the corp owner's private key, we will skip migrating the corp completely so it does not stuck in an intermediate state
            uint256 corpOwnerPrivateKey = corpOwnerPrivateKeyLookup[corp.companyPayable()];
            if (corpOwnerPrivateKey == 0) {
                console2.log("private key not found for legacy corp owner: %s, skipping corp: %s", corp.companyPayable(), address(corp));
                continue;
            }

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
            vm.startBroadcast(corpOwnerPrivateKey);

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

            vm.stopBroadcast();

            console2.log("Migrated legacy CyberCorp: %s", address(corp));
        }

        // 6) Migrate each dev-v3 corp one-by-one
        for (uint256 i = 0; i < knownDevV3CyberCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownDevV3CyberCorps[i]);

            // If we don't have the corp owner's private key, we will skip migrating the corp completely so it does not stuck in an intermediate state
            uint256 corpOwnerPrivateKey = corpOwnerPrivateKeyLookup[corp.companyPayable()];
            if (corpOwnerPrivateKey == 0) {
                console2.log("private key not found for dev-v3 corp owner: %s, skipping corp: %s", corp.companyPayable(), address(corp));
                continue;
            }

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
            
            vm.startBroadcast(corpOwnerPrivateKey);

            // Migrate legacy corp's IssuanceManager (UUPSUpgradeable-based, need co-approval)
            // Accept round manager upgrade to the temporary implementation with migration feature
            IssuanceManagerWithFactoryMigration im = IssuanceManagerWithFactoryMigration(corp.issuanceManager());
            im.upgradeToAndCall(
                address(imWithMigrationImpl),
                abi.encodeWithSelector(im.migrateUpgradeFactory.selector) // perform migration atomically
            );
            vm.assertEq(
                im.getUpgradeFactory(),
                address(imFactory),
                string(abi.encodePacked("legacy cyberCorp: ", vm.toString(address(corp)), " should point to the current IssuanceManagerFactory after migration"))
            );

            // Migrate legacy corp's RoundManager (UUPSUpgradeable-based, need co-approval)
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

            vm.stopBroadcast();

            console2.log("Migrated dev-v3 CyberCorp: %s", address(corp));
        }

        // 7a) Revert to the normal implementation since migration is done
        vm.startBroadcast(deployerPrivateKey);

        address imRefImpl = imFactory.getRefImplementation();
        legacyImFactory.upgradeImplementation(imRefImpl);
        vm.assertEq(legacyImFactory.getBeaconImplementation(), imRefImpl, "beacon implementation should be upgraded without migration features by now");
        console2.log("Set new beacon implementation (without migration features): %s for legacy IssuanceManagerFactory: %s", address(imRefImpl), address(legacyImFactory));

        // 7b) No need to revert deprecatingImFactory.refImplementation() since it is deprecating
        // 7c) No need to revert deprecatingRmFactory.refImplementation() since it is deprecating

        vm.stopBroadcast();
    }

    function _getDealManagerUpgradeFactory(address target) internal view returns (address) {
        // `upgradeFactory` is at slot 1 of `DealManagerStorage.STORAGE_POSITION`
        bytes32 slotData = vm.load(target, bytes32(uint256(DealManagerStorage.STORAGE_POSITION) + 1));
        return address(uint160(uint256(slotData)));
    }
}

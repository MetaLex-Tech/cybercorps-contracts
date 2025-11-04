// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console2} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerWithMigration} from "../src/IssuanceManagerWithMigration.sol";
import {ILegacyFactory} from "./interfaces/ILegacyFactory.sol";
import {KnownAddressesLoader} from "./libs/KnownAddressesLoader.sol";

contract UpgradeLegacyIssuanceManagersScript is Script {
    function run() public returns (IssuanceManagerWithMigration) {
        return run(type(uint256).max);
    }

    function run(uint256 maxCount) public returns (IssuanceManagerWithMigration) {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");

        CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);

        // CyberCertPrinter beacons are owned by each individual IssuanceManagers, so to upgrade them we must
        // enumerate all existing IssuanceManager addresses and their corresponding factories (https://dune.com/queries/6129394):
        // - 0xA32547aAdAA4975082D729c79e79dBaE4385EBCf
        // - 0xade5d9fBaC6201535dc558FBD247e6859f5aa8C5 (deprecated, won't touch it)
        ILegacyFactory legacyImFactory = ILegacyFactory(0xA32547aAdAA4975082D729c79e79dBaE4385EBCf);

        // Load all known cyber corps
        address[] memory knownIssuanceManagers = KnownAddressesLoader.load(block.chainid, "/script/res/known-issuance-managers.json", maxCount);

        vm.startBroadcast(deployerPrivateKey);

        //
        // Upgrade legacy DealManagers
        //

        // Upgrade beacon implementation to the new implementation (with migration feature)

        IssuanceManagerWithMigration imWithMigrationImpl = new IssuanceManagerWithMigration();

        // Expect new factory to be deployed at a predetermined address because we will hard-code it to the migration contract
        vm.assertEq(cyberCorpFactory.issuanceManagerFactory(), imWithMigrationImpl.NEW_UPGRADE_FACTORY(), "new issuanceManagerFactory address has changed, update it in IssuanceManagerWithMigration");

        legacyImFactory.upgradeImplementation(address(imWithMigrationImpl));
        vm.assertEq(legacyImFactory.getBeaconImplementation(), address(imWithMigrationImpl), "beacon implementation should be upgraded by now");
        console2.log("New beacon implementation: %s for legacy IssuanceManagerFactory: %s", address(imWithMigrationImpl), address(legacyImFactory));

        // This is the ugly part: One-time manual upgrade required for legacy DealManagers.
        // This section updates the `upgradeFactory` pointer to the new permanent factory address,
        // enabling access to updated fee-related methods. This migration is performed one-by-one
        // for each legacy IssuanceManager contract.

        // This is a ONE-TIME operation per legacy IssuanceManager's lifetime. Once updated,
        // the `upgradeFactory` is expected to remain permanent and unchanged for all following upgrades.
        for (uint256 i = 0; i < knownIssuanceManagers.length; i++) {
            IssuanceManagerWithMigration(knownIssuanceManagers[i]).migrateUpgradeFactory();
            vm.assertNotEq(IssuanceManagerFactory(IssuanceManager(knownIssuanceManagers[i]).getUpgradeFactory()).getRefImplementation(), address(0), "should be able to lookup reference implementation now");
            console2.log("Migrated legacy IssuanceManager: %s", knownIssuanceManagers[i]);
        }

        vm.stopBroadcast();

        return imWithMigrationImpl;
    }
}

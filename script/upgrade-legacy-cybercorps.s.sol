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
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpWithMigration} from "../src/CyberCorpWithMigration.sol";
import {ILegacyFactory} from "./interfaces/ILegacyFactory.sol";
import {KnownAddressesLoader} from "./libs/KnownAddressesLoader.sol";

contract UpgradeLegacyCyberCorpsScript is Script {
    function run() public returns (CyberCorpWithMigration) {
        return runWithArgs(type(uint256).max);
    }

    function runWithArgs(uint256 maxCount) public returns (CyberCorpWithMigration) {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3.0.1"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");

        CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
        CyberCorpSingleFactory cyberCorpSingleFactoryV2 = CyberCorpSingleFactory(cyberCorpFactory.cyberCorpSingleFactory()); // this is the v2 one (with reference implementation)

        // To upgrade the legacy beacon-based CyberCorps, we must enumerate all existing CyberCorp addresses
        // and their corresponding factories (https://dune.com/queries/6139033):
        // - 0xc8e084D3f8B3b326FCc894C7afD28F4904196406
        // - 0x93E3559240745931709421aD87AA0CD3040D0aDD (deprecated, won't touch it)
        ILegacyFactory legacyCyberCorpSingleFactory = ILegacyFactory(0xc8e084D3f8B3b326FCc894C7afD28F4904196406);

        // Load all known cyber corps
        address[] memory knownCyberCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps.json", maxCount);

        vm.startBroadcast(deployerPrivateKey);

        //
        // Upgrade legacy DealManagers
        //

        // Upgrade beacon implementation to the new implementation (with migration feature)

        CyberCorpWithMigration cyberCorpWithMigrationImpl = new CyberCorpWithMigration();

        // Expect new factory to be deployed at a predetermined address because we will hard-code it to the migration contract
        vm.assertEq(cyberCorpFactory.cyberCorpSingleFactory(), cyberCorpWithMigrationImpl.NEW_UPGRADE_FACTORY(), "new cyberCorpSingleFactory address has changed, update it in CyberCorpWithMigration");

        // Upgrade beacon to a special implementation with migration features
        legacyCyberCorpSingleFactory.upgradeImplementation(address(cyberCorpWithMigrationImpl));
        vm.assertEq(legacyCyberCorpSingleFactory.getBeaconImplementation(), address(cyberCorpWithMigrationImpl), "beacon implementation should be upgraded with migration features by now");
        console2.log("Set new beacon implementation (with migration features): %s for legacy CyberCorpSingleFactory: %s", address(cyberCorpWithMigrationImpl), address(legacyCyberCorpSingleFactory));

        // This is the ugly part: One-time manual upgrade required for legacy DealManagers.
        // This section updates the `upgradeFactory` pointer to the new permanent factory address,
        // enabling access to updated fee-related methods. This migration is performed one-by-one
        // for each legacy CyberCorp contract.

        // This is a ONE-TIME operation per legacy CyberCorp's lifetime. Once updated,
        // the `upgradeFactory` is expected to remain permanent and unchanged for all following upgrades.
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            CyberCorpWithMigration(knownCyberCorps[i]).migrateUpgradeFactory();
            vm.assertNotEq(CyberCorpSingleFactory(CyberCorp(knownCyberCorps[i]).upgradeFactory()).getRefImplementation(), address(0), "should be able to lookup reference implementation now");
            console2.log("Migrated legacy CyberCorp: %s", knownCyberCorps[i]);
        }

        // Upgrade beacon to the normal implementation since migration is done
        address refImplementation = cyberCorpSingleFactoryV2.getRefImplementation();
        legacyCyberCorpSingleFactory.upgradeImplementation(refImplementation);
        vm.assertEq(legacyCyberCorpSingleFactory.getBeaconImplementation(), refImplementation, "beacon implementation should be upgraded without migration features by now");
        console2.log("Set new beacon implementation (without migration features): %s for legacy CyberCorpSingleFactory: %s", address(refImplementation), address(legacyCyberCorpSingleFactory));

        vm.stopBroadcast();

        return cyberCorpWithMigrationImpl;
    }
}

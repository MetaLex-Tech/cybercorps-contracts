// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {console} from "forge-std/console.sol";
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerWithMigration} from "../src/DealManagerWithMigration.sol";
import {ILegacyDealManagerFactory} from "./interfaces/ILegacyDealManagerFactory.sol";


contract UpgradeLegacyDealManagersScript is Script {

    function run() public returns (DealManagerWithMigration) {
        return upgradeLegacyDealManagers(
            vm.envAddress("DEAL_MANAGER_FACTORY_ADDR")
        );
    }

    function upgradeLegacyDealManagers(address newDealManagerFactory) public returns (DealManagerWithMigration) {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorpLaunchV2.3.Upgrade")); // TODO TBD
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");

        // To upgrade the legacy beacon-based DealManagers, we must first identify
        // all existing DealManagerFactory addresses (https://dune.com/queries/5981894):
        // - 0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3
        // - 0x15A399Dee2b25C5a766cd9480a154B13d128E669 (deprecated, won't touch it)
        ILegacyDealManagerFactory legacyDealManagerFactory = ILegacyDealManagerFactory(0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3);

        // Known deployed DealManager @ Ethereum mainnet
        // TODO Find all legacy DealManagers
        address[] memory knownDealManagers = new address[](3);
        knownDealManagers[0] = 0xB4dd83e4b12454a85AEc05e443e95c72a2c48D83;
        knownDealManagers[1] = 0x71B4DAC6237Ce73bf673CB9cb2b94257C975D69a;
        knownDealManagers[2] = 0x492685f1d34170F1B67e8B72cBD0f982E3E7e7a7;

        vm.startBroadcast(deployerPrivateKey);

        //
        // Upgrade legacy DealManagers
        //

        // Upgrade beacon implementation to the new implementation (with migration feature)
        DealManagerWithMigration dmWithMigrationImpl = new DealManagerWithMigration();
        legacyDealManagerFactory.upgradeImplementation(address(dmWithMigrationImpl));
        vm.assertEq(legacyDealManagerFactory.getBeaconImplementation(), address(dmWithMigrationImpl), "beacon implementation should be upgraded by now");
        console.log("New beacon implementation: %s for legacy DealManagerFactory: %s", address(dmWithMigrationImpl), address(legacyDealManagerFactory));

        // This is the ugly part: One-time manual upgrade required for legacy DealManagers.
        // This section updates the `upgradeFactory` pointer to the new permanent factory address,
        // enabling access to updated fee-related methods. This migration is performed one-by-one
        // for each legacy DealManager contract.

        // This is a ONE-TIME operation per legacy DealManager's lifetime. Once updated,
        // the `upgradeFactory` is expected to remain permanent and unchanged for all following upgrades.
        for (uint256 i = 0; i < knownDealManagers.length; i++) {
            DealManagerWithMigration(knownDealManagers[i]).migrateUpgradeFactory();
            vm.assertEq(DealManager(knownDealManagers[i]).getPlatformPayable(), address(0), "should be able to lookup fee payable now");
            console.log("Migrated legacy DealManager: %s", knownDealManagers[i]);
        }

        vm.stopBroadcast();

        return dmWithMigrationImpl;
    }
}

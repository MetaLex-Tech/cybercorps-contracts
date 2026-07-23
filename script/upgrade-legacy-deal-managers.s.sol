// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console2} from "forge-std/Test.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
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
import "../src/CyberCorpConstants.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {SAFTExtension} from "../src/storage/extensions/SAFTExtension.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerWithMigration} from "../src/DealManagerWithMigration.sol";
import {ILegacyFactory} from "./interfaces/ILegacyFactory.sol";
import {KnownAddressesLoader} from "./libs/KnownAddressesLoader.sol";
import {CyberCorp} from "../src/CyberCorp.sol";

contract UpgradeLegacyDealManagersScript is Script {
    function run() public returns (DealManagerWithMigration) {
        return runWithArgs(type(uint256).max);
    }

    function runWithArgs(uint256 maxCount) public returns (DealManagerWithMigration) {
        bytes32 salt = bytes32(keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3.0.2"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");

        address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
        CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
        DealManagerFactory dmFactoryV2 = DealManagerFactory(cyberCorpFactory.dealManagerFactory()); // this is the v2 one (with reference implementation)

        // To upgrade the legacy beacon-based DealManagers, we must enumerate all existing DealManager addresses
        // and their corresponding factories (https://dune.com/queries/5981894):
        // - 0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3
        // - 0x15A399Dee2b25C5a766cd9480a154B13d128E669 (deprecated, won't touch it)
        ILegacyFactory legacyDealManagerFactory = ILegacyFactory(0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3);

        // Load all known cyber corps
        address[] memory knownCyberCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps.json", maxCount);

        vm.startBroadcast(deployerPrivateKey);

        //
        // Upgrade legacy DealManagers
        //

        // Upgrade beacon implementation to the new implementation (with migration feature)
        DealManagerWithMigration dmWithMigrationImpl = new DealManagerWithMigration();

        // Expect new factory to be deployed at a predetermined address because we will hard-code it to the migration contract
        vm.assertEq(cyberCorpFactory.dealManagerFactory(), dmWithMigrationImpl.NEW_UPGRADE_FACTORY(), "new dealManagerFactory address has changed, update it in DealManagerWithMigration");

        // Upgrade beacon to a special implementation with migration features
        legacyDealManagerFactory.upgradeImplementation(address(dmWithMigrationImpl));
        vm.assertEq(legacyDealManagerFactory.getBeaconImplementation(), address(dmWithMigrationImpl), "beacon implementation should be upgraded by now");
        console2.log("New beacon implementation (with migration features): %s for legacy DealManagerFactory: %s", address(dmWithMigrationImpl), address(legacyDealManagerFactory));

        // This is the ugly part: One-time manual upgrade required for legacy DealManagers.
        // This section updates the `upgradeFactory` pointer to the new permanent factory address,
        // enabling access to updated fee-related methods. This migration is performed one-by-one
        // for each legacy DealManager contract.

        // This is a ONE-TIME operation per legacy DealManager's lifetime. Once updated,
        // the `upgradeFactory` is expected to remain permanent and unchanged for all following upgrades.
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            address dmAddr = CyberCorp(knownCyberCorps[i]).dealManager();
            DealManagerWithMigration(dmAddr).migrateUpgradeFactory();
            vm.assertEq(DealManager(dmAddr).getPlatformPayable(), metalexSafe, string(abi.encodePacked("DealManager: ", vm.toString(dmAddr), "should be able to lookup fee payable now")));
            console2.log("Migrated legacy DealManager: %s", dmAddr);
        }

        // Upgrade beacon to the normal implementation since migration is done
        address refImplementation = dmFactoryV2.getRefImplementation();
        legacyDealManagerFactory.upgradeImplementation(refImplementation);
        vm.assertEq(legacyDealManagerFactory.getBeaconImplementation(), refImplementation, "beacon implementation should be upgraded without migration features by now");
        console2.log("Set new beacon implementation (without migration features): %s for legacy DealManagerFactory: %s", address(refImplementation), address(legacyDealManagerFactory));

        vm.stopBroadcast();

        return dmWithMigrationImpl;
    }
}

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
import {DealManager as DealManagerMigrationOnly} from "../src/DealManagerMigrationOnly.sol";
import {ILegacyDealManagerFactory} from "./interfaces/ILegacyDealManagerFactory.sol";


contract UpgradeDealManagerScript is Script {

    function run() public {
        upgradeDealManager(
            bytes32(keccak256("MetaLexCyberCorpLaunchV2.3.Upgrade")), // TODO TBD: salt
            vm.envUint("PRIVATE_KEY_MAIN") // deployerPrivateKey
        );
    }

    function upgradeDealManager(bytes32 salt, uint256 deployerPrivateKey) public returns (DealManagerFactory, DealManagerMigrationOnly) {

        // Known deployed DealManager @ Ethereum mainnet
        // TODO Update it when needed for other network
        address[] memory knownDealManagers = new address[](3);
        knownDealManagers[0] = 0xB4dd83e4b12454a85AEc05e443e95c72a2c48D83;
        knownDealManagers[1] = 0x71B4DAC6237Ce73bf673CB9cb2b94257C975D69a;
        knownDealManagers[2] = 0x492685f1d34170F1B67e8B72cBD0f982E3E7e7a7;

        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Universal registry address
        address registry = address(CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134));
        BorgAuth auth = CyberAgreementRegistry(registry).AUTH();
        vm.assertEq(address(auth), 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01, "should match universal AUTH address");

        //
        // Upgrade DealManagerFactory
        //

        // Deploy new DealManager reference implementation
        DealManager refDm = new DealManager();
        console.log("New DealManager reference implementation deployed at: %s", address(refDm));

        // Deploy new UUPSUpgradeable DealManagerFactory
        DealManagerFactory newDmFactory = DealManagerFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new DealManagerFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        DealManagerFactory.initialize.selector,
                        address(auth),
                        address(refDm)
                    )
                )
            )
        );
        console.log("New DealManagerFactory deployed at: %s", address(newDmFactory));

        // Verify the upgrade was successful
        address updatedImplementation = newDmFactory.getRefImplementation();
        vm.assertEq(newDmFactory.getRefImplementation(), address(refDm), "unexpected reference implementation");

        //
        // Upgrade existing DealManagers
        //

        // To upgrade the legacy beacon-based DealManagers, we must first identify
        // all existing DealManagerFactory addresses (https://dune.com/queries/5981894):
        // - 0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3
        // - 0x15A399Dee2b25C5a766cd9480a154B13d128E669 (deprecated, won't touch it)
        ILegacyDealManagerFactory legacyDealManagerFactory = ILegacyDealManagerFactory(0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3);

        // Upgrade beacon implementation to the new implementation (with migration feature)
        DealManagerMigrationOnly dmWithMigrationImpl = new DealManagerMigrationOnly();
        legacyDealManagerFactory.upgradeImplementation(address(dmWithMigrationImpl));
        vm.assertEq(legacyDealManagerFactory.getBeaconImplementation(), address(dmWithMigrationImpl), "beacon implementation should be upgraded by now");
        console.log("New beacon implementation: %s for legacy DealManagerFactory: %s", address(dmWithMigrationImpl), address(legacyDealManagerFactory));

        // This is the ugly part: migrate existing DealManager one-by-one because they need to connect to
        // the new DealManagerFactory to lookup fee parameters (existing DealManagerFactory is not upgradeable)
        for (uint256 i = 0; i < knownDealManagers.length; i++) {
            DealManagerMigrationOnly(knownDealManagers[i]).migrateToV2_3();
            vm.assertEq(DealManager(knownDealManagers[i]).getPlatformPayable(), address(0), "should be able to lookup fee payable now");
            console.log("Migrated legacy DealManager: %s", knownDealManagers[i]);
        }

        return (newDmFactory, dmWithMigrationImpl);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UpgradeDealManagerScript} from "../script/upgrade-dealmanager.s.sol";
import {ILegacyDealManagerFactory} from "../script/interfaces/ILegacyDealManagerFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManager as DealManagerMigrationOnly} from "../src/DealManagerMigrationOnly.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";

contract UpgradeDealManagerTest is Test {
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Universal registry address
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    ILegacyDealManagerFactory legacyDealManagerFactory = ILegacyDealManagerFactory(0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3);

    // Known deployed DealManager @ Ethereum mainnet
    address[] knownDealManagers = new address[](3);

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
    address deployer = vm.addr(deployerPrivateKey);

    DealManagerFactory newDmFactory;
    DealManagerMigrationOnly dmWithMigrationImpl;

    function setUp() public {
        knownDealManagers[0] = 0xB4dd83e4b12454a85AEc05e443e95c72a2c48D83;
        knownDealManagers[1] = 0x71B4DAC6237Ce73bf673CB9cb2b94257C975D69a;
        knownDealManagers[2] = 0x492685f1d34170F1B67e8B72cBD0f982E3E7e7a7;

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        registry.AUTH().updateRole(deployer, registry.AUTH().OWNER_ROLE());
        vm.stopPrank();

        // Run upgrade scripts
        (newDmFactory, dmWithMigrationImpl) = (new UpgradeDealManagerScript()).upgradeDealManager(
            bytes32(keccak256("MetaLexCyberCorpLaunchV2.3.Upgrade")), // salt
            deployerPrivateKey
        );
    }

    function test_SanityCheck() public {
        // Script might've done it, but we'll do it again just in case
        assertEq(legacyDealManagerFactory.getBeaconImplementation(), address(dmWithMigrationImpl), "beacon implementation should be upgraded by now");
    }

    function test_ExistingDealManagerIntegrity() public {
        for (uint256 i = 0; i < knownDealManagers.length; i++) {
            // New DealManager should implement new methods
            assertEq(DealManager(knownDealManagers[i]).DEPLOY_VERSION(), "1", string(abi.encodePacked("unexpected DEPLOY_VERSION() for DealManager: ", vm.toString(knownDealManagers[i]))));
            assertEq(DealManager(knownDealManagers[i]).computeFee(1 ether), 0 ether, "upgraded DealManager should support fee calculation with no fees");
            assertEq(DealManager(knownDealManagers[i]).getPlatformPayable(), address(0), "upgraded DealManager should support fee payable");

            // TODO Should be able to propose deals
        }
    }

    function test_NewDealManagerIntegrity() public {
        // Deploy a new DealManager
        DealManager dm = DealManager(newDmFactory.deployDealManager(bytes32(keccak256("test_NewDealManagerIntegrity"))));

        // Simulate initialize() like CyberCorpFactory would do
        dm.initialize(
            address(1), // No-op
            address(1), // No-op
            address(1), // No-op
            address(1), // No-op
            address(newDmFactory)
        );

        // New DealManager should implement new methods
        assertEq(dm.DEPLOY_VERSION(), "1", "unexpected DEPLOY_VERSION()");
        assertEq(dm.computeFee(1 ether), 0 ether, "new DealManager should support fee calculation with no fees");
        assertEq(dm.getPlatformPayable(), address(0), "new DealManager should support fee payable");
    }
}

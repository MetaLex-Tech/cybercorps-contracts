// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UpgradeRoundManagerTokenWhitelistScript} from "../script/upgrade-round-manager-token-whitelist.s.sol";
import {KnownAddressesLoader} from "../script/libs/KnownAddressesLoader.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";

/// @notice This is for testing upgrading base-sepolia, which has been upgraded to a dev version of v3 before, to the current version of v3
contract UpgradeRoundManagerTokenWhitelistTest is Test {
    using ERC1967ProxyLib for address;
    
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Universal registry address
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
    BorgAuth deployedLexChexAddrAuth = BorgAuth(0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2);

    RoundManagerFactory rmFactory;

    address paymentToken = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC @ Base Sepolia

    uint256 legacyAddressesCount = 3; // Limit the number of legacy addresses we migrate during tests so it won't stress the RPC endpoints too much

    address[] knownLegacyCorps;

    address deployer;
    uint256 deployerPrivateKey;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    function setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        // Lock in specific chain ID and fork block
        assertEq(block.chainid, 84532, "This test is meant for only Base Sepolia @ 34732511");
        vm.rollFork(34732511);

        rmFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());

        // Load a limit number of known legacy cyber corps for tests
        knownLegacyCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps.json", legacyAddressesCount);

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        registry.AUTH().updateRole(deployer, registry.AUTH().OWNER_ROLE());
        vm.stopPrank();

        // Run scripts to upgrade RoundManager and its factory
        (new UpgradeRoundManagerTokenWhitelistScript()).runWithArgs(deployerPrivateKey);

        // Run scripts to accept the new RoundManager for the legacy corps (assuming they have all been migrated by now)
        for (uint256 i = 0; i < knownLegacyCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownLegacyCorps[i]);
            RoundManager rm = RoundManager(corp.roundManager());
            assertNotEq(
                address(rm),
                address(0),
                string(abi.encodePacked("legacy CyberCorp: ", vm.toString(address(corp)), " should have RoundManager by now"))
            );

            address refRmImpl = rmFactory.getRefImplementation();
            if (address(rm).getErc1967Implementation() != refRmImpl) {
                vm.prank(address(corp));
                rm.upgradeToAndCall(refRmImpl, "");
                console2.log("CyberCorp: %s accepted RoundManager upgrade to: %s", address(corp), refRmImpl);
            }
        }
    }

    function test_SanityCheck() public {
        for (uint256 i = 0; i < knownLegacyCorps.length; i++) {
            CyberCorp corp = CyberCorp(knownLegacyCorps[i]);
            RoundManager rm = RoundManager(corp.roundManager());
            // RoundManager should be at current implementation
            assertEq(address(rm).getErc1967Implementation(), rmFactory.getRefImplementation(), string(abi.encodePacked("CyberCorp: ", vm.toString(address(corp)), " should have up-to-date implementation for its roundManager")));
        }
    }
}

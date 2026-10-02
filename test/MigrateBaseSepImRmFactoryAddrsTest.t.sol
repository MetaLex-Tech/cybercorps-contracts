// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberCorpHelper} from "../test/RoundManagerTest.t.sol";
import {CyberAgreementUtils} from "../test/libs/CyberAgreementUtils.sol";
import {UpgradePublicRoundsBaseSepoliaScript} from "../script/upgrade-public-rounds-base-sep.s.sol";
import {UpgradeAndMigrateBaseSepImRmFactoryAddrsScript} from "../script/upgrade-and-migrate-base-sep-im-rm-factory-addrs.s.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {CyberCertData, RoundType} from "../src/interfaces/IRoundManager.sol";
import {EOI, LexChexDetails, MintRequest} from "../src/storage/RoundManagerStorage.sol";
import {Accreditation} from "../src/creds/storage/lexchexStorage.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";

contract MigrateBaseSepImRmFactoryAddrsTest is Test {
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Assume Base-sepolia
    ERC20 usdc = ERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e);
    CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    BorgAuth lexChexAuth = BorgAuth(0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2);
    LeXcheX lexchex = LeXcheX(0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62);
    LeXcheXMinter leXcheXMinter = LeXcheXMinter(0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960);
    address lexchexConditionAddr = 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42;

    address deployer;
    uint256 deployerPrivateKey;

    function setUp() public {
        vm.label(address(cyberCorpFactory), "CyberCorpFactory");
        vm.label(address(usdc), "USDC");
        vm.label(address(registry), "CyberAgreementRegistry");
        vm.label(address(lexChexAuth), "lexChexAuth");
        vm.label(address(lexChexAuth), "lexChexAuth");
        vm.label(address(lexchex), "LeXcheX");
        vm.label(address(leXcheXMinter), "LeXcheXMinter");
        vm.label(address(lexchexConditionAddr), "lexchexCondition");

        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        CyberAgreementRegistry(registry).AUTH().updateRole(
            deployer,
            CyberAgreementRegistry(registry).AUTH().OWNER_ROLE()
        );
        lexChexAuth.updateRole(
            deployer,
            lexChexAuth.OWNER_ROLE()
        ); // so deployer can grant cyberCorpFactory permissions to it
        vm.stopPrank();

        // simulate migrations
        (new UpgradeAndMigrateBaseSepImRmFactoryAddrsScript()).runWithArgs(
            deployerPrivateKey,
            vm.envUint("CORP_OWNER_PKS", ","), // deployer is also the test corp owner
            4
        );

        // Revoke deployer admin access
        vm.startPrank(metalexSafe);
        CyberAgreementRegistry(registry).AUTH().updateRole(deployer, 0);
        lexChexAuth.updateRole(deployer, 0);
        vm.stopPrank();
    }

    function test_SanityCheck() public {
    }
}

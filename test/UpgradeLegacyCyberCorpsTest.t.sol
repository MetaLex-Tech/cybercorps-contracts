// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {UpgradePublicRoundsScript} from "../script/upgrade-public-rounds.s.sol";
import {UpgradeLegacyCyberCorpsScript} from "../script/upgrade-legacy-cybercorps.s.sol";
import {UpgradeLegacyDealManagersScript} from "../script/upgrade-legacy-deal-managers.s.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";
import {ILegacyIssuanceManagerFactory} from "../script/interfaces/ILegacyIssuanceManagerFactory.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {KnownAddressesLoader} from "../script/libs/KnownAddressesLoader.sol";
import {SecurityClass, SecuritySeries, CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpWithMigration} from "../src/CyberCorpWithMigration.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerWithMigration} from "../src/DealManagerWithMigration.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerWithMigration} from "./helpers/IssuanceManagerWithMigration.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";

contract MockImplVTest is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "test";

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override {}
}

contract UpgradeLegacyCyberCorpsTest is Test {
    using ERC1967ProxyLib for address;
    
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Universal registry address
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
    BorgAuth deployedLexChexAddrAuth = BorgAuth(0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2);
    ILegacyFactory legacyCyberCorpSingleFactory = ILegacyFactory(0xc8e084D3f8B3b326FCc894C7afD28F4904196406);
    ILegacyFactory legacyDealManagerFactory = ILegacyFactory(0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3);
    ILegacyIssuanceManagerFactory legacyIssuanceManagerFactory = ILegacyIssuanceManagerFactory(0xA32547aAdAA4975082D729c79e79dBaE4385EBCf);

    address paymentToken = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC @ Base Sepolia

    uint256 legacyAddressesCount = 3; // Limit the number of legacy addresses we migrate during tests so it won't stress the RPC endpoints too much

    address[] knownCyberCorps;

    // Randomly generated to avoid contaminated common test addresses
    uint256 privateKeySalt = 0xe6fc9058b04996425a6f0e6479e6e06f7177a6c61043b10857eb0a72339853e0;
    
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
    address deployer = vm.addr(deployerPrivateKey);
    uint256 alicePrivateKey = 0xa11ce + privateKeySalt;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 0xb0b + privateKeySalt;
    address bob = vm.addr(bobPrivateKey);

    CyberCorpSingleFactory newCyberCorpSingleFactory;
    DealManagerFactory newDmFactory;
    IssuanceManagerFactory newImFactory;
    RoundManagerFactory newRmFactory;

    // Deal test related
    bytes32 templateId = bytes32(uint256(10000));
    string contractUri = "ipfs.io/ipfs/[cid]";
    string[] globalFields;
    string[] partyFields;
    address[] defaultParties = new address[](2);
    string[] defaultGlobalValues = new string[](1);
    string[][] defaultPartyValues = new string[][](2);
    CyberCorpFactory.CyberCertData[] defaultCertData = new CyberCorpFactory.CyberCertData[](1);
    CertificateDetails[] defaultCertDetails = new CertificateDetails[](1);

    function setUp() public {
        //
        // Prepare for upgrades
        //

        // For future-proof: some networks may have upgraded already. In such case we will roll back to a known block before the upgrades
        if (block.chainid == 84532) {
            console2.log("Existing deployment has been upgraded, rolling back to a known block before it...");
            vm.rollFork(33920951);
        }

        // Load all known managers
        knownCyberCorps = KnownAddressesLoader.load(block.chainid, "/script/res/known-cyber-corps.json", legacyAddressesCount);

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        registry.AUTH().updateRole(deployer, registry.AUTH().OWNER_ROLE());
        deployedLexChexAddrAuth.updateRole(deployer, deployedLexChexAddrAuth.OWNER_ROLE()); // so deployer can grant cyberCorpFactory permissions to it
        vm.stopPrank();

        //
        // Prepare for deal tests
        //

        globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        vm.startPrank(metalexSafe);
        registry.createTemplate(
            templateId,
            "Test",
            contractUri,
            globalFields,
            partyFields
        );
        vm.stopPrank();
        
        defaultParties[0] = alice;
        defaultParties[1] = bob;
        
        defaultGlobalValues[0] = "Test global 0";
        
        defaultPartyValues[0] = new string[](1);
        defaultPartyValues[0][0] = "Test party 0-0";
        defaultPartyValues[1] = new string[](1);
        defaultPartyValues[1][0] = "Test party 1-0";
        
        defaultCertDetails[0] = CertificateDetails({
            signingOfficerName: "Alice",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 100,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 0,
            legalDetails: "test legal details",
            extensionData: ""
        });
        
        defaultCertData[0] = CyberCorpFactory.CyberCertData({
            name: "Test",
            symbol: "TEST",
            uri: "ipfs://test",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: new string[](0),
            printerExtensionData: hex""
        });
    }

    function test_SanityCheck() public {
        _upgradeFactoryAndLegacyCyberCorps();

        // Script might've done it, but we'll do it again just in case
        assertEq(
            legacyCyberCorpSingleFactory.getBeaconImplementation(),
            newCyberCorpSingleFactory.getRefImplementation(),
            "legacy CyberCorp beacon implementation should be upgraded by now"
        );
        assertEq(
            legacyDealManagerFactory.getBeaconImplementation(),
            newDmFactory.getRefImplementation(),
            "legacy DealManager beacon implementation should be upgraded by now"
        );
        assertEq(
            legacyIssuanceManagerFactory.getBeaconImplementation(),
            newImFactory.getRefImplementation(),
            "legacy IssuanceManager beacon implementation should be upgraded by now"
        );
    }

    function test_LegacyCyberCorpIntegrity() public {
        // Snapshot slot contents before upgrade
        BorgAuth[] memory expectedAuths = new BorgAuth[](knownCyberCorps.length);
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            expectedAuths[i] = CyberCorp(knownCyberCorps[i]).AUTH();
        }

        // Perform upgrades
        _upgradeFactoryAndLegacyCyberCorps();

        // Verify integrity
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            // New CyberCorp should implement new methods
            assertEq(CyberCorp(knownCyberCorps[i]).DEPLOY_VERSION(), "3", string(abi.encodePacked("unexpected DEPLOY_VERSION() for CyberCorp: ", vm.toString(knownCyberCorps[i]))));
            assertNotEq(CyberCorpSingleFactory(CyberCorp(knownCyberCorps[i]).upgradeFactory()).getRefImplementation(), address(0), "upgraded CyberCorp should be able to find reference implementation");

            // Check for slot conflicts
            assertEq(address(CyberCorp(knownCyberCorps[i]).AUTH()), address(expectedAuths[i]), string(abi.encodePacked("AUTH should not change for CyberCorp: ", vm.toString(knownCyberCorps[i]))));

            // Should have RoundManager now
            assertEq(CyberCorp(knownCyberCorps[i]).roundManager().getErc1967Implementation(), newRmFactory.getRefImplementation(), "should have up-to-date RoundManager");

            // Should still be able to verify that this legacy contract is a BeaconProxy (for front-end to differentiate legacy vs v3 contracts)
            assertEq(knownCyberCorps[i].getErc1967Beacon(), legacyCyberCorpSingleFactory.beacon(), "should be able to get beacon address");
        }

        // Legacy CyberCorpSingleFactory should be able to unilaterally upgrade its beacon
        vm.startPrank(metalexSafe);
        legacyCyberCorpSingleFactory.upgradeImplementation(address(new MockImplVTest()));
        vm.stopPrank();
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            assertEq(CyberCorp(knownCyberCorps[i]).DEPLOY_VERSION(), "test", "CyberCorp should be upgraded again");
        }
    }

    function test_LegacyDealManagerIntegrity() public {
        // Snapshot slot contents before upgrade
        BorgAuth[] memory expectedAuths = new BorgAuth[](knownCyberCorps.length);
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            expectedAuths[i] = DealManager(CyberCorp(knownCyberCorps[i]).dealManager()).AUTH();
        }

        // Perform upgrades
        _upgradeFactoryAndLegacyCyberCorps();

        // Verify integrity
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            address dmAddr = CyberCorp(knownCyberCorps[i]).dealManager();
            // New DealManager should implement new methods                                                                                                                                                                                                                                     
            assertEq(DealManager(dmAddr).DEPLOY_VERSION(), "3", string(abi.encodePacked("unexpected DEPLOY_VERSION() for DealManager: ", vm.toString(dmAddr))));
            assertEq(DealManager(dmAddr).computeFee(1 ether), 0.003 ether, "upgraded DealManager should support fee calculation");
            assertEq(DealManager(dmAddr).getPlatformPayable(), metalexSafe, "upgraded DealManager should support fee payable");

            // Check for slot conflicts
            assertEq(address(DealManager(dmAddr).AUTH()), address(expectedAuths[i]), string(abi.encodePacked("AUTH should not change for DealManager: ", vm.toString(dmAddr))));

            // Should still be able to verify that this legacy contract is a BeaconProxy (for front-end to differentiate legacy vs v3 contracts)
            assertEq(dmAddr.getErc1967Beacon(), legacyDealManagerFactory.beacon(), "should be able to get beacon address");
        }

        // Legacy DealManagerFactory should be able to unilaterally upgrade its beacon
        vm.startPrank(metalexSafe);
        legacyDealManagerFactory.upgradeImplementation(address(new MockImplVTest()));
        vm.stopPrank();
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            assertEq(DealManager(CyberCorp(knownCyberCorps[i]).dealManager()).DEPLOY_VERSION(), "test", "DealManager should be upgraded again");
        }
    }

    function test_LegacyIssuanceManagerIntegrity() public {
        // Snapshot slot contents before upgrade
        BorgAuth[] memory expectedAuths = new BorgAuth[](knownCyberCorps.length);
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            expectedAuths[i] = BorgAuth(IIssuanceManager(CyberCorp(knownCyberCorps[i]).issuanceManager()).AUTH());
        }

        // Perform upgrades
        _upgradeFactoryAndLegacyCyberCorps();

        // Verify integrity
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            address imAddr = CyberCorp(knownCyberCorps[i]).issuanceManager();
            // New IssuanceManager should implement new methods
            assertEq(IIssuanceManager(imAddr).DEPLOY_VERSION(), "3", string(abi.encodePacked("unexpected DEPLOY_VERSION() for IssuanceManager: ", vm.toString(imAddr))));
            assertNotEq(IssuanceManagerFactory(IIssuanceManager(imAddr).getUpgradeFactory()).getRefImplementation(), address(0), "upgraded IssuanceManager should be able to find reference implementation");

            // Check for slot conflicts
            assertEq(address(IIssuanceManager(imAddr).AUTH()), address(expectedAuths[i]), string(abi.encodePacked("AUTH should not change for IssuanceManager: ", vm.toString(imAddr))));

            // its beacon implementations should be upgraded to the reference implementations
            _assertIssuanceManagerBeacons(imAddr);

            // IssuanceManagerFactory should be no longer able to unilaterally upgrade CyberCertPrinter
            vm.startPrank(metalexSafe);
            // Because `upgradeBeaconImplementation()` is no longer implemented in the new IssuanceManager;
            // furthermore, it will no longer allow the factory to unilaterally upgrade CyberCertPrinter
            vm.expectRevert();
            ILegacyIssuanceManagerFactory(legacyIssuanceManagerFactory).upgradePrinterBeaconAt(
                imAddr,
                address(0) // no-op
            );
            vm.stopPrank();

            // Should still be able to verify that this legacy contract is a BeaconProxy (for front-end to differentiate legacy vs v3 contracts)
            assertEq(imAddr.getErc1967Beacon(), legacyIssuanceManagerFactory.beacon(), "should be able to get beacon address");
        }

        // Legacy IssuanceManagerFactory should be able to unilaterally upgrade its beacon
        vm.startPrank(metalexSafe);
        legacyIssuanceManagerFactory.upgradeImplementation(address(new MockImplVTest()));
        vm.stopPrank();
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            assertEq(IIssuanceManager(CyberCorp(knownCyberCorps[i]).issuanceManager()).DEPLOY_VERSION(), "test", "IssuanceManager should be upgraded again");
        }
    }

    function test_LegacyDealManagerProposeDeal() public {
        _upgradeFactoryAndLegacyCyberCorps();

        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            address dmAddr = CyberCorp(knownCyberCorps[i]).dealManager();
            address cyberCorp = DealManager(dmAddr).issuanceManager().CORP();
            vm.startPrank(cyberCorp);

            address[] memory certPrinterAddress = new address[](1);
            for (uint256 j = 0; j < defaultCertData.length; j++) {
                certPrinterAddress[j] = IIssuanceManager(DealManager(dmAddr).issuanceManager()).createCertPrinter(
                    defaultCertData[j].defaultLegend,
                    string.concat("TestCorp", defaultCertData[j].name),
                    defaultCertData[j].symbol,
                    defaultCertData[j].uri,
                    defaultCertData[j].securityClass,
                    defaultCertData[j].securitySeries,
                    defaultCertData[j].extension,
                    defaultCertData[j].printerExtensionData
                );
            }

            uint256 agreementSalt = block.timestamp + i;

            // Create and sign deal
            (
                bytes32 agreementId,
                uint256[] memory certIds
            ) = DealManager(dmAddr).proposeAndSignDeal(
                certPrinterAddress,
                paymentToken,
                100e6,
                templateId,
                agreementSalt,
                defaultGlobalValues,
                defaultParties,
                defaultCertDetails,
                alice,
                CyberAgreementUtils.signAgreementTypedData(
                    vm,
                    registry.DOMAIN_SEPARATOR(),
                    registry.SIGNATUREDATA_TYPEHASH(),
                    keccak256(abi.encode(
                        templateId,
                        agreementSalt,
                        defaultGlobalValues,
                        defaultParties
                    )),
                    contractUri,
                    globalFields,
                    partyFields,
                    defaultGlobalValues,
                    defaultPartyValues[0],
                    alicePrivateKey
                ),
                defaultPartyValues,
                new address[](0),
                bytes32(0),
                block.timestamp + 1000000
            );

            vm.stopPrank();

            // Simulate counter-sign
            deal(address(paymentToken), bob, 100e6);
            uint256 companyPayableBalanceBefore = ERC20(paymentToken).balanceOf(CyberCorp(cyberCorp).companyPayable());

            vm.startPrank(bob);
            ERC20(paymentToken).approve(dmAddr, 100e6);

            DealManager(dmAddr).signAndFinalizeDeal(
                bob,
                agreementId,
                defaultPartyValues[1],
                CyberAgreementUtils.signAgreementTypedData(
                    vm,
                    registry.DOMAIN_SEPARATOR(),
                    registry.SIGNATUREDATA_TYPEHASH(),
                    agreementId,
                    contractUri,
                    globalFields,
                    partyFields,
                    defaultGlobalValues,
                    defaultPartyValues[1],
                    bobPrivateKey
                ),
                true,
                "Bob",
                ""
            );
            vm.stopPrank();

            assertEq(ERC20(paymentToken).balanceOf(CyberCorp(cyberCorp).companyPayable()) - companyPayableBalanceBefore, 100e6 - 0.3e6, "alice should receive payment minus fees");
        }
    }

    /// @notice After migration, legacy Corp should have RoundManager retrofitted. Since the RoundManager is a new deployment,
    /// it is of pure UUPSUpgradeable + ERC1967Proxy architecture and has the full upgrade-by-co-approval features.
    /// We will verify the upgradeability here
    function test_LegacyRetrofittedRoundManagerIntegrity() public {
        // Perform upgrades
        _upgradeFactoryAndLegacyCyberCorps();

        // Verify integrity
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            address rmAddr = CyberCorp(knownCyberCorps[i]).roundManager();
            // New RoundManager should implement new methods
            assertEq(RoundManager(rmAddr).DEPLOY_VERSION(), "3", string(abi.encodePacked("unexpected DEPLOY_VERSION() for RoundManager: ", vm.toString(rmAddr))));
            assertEq(RoundManager(rmAddr).computeFee(1 ether), 0.003 ether, "upgraded RoundManager should support fee calculation with no fees");
            assertEq(RoundManager(rmAddr).getPlatformPayable(), metalexSafe, "upgraded RoundManager should support fee payable");

            // Should be able to upgrade it by co-approval
            address testNewRmImpl = address(new MockImplVTest());
            vm.prank(metalexSafe);
            newRmFactory.setRefImplementation(testNewRmImpl);
            vm.prank(knownCyberCorps[i]);
            RoundManager(rmAddr).upgradeToAndCall(testNewRmImpl, "");
            assertEq(RoundManager(rmAddr).DEPLOY_VERSION(), "test", "RoundManager should be upgraded again");
        }
    }

    function test_NewDealManagerIntegrity() public {
        _upgradeFactoryAndLegacyCyberCorps();

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
        assertEq(dm.DEPLOY_VERSION(), "3", "unexpected DEPLOY_VERSION()");
        assertEq(dm.computeFee(1 ether), 0.003 ether, "new DealManager should support fee calculation with no fees");
        assertEq(dm.getPlatformPayable(), metalexSafe, "new DealManager should support fee payable");
    }

    function test_DeployNewCyberCorp() public {
        _upgradeFactoryAndLegacyCyberCorps();

        vm.startPrank(alice);
        (
            address cyberCorpAddress,
            ,
            address issuanceManagerAddress,
            address dealManagerAddress,
            address roundManagerAddress,
            address[] memory certPrinterAddress,
            ,

        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "TestCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            alice,
            CompanyOfficer({
                eoa: alice,
                name: "Alice",
                contact: "test@example.com",
                title: "CEO"
            }),
            defaultCertData,
            templateId,
            defaultGlobalValues,
            defaultParties,
            100e6,
            defaultPartyValues,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                keccak256(abi.encode(
                    templateId,
                    block.timestamp,
                    defaultGlobalValues,
                    defaultParties
                )),
                contractUri,
                globalFields,
                partyFields,
                defaultGlobalValues,
                defaultPartyValues[0],
                alicePrivateKey
            ),
            defaultCertDetails,
            new address[](0),
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();

        // Verify that new deployments are UUPSUpgradeable (so front-end can differentiate from from legacy contracts)
        assertEq(cyberCorpAddress.getErc1967Beacon(), address(0), "new CyberCorp should not be a BeaconProxy");
        assertEq(issuanceManagerAddress.getErc1967Beacon(), address(0), "new IssuanceManager should not be a BeaconProxy");
        assertEq(dealManagerAddress.getErc1967Beacon(), address(0), "new DealManager should not be a BeaconProxy");
        assertEq(roundManagerAddress.getErc1967Beacon(), address(0), "new RoundManager should not be a BeaconProxy");
        assertEq(certPrinterAddress[0].getErc1967Beacon(), address(IIssuanceManager(issuanceManagerAddress).cyberCertPrinterBeacon()), "new CyberCertPrinter should still be a BeaconProxy");
    }

    function test_EnableFeesNewCorp() public {
        _upgradeFactoryAndLegacyCyberCorps();

        vm.startPrank(metalexSafe);
        newDmFactory.setPlatformPayable(address(metalexSafe));
        newDmFactory.setDefaultFeeRatio(25);
        vm.stopPrank();

        vm.startPrank(alice);
        (
            address cyberCorp,
            address auth,
            address issuanceManager,
            address dm,
            address rm,
            address[] memory cyberCertPrinterAddr,
            bytes32 agreementId,
            uint256[] memory certIds
        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
            block.timestamp,
            "TestCorp",
            "Limited Liability Company",
            "Juris",
            "Contact Details",
            "Dispute Res",
            alice,
            CompanyOfficer({
                eoa: alice,
                name: "Alice",
                contact: "test@example.com",
                title: "CEO"
            }),
            defaultCertData,
            templateId,
            defaultGlobalValues,
            defaultParties,
            100e6,
            defaultPartyValues,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                keccak256(abi.encode(
                    templateId,
                    block.timestamp,
                    defaultGlobalValues,
                    defaultParties
                )),
                contractUri,
                globalFields,
                partyFields,
                defaultGlobalValues,
                defaultPartyValues[0],
                alicePrivateKey
            ),
            defaultCertDetails,
            new address[](0),
            bytes32(0),
            block.timestamp + 1000000
        );
        vm.stopPrank();

        deal(address(paymentToken), bob, 100e6);
        uint256 metalexSafeBalanceBefore = ERC20(paymentToken).balanceOf(metalexSafe);

        vm.startPrank(bob);
        ERC20(paymentToken).approve(dm, 100e6);

        DealManager(dm).signAndFinalizeDeal(
            bob,
            agreementId,
            defaultPartyValues[1],
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                contractUri,
                globalFields,
                partyFields,
                defaultGlobalValues,
                defaultPartyValues[1],
                bobPrivateKey
            ),
            true,
            "Bob",
            ""
        );
        vm.stopPrank();

        assertEq(ERC20(paymentToken).balanceOf(alice), 100e6 - 0.25e6, "alice should receive payment minus fees");
        assertEq(ERC20(paymentToken).balanceOf(metalexSafe) - metalexSafeBalanceBefore, 0.25e6, "MetaLex should receive fees");
    }

    function test_EnableFeesExistingCorp() public {
        _upgradeFactoryAndLegacyCyberCorps();

        vm.startPrank(metalexSafe);
        newDmFactory.setPlatformPayable(address(metalexSafe));
        newDmFactory.setDefaultFeeRatio(25);
        vm.stopPrank();

        address dmAddr = CyberCorp(knownCyberCorps[0]).dealManager();
        address cyberCorp = DealManager(dmAddr).issuanceManager().CORP();
        vm.startPrank(cyberCorp);

        address[] memory certPrinterAddress = new address[](1);
        for (uint256 j = 0; j < defaultCertData.length; j++) {
            certPrinterAddress[j] = IIssuanceManager(DealManager(dmAddr).issuanceManager()).createCertPrinter(
                defaultCertData[j].defaultLegend,
                string.concat("TestCorp", defaultCertData[j].name),
                defaultCertData[j].symbol,
                defaultCertData[j].uri,
                defaultCertData[j].securityClass,
                defaultCertData[j].securitySeries,
                defaultCertData[j].extension,
                defaultCertData[j].printerExtensionData
            );
        }

        uint256 agreementSalt = block.timestamp;

        // Create and sign deal
        (bytes32 agreementId, ) = DealManager(dmAddr).proposeAndSignDeal(
            certPrinterAddress,
            paymentToken,
            100e6,
            templateId,
            agreementSalt,
            defaultGlobalValues,
            defaultParties,
            defaultCertDetails,
            alice,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                keccak256(abi.encode(
                    templateId,
                    agreementSalt,
                    defaultGlobalValues,
                    defaultParties
                )),
                contractUri,
                globalFields,
                partyFields,
                defaultGlobalValues,
                defaultPartyValues[0],
                alicePrivateKey
            ),
            defaultPartyValues,
            new address[](0),
            bytes32(0),
            block.timestamp + 1000000
        );

        vm.stopPrank();

        deal(address(paymentToken), bob, 100e6);
        uint256 companyPayableBalanceBefore = ERC20(paymentToken).balanceOf(CyberCorp(cyberCorp).companyPayable());
        uint256 metalexSafeBalanceBefore = ERC20(paymentToken).balanceOf(metalexSafe);

        vm.startPrank(bob);
        ERC20(paymentToken).approve(dmAddr, 100e6);

        DealManager(dmAddr).signAndFinalizeDeal(
            bob,
            agreementId,
            defaultPartyValues[1],
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                agreementId,
                contractUri,
                globalFields,
                partyFields,
                defaultGlobalValues,
                defaultPartyValues[1],
                bobPrivateKey
            ),
            true,
            "Bob",
            ""
        );
        vm.stopPrank();

        assertEq(ERC20(paymentToken).balanceOf(CyberCorp(cyberCorp).companyPayable()) - companyPayableBalanceBefore, 100e6 - 0.25e6, "alice should receive payment minus fees");
        assertEq(ERC20(paymentToken).balanceOf(metalexSafe) - metalexSafeBalanceBefore, 0.25e6, "MetaLex should receive fees");
    }

    function _upgradeFactoryAndLegacyCyberCorps() internal {
        //
        // Simulate upgrades
        //

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        CyberAgreementRegistry(registry).AUTH().updateRole(
            deployer,
            CyberAgreementRegistry(registry).AUTH().OWNER_ROLE()
        );
        vm.stopPrank();

        // Upgrade all factories and dependencies
        (new UpgradePublicRoundsScript()).run();
        newCyberCorpSingleFactory = CyberCorpSingleFactory(cyberCorpFactory.cyberCorpSingleFactory());
        newDmFactory = DealManagerFactory(cyberCorpFactory.dealManagerFactory());
        newImFactory = IssuanceManagerFactory(cyberCorpFactory.issuanceManagerFactory());
        newRmFactory = RoundManagerFactory(cyberCorpFactory.roundManagerFactory());

        // Run scripts to upgrade all legacy CyberCorps
        (new UpgradeLegacyCyberCorpsScript()).runWithArgs(legacyAddressesCount);

        // Run scripts to upgrade all legacy DealManagers
        (new UpgradeLegacyDealManagersScript()).runWithArgs(legacyAddressesCount);

        // Upgrade legacy IssuanceManagers (script commented out in src/ due to contract size; inlined here for tests)
        _upgradeLegacyIssuanceManagers();

        // Simulate all legacy corp owners accept the new CyberCorpPrinter
        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            address imAddr = CyberCorp(knownCyberCorps[i]).issuanceManager();
            // Accept new CyberCertPrinter release
            vm.startPrank(imAddr);
            IIssuanceManager(imAddr).upgradeCertPrinterBeaconImplementation(
                IssuanceManagerFactory(cyberCorpFactory.issuanceManagerFactory()).getCyberCertPrinterRefImplementation()
            );
            vm.stopPrank();
            console2.log("CyberCertPrinter beacon implementation was accepted by IssuanceManager: %s", imAddr);
        }
    }

    function _upgradeLegacyIssuanceManagers() internal {
        IssuanceManagerWithMigration imWithMigrationImpl = new IssuanceManagerWithMigration();

        assertEq(
            cyberCorpFactory.issuanceManagerFactory(),
            imWithMigrationImpl.NEW_UPGRADE_FACTORY(),
            "new issuanceManagerFactory address has changed, update it in IssuanceManagerWithMigration"
        );

        legacyIssuanceManagerFactory.upgradeImplementation(address(imWithMigrationImpl));
        assertEq(
            legacyIssuanceManagerFactory.getBeaconImplementation(),
            address(imWithMigrationImpl),
            "beacon implementation should be upgraded with migration features by now"
        );

        for (uint256 i = 0; i < knownCyberCorps.length; i++) {
            address imAddr = CyberCorp(knownCyberCorps[i]).issuanceManager();
            IssuanceManagerWithMigration(imAddr).migrateUpgradeFactory();
            assertNotEq(
                IssuanceManagerFactory(IssuanceManager(imAddr).getUpgradeFactory()).getRefImplementation(),
                address(0),
                "should be able to lookup reference implementation now"
            );
            assertEq(
                IssuanceManager(imAddr).getCertPrinterBeaconImplementation(),
                newImFactory.getCyberCertPrinterRefImplementation(),
                "should point CyberCertPrinter implementation to reference now"
            );
            assertEq(
                IssuanceManager(imAddr).getScripBeaconImplementation(),
                newImFactory.getCyberScripRefImplementation(),
                "should point CyberScrip implementation to reference now"
            );
        }

        address refImplementation = newImFactory.getRefImplementation();
        legacyIssuanceManagerFactory.upgradeImplementation(refImplementation);
        assertEq(
            legacyIssuanceManagerFactory.getBeaconImplementation(),
            refImplementation,
            "beacon implementation should be upgraded without migration features by now"
        );
    }

    function _assertIssuanceManagerBeacons(address imAddr) internal {
        assertEq(
            IIssuanceManager(imAddr).getCertPrinterBeaconImplementation(),
            newImFactory.getCyberCertPrinterRefImplementation(),
            string(abi.encodePacked("unexpected CertPrinterBeaconImplementation for IssuanceManager: ", vm.toString(imAddr)))
        );
        assertEq(
            IIssuanceManager(imAddr).getScripBeaconImplementation(),
            newImFactory.getCyberScripRefImplementation(),
            string(abi.encodePacked("unexpected ScripBeaconImplementation for IssuanceManager: ", vm.toString(imAddr)))
        );
    }
}

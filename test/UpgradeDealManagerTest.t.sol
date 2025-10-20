// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {UpgradeDealManagerDependenciesScript} from "../script/upgrade-dealmanager-dependencies.s.sol";
import {UpgradeDealManagerFactoryScript} from "../script/upgrade-dealmanager-factory.s.sol";
import {UpgradeLegacyDealManagersScript} from "../script/upgrade-legacy-dealmanagers.s.sol";
import {ILegacyDealManagerFactory} from "../script/interfaces/ILegacyDealManagerFactory.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {KnownDealManagersLoader} from "../script/libs/KnownDealManagersLoader.sol";
import {SecurityClass, SecuritySeries, CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerWithMigration} from "../src/DealManagerWithMigration.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract UpgradeDealManagerTest is Test {
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Universal registry address
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    CyberCorpFactory cyberCorpFactory = CyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
    ILegacyDealManagerFactory legacyDealManagerFactory = ILegacyDealManagerFactory(0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3);

    address paymentToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC @ Ethereum mainnet

    // Known deployed DealManager @ Ethereum mainnet
    address[] knownDealManagers;

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
    address deployer = vm.addr(deployerPrivateKey);
    uint256 alicePrivateKey = 0xa11ce;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 0xb0b;
    address bob = vm.addr(bobPrivateKey);

    DealManagerFactory newDmFactory;
    DealManagerWithMigration dmWithMigrationImpl;
    GnosisTransaction safeTx;

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

        // Load all known deal managers
        knownDealManagers = KnownDealManagersLoader.load(block.chainid);

        // Simulate granting the test deployer admin access so it can perform upgrades
        vm.startPrank(metalexSafe);
        registry.AUTH().updateRole(deployer, registry.AUTH().OWNER_ROLE());
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
            defaultLegend: new string[](0)
        });
    }

    function test_SanityCheck() public {
        _upgradeFactoryAndLegacyDealManagers();

        // Script might've done it, but we'll do it again just in case
        assertEq(legacyDealManagerFactory.getBeaconImplementation(), address(dmWithMigrationImpl), "beacon implementation should be upgraded by now");
        assertEq(cyberCorpFactory.dealManagerFactory(), address(newDmFactory), "CyberCorpFactory's DealManagerFactory should be updated by now");
    }

    function test_LegacyDealManagerIntegrity() public {
        // Snapshot slot contents before upgrade
        BorgAuth[] memory expectedAuths = new BorgAuth[](knownDealManagers.length);
        for (uint256 i = 0; i < knownDealManagers.length; i++) {
            expectedAuths[i] = DealManager(knownDealManagers[i]).AUTH();
        }

        // Perform upgrades
        _upgradeFactoryAndLegacyDealManagers();

        // Verify integrity
        for (uint256 i = 0; i < knownDealManagers.length; i++) {
            // New DealManager should implement new methods
            assertEq(DealManager(knownDealManagers[i]).DEPLOY_VERSION(), "1", string(abi.encodePacked("unexpected DEPLOY_VERSION() for DealManager: ", vm.toString(knownDealManagers[i]))));
            assertEq(DealManager(knownDealManagers[i]).computeFee(1 ether), 0 ether, "upgraded DealManager should support fee calculation with no fees");
            assertEq(DealManager(knownDealManagers[i]).getPlatformPayable(), address(0), "upgraded DealManager should support fee payable");

            // Check for slot conflicts
            assertEq(address(DealManager(knownDealManagers[i]).AUTH()), address(expectedAuths[i]), string(abi.encodePacked("AUTH should not change for DealManager: ", vm.toString(knownDealManagers[i]))));
        }
    }

    function test_LegacyDealManagerProposeDeal() public {
        _upgradeFactoryAndLegacyDealManagers();

        // Test the first three known deal managers is enough
        uint256 testLength = knownDealManagers.length > 3 ? 3 : knownDealManagers.length;
        for (uint256 i = 0; i < testLength; i++) {

            address cyberCorp = DealManager(knownDealManagers[i]).issuanceManager().CORP();
            vm.startPrank(cyberCorp);

            address[] memory certPrinterAddress = new address[](1);
            for (uint256 j = 0; j < defaultCertData.length; j++) {
                certPrinterAddress[j] = IIssuanceManager(DealManager(knownDealManagers[i]).issuanceManager()).createCertPrinter(
                    defaultCertData[j].defaultLegend,
                    string.concat("TestCorp", defaultCertData[j].name),
                    defaultCertData[j].symbol,
                    defaultCertData[j].uri,
                    defaultCertData[j].securityClass,
                    defaultCertData[j].securitySeries,
                    defaultCertData[j].extension
                );
            }

            uint256 agreementSalt = block.timestamp + i;

            // Create and sign deal
            DealManager(knownDealManagers[i]).proposeAndSignDeal(
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
        }
    }

    function test_NewDealManagerIntegrity() public {
        _upgradeFactoryAndLegacyDealManagers();

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

    function test_DeployNewCyberCorp() public {
        _upgradeFactoryAndLegacyDealManagers();

        vm.startPrank(alice);
        cyberCorpFactory.deployCyberCorpAndCreateOffer(
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
    }

    // TODO WIP: this is failing atm probably due to incompatible version of CyberCorpFactory, IssuanceManagerFactory, etc.
    //  Need a precise plan on how we are upgrading everything
//    function test_enableFees() public {
//        _upgradeFactoryAndLegacyDealManagers();
//
//        vm.startPrank(metalexSafe);
//        newDmFactory.setPlatformPayable(address(metalexSafe));
//        newDmFactory.setDefaultFeeRatio(25);
//        vm.stopPrank();
//
//        vm.startPrank(alice);
//        (
//            address cyberCorp,
//            address auth,
//            address issuanceManager,
//            address dm,
//            address[] memory cyberCertPrinterAddr,
//            bytes32 agreementId,
//            uint256[] memory certIds
//        ) = cyberCorpFactory.deployCyberCorpAndCreateOffer(
//            block.timestamp,
//            "TestCorp",
//            "Limited Liability Company",
//            "Juris",
//            "Contact Details",
//            "Dispute Res",
//            alice,
//            CompanyOfficer({
//                eoa: alice,
//                name: "Alice",
//                contact: "test@example.com",
//                title: "CEO"
//            }),
//            defaultCertData,
//            templateId,
//            defaultGlobalValues,
//            defaultParties,
//            100e6,
//            defaultPartyValues,
//            CyberAgreementUtils.signAgreementTypedData(
//                vm,
//                registry.DOMAIN_SEPARATOR(),
//                registry.SIGNATUREDATA_TYPEHASH(),
//                keccak256(abi.encode(
//                    templateId,
//                    block.timestamp,
//                    defaultGlobalValues,
//                    defaultParties
//                )),
//                contractUri,
//                globalFields,
//                partyFields,
//                defaultGlobalValues,
//                defaultPartyValues[0],
//                alicePrivateKey
//            ),
//            defaultCertDetails,
//            new address[](0),
//            bytes32(0),
//            block.timestamp + 1000000
//        );
//        vm.stopPrank();
//
//        deal(address(paymentToken), bob, 100e6);
//        uint256 metalexSafeBalanceBefore = ERC20(paymentToken).balanceOf(metalexSafe);
//
//        vm.startPrank(bob);
//        ERC20(paymentToken).approve(dm, 100e6);
//        DealManager(dm).signAndFinalizeDeal(
//            bob,
//            agreementId,
//            defaultPartyValues[1],
//            CyberAgreementUtils.signAgreementTypedData(
//                vm,
//                registry.DOMAIN_SEPARATOR(),
//                registry.SIGNATUREDATA_TYPEHASH(),
//                agreementId,
//                contractUri,
//                globalFields,
//                partyFields,
//                defaultGlobalValues,
//                defaultPartyValues[1],
//                bobPrivateKey
//            ),
//            true,
//            "Bob",
//            ""
//        );
//        vm.stopPrank();
//
//        assertEq(ERC20(paymentToken).balanceOf(alice), 100e6 - 0.25e6, "alice should receive payment minus fees");
//        assertEq(ERC20(paymentToken).balanceOf(metalexSafe) - metalexSafeBalanceBefore, 0.25e6, "MetaLex should receive fees");
//    }

    function _upgradeFactoryAndLegacyDealManagers() internal {
        //
        // Simulate upgrades
        //

        // Upgrade all other breaking changes
        (new UpgradeDealManagerDependenciesScript()).run();

        // Run scripts to deploy DealManagerFactory
        (newDmFactory, safeTx) = (new UpgradeDealManagerFactoryScript()).run();
        // Expect new factory to be deployed at a predetermined address because we will hard-code it to the DealManagerWithMigration contract
        assertEq(address(newDmFactory), 0x919c7aD9aFAF40C29EE41aA41431ACf7558e35b7, "new DealManagerFactory address has changed, update it in DealManagerWithMigration");

        // Simulate MetaLeX Safe executing the Safe txs to replace DealManagerFactory
        vm.startPrank(metalexSafe);
        (safeTx.to).call{value: safeTx.value}(safeTx.data);
        vm.stopPrank();

        // Run scripts to upgrade all legacy DealManagers
        // TODO should take a list of known DealManagers
        dmWithMigrationImpl = (new UpgradeLegacyDealManagersScript()).run();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {UpgradeDealManagerFactoryScript} from "../script/upgrade-dealmanager-factory.s.sol";
import {UpgradeLegacyDealManagersScript} from "../script/upgrade-legacy-dealmanagers.s.sol";
import {ILegacyDealManagerFactory} from "../script/interfaces/ILegacyDealManagerFactory.sol";
import {GnosisTransaction} from "../script/libs/safe.sol";
import {SecurityClass, SecuritySeries, CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerWithMigration} from "../src/DealManagerWithMigration.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {BorgAuth} from "../src/libs/auth.sol";

/// @notice Because we are testing against the legacy CyberCorpFactory, not the one we are upgrading to
interface ILegacyCyberCorpFactory {
    struct CyberCertData {
        string name;
        string symbol;
        string uri;
        SecurityClass securityClass;
        SecuritySeries securitySeries;
        address extension;
        string[] defaultLegend;
    }
    
    function dealManagerFactory() external returns (address);

    function deployCyberCorpAndCreateOffer(
        uint256 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer,
        CyberCertData[] memory _certData,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[][] memory _partyValues,
        bytes memory signature,
        CertificateDetails[] memory _details,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    )
    external
    returns (
        address cyberCorpAddress,
        address authAddress,
        address issuanceManagerAddress,
        address dealManagerAddress,
        address[] memory certPrinterAddress,
        bytes32 id,
        uint256[] memory certIds
    );
}

contract UpgradeDealManagerTest is Test {
    address metalexSafe = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;

    // Universal registry address
    CyberAgreementRegistry registry = CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134);
    ILegacyCyberCorpFactory cyberCorpFactory = ILegacyCyberCorpFactory(0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2);
    ILegacyDealManagerFactory legacyDealManagerFactory = ILegacyDealManagerFactory(0x975df8A99C895d04ae158F8C91Ba562Fce3ECDA3);

    address paymentToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC @ Ethereum mainnet

    // Known deployed DealManager @ Ethereum mainnet
    address[] knownDealManagers = new address[](3);

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
    ILegacyCyberCorpFactory.CyberCertData[] defaultCertData = new ILegacyCyberCorpFactory.CyberCertData[](1);
    CertificateDetails[] defaultCertDetails = new CertificateDetails[](1);

    function setUp() public {
        //
        // Prepare for upgrades
        //

        knownDealManagers[0] = 0xB4dd83e4b12454a85AEc05e443e95c72a2c48D83;
        knownDealManagers[1] = 0x71B4DAC6237Ce73bf673CB9cb2b94257C975D69a;
        knownDealManagers[2] = 0x492685f1d34170F1B67e8B72cBD0f982E3E7e7a7;

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
        
        defaultCertData[0] = ILegacyCyberCorpFactory.CyberCertData({
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

        address knownCyberCorp = 0x55c2Bb9973793d6Aa3dbb18C81fB5e115892F8af;
        vm.startPrank(knownCyberCorp);

        address[] memory certPrinterAddress = new address[](1);
        for (uint256 i = 0; i < defaultCertData.length; i++) {
            certPrinterAddress[i] = IIssuanceManager(DealManager(knownDealManagers[0]).issuanceManager()).createCertPrinter(
                defaultCertData[i].defaultLegend,
                string.concat("TestCorp", defaultCertData[i].name),
                defaultCertData[i].symbol,
                defaultCertData[i].uri,
                defaultCertData[i].securityClass,
                defaultCertData[i].securitySeries,
                defaultCertData[i].extension
            );
        }

        // Create and sign deal
        DealManager(knownDealManagers[0]).proposeAndSignDeal(
            certPrinterAddress,
            paymentToken,
            100e6,
            templateId,
            block.timestamp,
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
            defaultPartyValues,
            new address[](0),
            bytes32(0),
            block.timestamp + 1000000
        );

        vm.stopPrank();
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

    // TODO WIP
    function test_enableFees() public {
        _upgradeFactoryAndLegacyDealManagers();

        vm.startPrank(metalexSafe);
        newDmFactory.setPlatformPayable(address(metalexSafe));
        newDmFactory.setDefaultFeeRatio(10);
        vm.stopPrank();
    }

    function _upgradeFactoryAndLegacyDealManagers() internal {
        //
        // Simulate upgrades
        //

        // Run scripts to deploy DealManagerFactory
        (newDmFactory, safeTx) = (new UpgradeDealManagerFactoryScript()).run();
        // Expect new factory to be deployed at a predetermined address because we will hard-code it to the DealManagerWithMigration contract
        assertEq(address(newDmFactory), 0x2E6EB43Fe6BC12543aB59239028401Ae1f9125E3, "new DealManagerFactory address has changed, update it in DealManagerWithMigration");

        // Simulate MetaLeX Safe executing the Safe txs to replace DealManagerFactory
        vm.startPrank(metalexSafe);
        (safeTx.to).call{value: safeTx.value}(safeTx.data);
        vm.stopPrank();

        // Run scripts to upgrade all legacy DealManagers
        // TODO should take a list of known DealManagers
        dmWithMigrationImpl = (new UpgradeLegacyDealManagersScript()).upgradeLegacyDealManagers(address(newDmFactory));
    }
}

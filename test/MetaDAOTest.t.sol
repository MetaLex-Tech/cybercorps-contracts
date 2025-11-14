// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DeployMetaDAOFactoryScript} from "../script/deploy-metadao-factory.s.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {DealManagerFactory, DealManager} from "../src/DealManagerFactory.sol";
import {RoundManagerFactory, RoundManager} from "../src/RoundManagerFactory.sol";
import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {ICyberAgreementRegistry} from "../src/interfaces/ICyberAgreementRegistry.sol";
import "../src/storage/CyberCertPrinterStorage.sol"; // CertificateDetails
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";

contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1_000_000 * 10 ** 6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MetaDAOTest is Test {
    address private metalex = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    address private coreAuth = 0x033012a1eDA6e2E00D12CD37c5b63B9440ef5E01;

    uint256 private deployerPrivKey;
    address private deployer;
    uint256 private metaDAOPrivKey;
    address private metaDAO;
    uint256 private founderPrivKey;
    address private founder;
    uint256 private alicePrivKey;
    address private alice;

    CyberAgreementRegistry public registry;
    MetaDAOFactory public factory;

    string public segCoTemplateTitle = "MetaDAO Futarchy Governance SPC - SegCo combined v 1.0";
    bytes32 public segCoTemplateId = keccak256(bytes(segCoTemplateTitle));
    string public segCoTemplateUri = "ipfs://bafybeifpvfwxfmobk7nhflsczqiynp3ca5urvyk3duh7s3rwptcnfzhuje";

    string public boardConsentTemplateTitle = "MetaDAO Futarchy Governance SPC - Board Consent - Approval of SegCo v 1.0";
    bytes32 public boardConsentTemplateId = keccak256(bytes(boardConsentTemplateTitle));
    string public boardConsentTemplateUri = "ipfs://bafkreic7dscoigvwjc23vzvkmzophm34kpafu6nrctykq5bif63lqvpuoa";

    string[] public globalFields;
    string[] public partyFields;

    function setUp() public {
        // Keys
        (deployer, deployerPrivKey) = makeAddrAndKey("deployer");
        (metaDAO, metaDAOPrivKey) = makeAddrAndKey("metaDAO");
        (founder, founderPrivKey) = makeAddrAndKey("founder");
        (alice, alicePrivKey) = makeAddrAndKey("alice");

        // Simulate granting deployer admin permission
        vm.startPrank(metalex);
        BorgAuth(coreAuth).updateRole(deployer, BorgAuth(coreAuth).OWNER_ROLE());
        vm.stopPrank();

        // Deploy MetaDAO factories with production scripts
        (registry, factory) = (new DeployMetaDAOFactoryScript()).run(
            deployerPrivKey, // deployerPrivateKey
            metaDAO, // multisig
            hex"63f62ac9b08c813401a02a16a820a106e525ac65dff992dccfd2cb42e5423db6725bb1b4d6e0244a635665f4965514512253613e3b032491f7ec85c2f657154e1b" // metadaoEscrowSig
        );

        // Simulate disabling deployer admin permission after deployment
        vm.startPrank(metalex);
        BorgAuth(coreAuth).updateRole(deployer, 0);
        vm.stopPrank();

        globalFields = new string[](8);
        globalFields[0] = "founderName";
        globalFields[1] = "enterpriseName";
        globalFields[2] = "companyName";
        globalFields[3] = "companyType";
        globalFields[4] = "companyJurisdiction";
        globalFields[5] = "companyContactDetails";
        globalFields[6] = "tokenSymbol";
        globalFields[7] = "tokenName";
        partyFields = new string[](2);
        partyFields[0] = "name";
        partyFields[1] = "contactDetails";
    }

    function test_metadata() public {
        // Verify template for SegCo combined agreement
        {
            (
                string memory legalContractUri,
                string memory title,
                string[] memory _globalFields,
                string[] memory _partyFields
            ) = registry.getTemplateDetails(segCoTemplateId);
            assertEq(legalContractUri, segCoTemplateUri);
            assertEq(title, segCoTemplateTitle);
            assertEq(_globalFields, globalFields);
            assertEq(_partyFields, partyFields);
        }

        // Verify template for Board Consent
        {
            (
                string memory legalContractUri,
                string memory title,
                string[] memory _globalFields,
                string[] memory _partyFields
            ) = registry.getTemplateDetails(boardConsentTemplateId);
            assertEq(legalContractUri, boardConsentTemplateUri);
            assertEq(title, boardConsentTemplateTitle);
            assertEq(_globalFields, globalFields);
            assertEq(_partyFields, partyFields);
        }
    }

    function test_deployMetaDAOContractFor() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 100; // 1 has been used by the deploy scripts;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(segCoTemplateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            segCoTemplateUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            founderPrivKey
        );

        vm.startPrank(founder);
        factory.deployMetaDAOContractFor(
            saltUint,
            "testcorp S.P., a segregated portfolio of Futarchy Governance SPC",
            "Segregated Portfolio of Segregated Portfolio Company",
            "Cayman Islands",
            "email@testcorp.com",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues[1],
            signature,
            founder
        );
        vm.stopPrank();

        address[] memory meetingNotesParties = new address[](1);
        meetingNotesParties[0] = metaDAO;
        _verifyContractsDefault(
            contractId,
            keccak256(abi.encode(boardConsentTemplateId, saltUint, globalValues, meetingNotesParties))
        );
    }

    function test_deployMetaDAOContractForOnBehalf() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 100; // 1 has been used by the deploy scripts;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(segCoTemplateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            segCoTemplateUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            founderPrivKey
        );

        // deploy on behalf of founder should also work as long as the signature is correct
        vm.startPrank(alice);
        factory.deployMetaDAOContractFor(
            saltUint,
            "testcorp S.P., a segregated portfolio of Futarchy Governance SPC",
            "Segregated Portfolio of Segregated Portfolio Company",
            "Cayman Islands",
            "email@testcorp.com",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues[1],
            signature,
            founder
        );
        vm.stopPrank();

        address[] memory meetingNotesParties = new address[](1);
        meetingNotesParties[0] = metaDAO;
        _verifyContractsDefault(
            contractId,
            keccak256(abi.encode(boardConsentTemplateId, saltUint, globalValues, meetingNotesParties))
        );
    }

    function test_RevertIf_deployMetaDAOContractForWrongSignature() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 100; // 1 has been used by the deploy scripts;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(segCoTemplateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            segCoTemplateUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            alicePrivKey // wrong signature
        );

        // alice should not be able to deploy with her own signature on behalf of founder
        vm.startPrank(alice);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        factory.deployMetaDAOContractFor(
            saltUint,
            "testcorp S.P., a segregated portfolio of Futarchy Governance SPC",
            "Segregated Portfolio of Segregated Portfolio Company",
            "Cayman Islands",
            "email@testcorp.com",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues[1],
            signature,
            founder
        );
        vm.stopPrank();
    }

    function test_RevertIf_deployMetaDAOContractForMismatchGlobalValues() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 100; // 1 has been used by the deploy scripts;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, corpOfficer.eoa]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(segCoTemplateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            segCoTemplateUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            founderPrivKey
        );

        // alice should not be able temper with the field values
        vm.startPrank(alice);
        vm.expectRevert(MetaDAOFactory.GlobalOrPartyValuesMismatch.selector);
        factory.deployMetaDAOContractFor(
            saltUint,
            "Alice's Company", // intentionally wrong company name
            "Segregated Portfolio of Segregated Portfolio Company",
            "Cayman Islands",
            "email@testcorp.com",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues[1],
            signature,
            founder
        );
        vm.stopPrank();
    }

    function test_RevertIf_deployMetaDAOContractForMismatchOfficerValues() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 100; // 1 has been used by the deploy scripts;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(segCoTemplateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            segCoTemplateUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            founderPrivKey
        );

        CompanyOfficer memory officer = _getDefaultCorpOfficer();
        // Overwrite with incorrect officer EOA
        officer.eoa = alice;

        // alice should not be able temper with the officer values
        vm.startPrank(alice);
        vm.expectRevert(MetaDAOFactory.OfficerValuesMismatch.selector);
        factory.deployMetaDAOContractFor(
            saltUint,
            "testcorp S.P., a segregated portfolio of Futarchy Governance SPC",
            "Segregated Portfolio of Segregated Portfolio Company",
            "Cayman Islands",
            "email@testcorp.com",
            "arbitration",
            founder,
            officer,
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues[1],
            signature,
            founder
        );
        vm.stopPrank();
    }

    function _getDefaultGlobalValues() internal returns (string[] memory) {
        string[] memory globalValues = new string[](8);
        globalValues[0] = "Founder"; // founderName
        globalValues[1] = "testcorp"; // enterpriseNAme
        globalValues[2] = "testcorp S.P., a segregated portfolio of Futarchy Governance SPC"; // companyName
        globalValues[3] = "Segregated Portfolio of Segregated Portfolio Company"; // companyType
        globalValues[4] = "Cayman Islands"; // companyJurisdiction
        globalValues[5] = "email@testcorp.com"; // companyContactDetails
        globalValues[6] = "TESTCORP"; // tokenSymbol
        globalValues[7] = "Test Corp"; // tokenName
        return globalValues;
    }

    function _getDefaultPartyValues() internal returns (string[][] memory) {
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "MetaDAO Officer"; // name
        partyValues[0][1] = "metadao@example.com"; // contactDetails
        partyValues[1] = new string[](2);
        partyValues[1][0] = "Founder"; // name
        partyValues[1][1] = "founder@example.com"; // contactDetails
        return partyValues;
    }

    function _getDefaultCorpOfficer() internal returns (CompanyOfficer memory) {
        return CompanyOfficer({
            eoa: founder,
            name: "Founder",
            contact: "founder@example.com",
            title: "CEO"
        });
    }

    /// @notice This is to make sure contracts fields are created and signed with the expected values because
    /// they are not strong typed and are error-prone to typos or out of sync across many iterations
    /// @dev The test assumes all default values
    function _verifyContractsDefault(bytes32 agreementId, bytes32 meetingNotesId) internal {
        string[] memory expectedGlobalFields = new string[](8);
        expectedGlobalFields[0] = "founderName";
        expectedGlobalFields[1] = "enterpriseName";
        expectedGlobalFields[2] = "companyName";
        expectedGlobalFields[3] = "companyType";
        expectedGlobalFields[4] = "companyJurisdiction";
        expectedGlobalFields[5] = "companyContactDetails";
        expectedGlobalFields[6] = "tokenSymbol";
        expectedGlobalFields[7] = "tokenName";

        string[] memory expectedGlobalValues = new string[](8);
        expectedGlobalValues[0] = "Founder"; // founderName
        expectedGlobalValues[1] = "testcorp"; // enterpriseNAme
        expectedGlobalValues[2] = "testcorp S.P., a segregated portfolio of Futarchy Governance SPC"; // companyName
        expectedGlobalValues[3] = "Segregated Portfolio of Segregated Portfolio Company"; // companyType
        expectedGlobalValues[4] = "Cayman Islands"; // companyJurisdiction
        expectedGlobalValues[5] = "email@testcorp.com"; // companyContactDetails
        expectedGlobalValues[6] = "TESTCORP"; // tokenSymbol
        expectedGlobalValues[7] = "Test Corp"; // tokenName

        string[] memory expectedPartyFields = new string[](2);
        expectedPartyFields[0] = "name";
        expectedPartyFields[1] = "contactDetails";

        {
            address[] memory expectedParties = new address[](2);
            expectedParties[0] = metaDAO;
            expectedParties[1] = founder;

            string[][] memory expectedPartyValues = new string[][](2);
            expectedPartyValues[0] = new string[](2);
            expectedPartyValues[0][0] = "MetaDAO Officer"; // name
            expectedPartyValues[0][1] = "metadao@example.com"; // contactDetails
            expectedPartyValues[1] = new string[](2);
            expectedPartyValues[1][0] = "Founder"; // name
            expectedPartyValues[1][1] = "founder@example.com"; // contactDetails

            _verifyContractDetails(
                "SegCo agreement",
                agreementId,
                segCoTemplateUri,
                expectedGlobalFields,
                expectedPartyFields,
                expectedGlobalValues,
                expectedParties,
                expectedPartyValues,
                2
            );
        }

        {
            address[] memory expectedParties = new address[](1);
            expectedParties[0] = metaDAO;

            string[][] memory expectedPartyValues = new string[][](1);
            expectedPartyValues[0] = new string[](2);
            expectedPartyValues[0][0] = "MetaDAO Officer"; // name
            expectedPartyValues[0][1] = "metadao@example.com"; // contactDetails

            _verifyContractDetails(
                "Board consent",
                meetingNotesId,
                boardConsentTemplateUri,
                expectedGlobalFields,
                expectedPartyFields,
                expectedGlobalValues,
                expectedParties,
                expectedPartyValues,
                1
            );
        }
    }

    /// @dev Made a separate function to avoid stack-too-deep errors
    function _verifyContractDetails(
        string memory contractName,
        bytes32 agreementId,
        string memory expectedLegalContractUri,
        string[] memory expectedGlobalFields,
        string[] memory expectedPartyFields,
        string[] memory expectedGlobalValues,
        address[] memory expectedParties,
        string[][] memory expectedPartyValues,
        uint256 expectedNumSignatures
    ) internal {
        (
            ,
            string memory legalContractUri,
            string[] memory globalFields,
            string[] memory partyFields,
            string[] memory globalValues,
            address[] memory parties,
            string[][] memory partyValues,
            ,
            uint256 numSignatures,
            bool isComplete
        ) = CyberAgreementRegistry(registry).getContractDetails(agreementId);

        assertEq(legalContractUri, expectedLegalContractUri, string(abi.encodePacked(contractName, ": unexpected legal contract URI")));
        assertEq(globalFields, expectedGlobalFields, string(abi.encodePacked(contractName, ": unexpected globalFields")));
        assertEq(partyFields, expectedPartyFields, string(abi.encodePacked(contractName, ": unexpected partyFields")));
        assertEq(globalValues, expectedGlobalValues, string(abi.encodePacked(contractName, ": unexpected globalValues")));
        for (uint256 i = 0; i < partyValues.length; i++) {
            assertEq(partyValues[i], expectedPartyValues[i], string(abi.encodePacked(contractName, ": unexpected partyValues")));
        }
        assertEq(parties, expectedParties, string(abi.encodePacked(contractName, ": unexpected parties")));
        assertEq(numSignatures, expectedNumSignatures, string(abi.encodePacked(contractName, ": unexpected number of signatures")));
        assertTrue(isComplete, string(abi.encodePacked(contractName, ": agreement should be complete")));
    }
}

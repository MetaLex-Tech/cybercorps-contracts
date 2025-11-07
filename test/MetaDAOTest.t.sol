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

    bytes32 public segCoTemplateId = bytes32(uint256(40));
    bytes32 public boardConsentTemplateId = bytes32(uint256(41));
    string[] public globalFields;
    string[] public partyFields;

    function setUp() public {
        // Keys
        (deployer, deployerPrivKey) = makeAddrAndKey("deployer");
        (metaDAO, metaDAOPrivKey) = makeAddrAndKey("metaDAO");
        (founder, founderPrivKey) = makeAddrAndKey("founder");
        (alice, alicePrivKey) = makeAddrAndKey("alice");

        // Deploy MetaDAO factories with production scripts
        (registry, factory) = (new DeployMetaDAOFactoryScript()).run(
            deployerPrivKey,
            metaDAO
        );

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

    function test_deployMetaDAOContractFor() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
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
            "ipfs://template",
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            founderPrivKey
        );

        vm.startPrank(founder);
        factory.deployMetaDAOContractFor(
            saltUint,
            "Corp Meta",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues,
            signature,
            founder
        );
        vm.stopPrank();

        address[] memory meetingNotesParties = new address[](1);
        meetingNotesParties[0] = metaDAO;
        _verifyContractStatus(
            contractId,
            keccak256(abi.encode(boardConsentTemplateId, saltUint, globalValues, meetingNotesParties))
        );
    }

    function test_deployMetaDAOContractForOnBehalf() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
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
            "ipfs://template",
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
            "Corp Meta",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues,
            signature,
            founder
        );
        vm.stopPrank();

        address[] memory meetingNotesParties = new address[](1);
        meetingNotesParties[0] = metaDAO;
        _verifyContractStatus(
            contractId,
            keccak256(abi.encode(boardConsentTemplateId, saltUint, globalValues, meetingNotesParties))
        );
    }

    function test_RevertIf_deployMetaDAOContractForWrongSignature() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
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
            "ipfs://template",
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
            "Corp Meta",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues,
            signature,
            founder
        );
        vm.stopPrank();
    }

    function test_RevertIf_deployMetaDAOContractForMismatchPartyValues() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        // Overwrite with incorrect founder name
        partyValues[1][0] = "Alice";

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
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
            "ipfs://template",
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            founderPrivKey
        );

        // alice should not be able temper with the party values
        vm.startPrank(alice);
        vm.expectRevert(MetaDAOFactory.PartyValuesMismatch.selector);
        factory.deployMetaDAOContractFor(
            saltUint,
            "Corp Meta",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            founder,
            _getDefaultCorpOfficer(),
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues,
            signature,
            founder
        );
        vm.stopPrank();
    }

    function test_RevertIf_deployMetaDAOContractForMismatchOfficerValues() public {
        // Parties and values
        string[] memory globalValues = _getDefaultGlobalValues();
        string[][] memory partyValues = _getDefaultPartyValues();

        CompanyOfficer memory officer = _getDefaultCorpOfficer();
        // Overwrite with incorrect officer EOA
        officer.eoa = alice;

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
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
            "ipfs://template",
            globalFields,
            partyFields,
            globalValues,
            partyValues[1],
            founderPrivKey
        );

        // alice should not be able temper with the officer values
        vm.startPrank(alice);
        vm.expectRevert(MetaDAOFactory.OfficerValuesMismatch.selector);
        factory.deployMetaDAOContractFor(
            saltUint,
            "Corp Meta",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            founder,
            officer,
            segCoTemplateId,
            boardConsentTemplateId,
            globalValues,
            partyValues,
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

    function _verifyContractStatus(bytes32 agreementId, bytes32 meetingNotesId) internal {
        // Verify agreement status
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool isAgreementComplete
        ) = CyberAgreementRegistry(registry).getContractDetails(agreementId);
        assertTrue(isAgreementComplete, "agreement should be complete");

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool isMeetingNotesComplete
        ) = CyberAgreementRegistry(registry).getContractDetails(meetingNotesId);
        assertTrue(isMeetingNotesComplete, "meeting notes should be complete");
    }
}

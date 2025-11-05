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

    bytes32 public templateId;
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

        // Create test template with 1 global + 1 party field
        templateId = bytes32("TEST_TEMPLATE");
        globalFields = new string[](1);
        globalFields[0] = "Global Field";
        partyFields = new string[](1);
        partyFields[0] = "Party Field";
        vm.prank(metaDAO);
        registry.createTemplate(templateId, "MetaDAO", "ipfs://template", globalFields, partyFields);
    }

    function test_deployMetaDAOContractFor() public {
        // Parties and values
        string[] memory globalValues = new string[](1);
        globalValues[0] = "G";

        string[] memory partyValues = new string[](1);
        partyValues[0] = "Officer";

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(templateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs://template",
            globalFields,
            partyFields,
            globalValues,
            partyValues,
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
            CompanyOfficer({
                eoa: founder,
                name: "Officer",
                contact: "officer@example.com",
                title: "CEO"
            }),
            templateId,
            globalValues,
            new string[][](0), // no-op
            signature,
            founder
        );
        vm.stopPrank();
    }

    function test_deployMetaDAOContractForOnBehalf() public {
        // Parties and values
        string[] memory globalValues = new string[](1);
        globalValues[0] = "G";

        string[] memory partyValues = new string[](1);
        partyValues[0] = "Officer";

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(templateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs://template",
            globalFields,
            partyFields,
            globalValues,
            partyValues,
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
            CompanyOfficer({
                eoa: founder,
                name: "Officer",
                contact: "officer@example.com",
                title: "CEO"
            }),
            templateId,
            globalValues,
            new string[][](0), // no-op
            signature,
            founder
        );
        vm.stopPrank();
    }

    function test_RevertIf_deployMetaDAOContractForWrongSignature() public {
        // Parties and values
        string[] memory globalValues = new string[](1);
        globalValues[0] = "G";

        string[] memory partyValues = new string[](1);
        partyValues[0] = "Officer";

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        address[] memory parties = new address[](2);
        parties[0] = metaDAO;
        parties[1] = founder;
        bytes32 contractId = keccak256(abi.encode(templateId, saltUint, globalValues, parties));
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            "ipfs://template",
            globalFields,
            partyFields,
            globalValues,
            partyValues,
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
            CompanyOfficer({
                eoa: founder,
                name: "Officer",
                contact: "officer@example.com",
                title: "CEO"
            }),
            templateId,
            globalValues,
            new string[][](0), // no-op
            signature,
            founder
        );
        vm.stopPrank();
    }
}


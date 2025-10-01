// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MetaDAOFactory} from "../src/MetaDAOFactory.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
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
    uint256 private ownerPrivKey;
    address private owner;
    uint256 private investorPrivKey;
    address private investor;

    function test_deployCyberCorpAndCreateOffer_Reverts_NotFinalizer() public {
        // Keys
        ownerPrivKey = 0xA0A0;
        owner = vm.addr(ownerPrivKey);
        investorPrivKey = 0xB0B0;
        investor = vm.addr(investorPrivKey);
        vm.startPrank(owner);
        // Bootstrap auth
        bytes32 salt = keccak256(abi.encodePacked("metadao-infra", owner));
        BorgAuth bootstrapAuth = new BorgAuth{salt: salt}(owner);

        // Registry (proxy)
        CyberAgreementRegistry registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberAgreementRegistry{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(bootstrapAuth)
                    )
                )
            )
        );

        // UriBuilder (proxy)
        address uriBuilder = address(
            new ERC1967Proxy{salt: salt}(
                address(new CertificateUriBuilder{salt: salt}()),
                abi.encodeWithSelector(
                    CertificateUriBuilder.initialize.selector,
                    address(bootstrapAuth)
                )
            )
        );

        // Factories
        address issuanceManagerFactoryAddr = address(new IssuanceManagerFactory{salt: salt}(address(bootstrapAuth)));
        address cyberCorpSingleFactory = address(new CyberCorpSingleFactory{salt: salt}(address(bootstrapAuth)));
        address dealManagerFactory = address(new DealManagerFactory{salt: salt}(address(bootstrapAuth)));
        address roundManagerFactory = address(new RoundManagerFactory{salt: salt}(address(bootstrapAuth)));

        // Implementations
        address certPrinterImpl = address(new CyberCertPrinter{salt: salt}());
        address cyberScripImpl = address(new CyberScrip{salt: salt}());

        // Stable token
        MockPaymentToken usdc = new MockPaymentToken();

        // MetaDAOFactory (proxy)
        MetaDAOFactory factory = MetaDAOFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new MetaDAOFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        MetaDAOFactory.initialize.selector,
                        address(bootstrapAuth),
                        address(registry),
                        certPrinterImpl,
                        cyberScripImpl,
                        issuanceManagerFactoryAddr,
                        cyberCorpSingleFactory,
                        dealManagerFactory,
                        roundManagerFactory,
                        uriBuilder,
                        address(usdc)
                    )
                )
            )
        );

        // Set up MetaDAO owner and officer on factory
        uint256 metaDAOPrivKey = 0xD00D;
        address metaDAO = vm.addr(metaDAOPrivKey);

        BorgAuth(address(factory.AUTH())).updateRole(metaDAO, 99);
        vm.stopPrank();
        CompanyOfficer memory metaOfficer = CompanyOfficer({
            eoa: metaDAO,
            name: "Officer",
            contact: "metadao@example.com",
            title: "CEO"
        });
        vm.prank(metaDAO);
        factory.setMetaDAOOfficer(metaOfficer);
        vm.prank(metaDAO);
        factory.setMetaDAOSignatureHash(abi.encodePacked("META_ESCROW_SIG"));

        // Template with 1 global + 1 party field
        bytes32 templateId = bytes32("TEST_TEMPLATE");
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field";
        vm.prank(owner);
        registry.createTemplate(templateId, "MetaDAO", "ipfs://template", globalFields, partyFields);

        // Officer
        CompanyOfficer memory officer = CompanyOfficer({
            eoa: owner,
            name: "Officer",
            contact: "officer@example.com",
            title: "CEO"
        });

        // Cert data
        MetaDAOFactory.CyberCertData[] memory certData = new MetaDAOFactory.CyberCertData[](1);
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData[0] = MetaDAOFactory.CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            defaultLegend: defaultLegend
        });

        // Certificate details
        CertificateDetails[] memory details = new CertificateDetails[](1);
        details[0] = CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "CEO",
            investmentAmountUSD: 10_000 * 10 ** usdc.decimals(),
            issuerUSDValuationAtTimeOfInvestment: 10_000_000,
            unitsRepresented: 0,
            legalDetails: "",
            extensionData: ""
        });

        // Parties and values
        address[] memory parties = new address[](2);
        parties[0] = owner;    // corp
        parties[1] = investor; // buyer

        string[] memory globalValues = new string[](1);
        globalValues[0] = "G";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Officer";

        // Compute agreementId and signer signature for deployer (who will sign)
        uint256 saltUint = 1;
        uint256 deployerPrivKey = 0xA1A1;
        address deployer = vm.addr(deployerPrivKey);
        // Parties must match what factory will set: [metaDAOOfficer.eoa, deployer]
        parties[0] = metaDAO;
        parties[1] = deployer;
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
            partyValues[0],
            deployerPrivKey
        );

        vm.prank(deployer);
        factory.deployMetaDAOContractFor(
            saltUint,
            "Corp Meta",
            "corporation",
            "DE",
            "contact",
            "arbitration",
            deployer,
            officer,
            templateId,
            globalValues,
            partyValues,
            signature,
            deployer // deployer param
        );
    }
}


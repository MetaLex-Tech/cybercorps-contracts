// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {DealManagerStorage} from "../src/storage/DealManagerStorage.sol";
import {CertificateDetails, SecurityClass, SecuritySeries} from "../src/storage/LedgerEntryTokenStorage.sol";
import {CyberCertPrinterMock, ERC20Mock, IssuanceManagerMock} from "./DealManagerTest.t.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PurchaseUriCorpMock {
    address public companyPayable = address(0xCAFE);
    string public cyberCORPName = "Test Corp";
}

contract PurchaseUriIssuanceMock is IssuanceManagerMock {
    string public lastCertificateUri;

    function createCertPrinter(
        string[] memory,
        string memory,
        string memory,
        string memory uri,
        SecurityClass,
        SecuritySeries,
        address,
        bytes memory
    ) external returns (address) {
        lastCertificateUri = uri;
        return address(new CyberCertPrinterMock());
    }
}

contract PurchaseAgreementUriTest is Test {
    CyberAgreementRegistry registry;
    DealManager dm;
    PurchaseUriIssuanceMock issuance;
    PurchaseUriCorpMock corp;
    ERC20Mock payment;
    BorgAuth auth;
    address issuer;
    uint256 issuerKey;
    address investor;
    uint256 investorKey;
    bytes32 constant TEMPLATE = keccak256("SAFE schema");
    string constant TEMPLATE_URI = "ipfs://original-template";
    string constant PDF_URI = "ipfs://purchase-agreement-pdf";
    string[] fields;
    string[] values;
    address[] parties;
    string[][] partyValues;
    address[] printers;
    CertificateDetails[] certDetails;

    function setUp() public {
        (issuer, issuerKey) = makeAddrAndKey("issuer");
        (investor, investorKey) = makeAddrAndKey("investor");
        auth = new BorgAuth(issuer);
        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeCall(CyberAgreementRegistry.initialize, (address(auth)))
                )
            )
        );
        fields = new string[](1);
        fields[0] = "Name";
        values = new string[](1);
        values[0] = "Test Corp";
        parties = new address[](2);
        parties[0] = issuer;
        parties[1] = investor;
        partyValues = new string[][](2);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Issuer";
        partyValues[1] = new string[](1);
        partyValues[1][0] = "Investor";
        registry.createTemplate(TEMPLATE, "SAFE", TEMPLATE_URI, fields, fields);
        corp = new PurchaseUriCorpMock();
        issuance = new PurchaseUriIssuanceMock();
        payment = new ERC20Mock("Payment", "PAY");
        DealManager implementation = new DealManager();
        DealManagerFactory factory = DealManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new DealManagerFactory()),
                    abi.encodeCall(DealManagerFactory.initialize, (address(auth), address(implementation)))
                )
            )
        );
        dm = DealManager(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(
                        DealManager.initialize,
                        (address(auth), address(corp), address(registry), address(issuance), address(factory))
                    )
                )
            )
        );
        printers = new address[](1);
        printers[0] = address(new CyberCertPrinterMock());
        certDetails = new CertificateDetails[](1);
        payment.mint(investor, 100 ether);
        vm.prank(investor);
        payment.approve(address(dm), type(uint256).max);
    }

    function _id(string memory uri, bytes32 secret, address finalizer) internal view returns (bytes32) {
        return keccak256(abi.encode(TEMPLATE, uint256(1), values, parties, secret, finalizer, uri));
    }

    function _signature(bytes32 id, string memory uri, bool buyer) internal view returns (bytes memory) {
        return CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            id,
            uri,
            fields,
            fields,
            values,
            partyValues[buyer ? 1 : 0],
            buyer ? investorKey : issuerKey
        );
    }

    function _propose(string memory uri, bytes memory signature) internal returns (bytes32 id, uint256[] memory ids) {
        vm.prank(issuer);
        return dm.proposeAndSignDealWithAgreementUri(
            printers,
            address(payment),
            10 ether,
            TEMPLATE,
            1,
            values,
            parties,
            certDetails,
            issuer,
            signature,
            partyValues,
            new address[](0),
            bytes32(0),
            0,
            uri
        );
    }

    function _assertDocument(bytes32 id, string memory uri) internal view {
        assertEq(registry.getAgreementUri(id), uri);
        (bytes32 templateId, string memory document,,,,,,,,) = registry.getContractDetails(id);
        assertEq(templateId, TEMPLATE);
        assertEq(document, uri);
        assertEq(vm.parseJsonString(registry.getContractJson(id), ".legalContractUri"), uri);
        (string memory original,,,) = registry.getTemplateDetails(TEMPLATE);
        assertEq(original, TEMPLATE_URI);
    }

    function test_PurchaseUriSignsPaysAndFinalizesWithoutPublishingTemplate() public {
        bytes32 expected = _id(PDF_URI, bytes32(0), address(dm));
        vm.recordLogs();
        (bytes32 id, uint256[] memory ids) = _propose(PDF_URI, _signature(expected, PDF_URI, false));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], keccak256("TemplateCreated(bytes32,string,string,string[],string[])"));
        }
        assertEq(id, expected);
        _assertDocument(id, PDF_URI);
        assertTrue(registry.hasSigned(id, issuer));
        assertFalse(registry.isFinalized(id));
        assertEq(CyberCertPrinterMock(printers[0]).ownerOf(ids[0]), address(dm));
        bytes memory signature = _signature(id, PDF_URI, true);
        vm.prank(investor);
        dm.signAndFinalizeDeal(investor, id, partyValues[1], signature, false, "Investor", "");
        assertTrue(registry.isFinalized(id));
        assertEq(payment.balanceOf(corp.companyPayable()), 10 ether);
        assertEq(CyberCertPrinterMock(printers[0]).ownerOf(ids[0]), investor);
        _assertDocument(id, PDF_URI);
    }

    function test_WrongDocumentSignatureRollsBackAgreementAndMint() public {
        bytes32 expected = _id(PDF_URI, bytes32(0), address(dm));
        bytes memory signature = _signature(expected, TEMPLATE_URI, false);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        _propose(PDF_URI, signature);
        assertEq(CyberCertPrinterMock(printers[0]).totalSupply(), 0);
        vm.expectRevert(CyberAgreementRegistry.ContractDoesNotExist.selector);
        registry.getAgreementUri(expected);
    }

    function test_InvestorMustSignInstanceUri() public {
        bytes32 expected = _id(PDF_URI, bytes32(0), address(dm));
        (bytes32 id,) = _propose(PDF_URI, _signature(expected, PDF_URI, false));
        bytes memory signature = _signature(id, TEMPLATE_URI, true);
        vm.prank(investor);
        vm.expectRevert(CyberAgreementRegistry.SignatureVerificationFailed.selector);
        dm.signAndFinalizeDeal(investor, id, partyValues[1], signature, false, "Investor", "");
        assertEq(payment.balanceOf(investor), 100 ether);
        assertFalse(registry.hasSigned(id, investor));
    }

    function test_LegacyProposalKeepsIdAndTemplateUri() public {
        bytes32 expected = keccak256(abi.encode(TEMPLATE, uint256(1), values, parties, bytes32(0), address(dm)));
        bytes memory signature = _signature(expected, TEMPLATE_URI, false);
        vm.prank(issuer);
        (bytes32 id,) = dm.proposeAndSignDeal(
            printers,
            address(payment),
            10 ether,
            TEMPLATE,
            1,
            values,
            parties,
            certDetails,
            issuer,
            signature,
            partyValues,
            new address[](0),
            bytes32(0),
            0
        );
        assertEq(id, expected);
        _assertDocument(id, TEMPLATE_URI);
        assertTrue(registry.hasSigned(id, issuer));
    }

    function test_UriSecretAndFinalizerAreBoundIntoId() public {
        bytes32 first = registry.createContractWithAgreementUri(
            TEMPLATE, 1, values, parties, partyValues, bytes32(0), address(dm), 0, PDF_URI
        );
        bytes32 second = registry.createContractWithAgreementUri(
            TEMPLATE, 1, values, parties, partyValues, bytes32(0), address(dm), 0, "ipfs://different-pdf"
        );
        bytes32 third = registry.createContractWithAgreementUri(
            TEMPLATE, 1, values, parties, partyValues, keccak256("secret"), address(dm), 0, PDF_URI
        );
        bytes32 fourth = registry.createContractWithAgreementUri(
            TEMPLATE, 1, values, parties, partyValues, bytes32(0), investor, 0, PDF_URI
        );
        assertEq(first, _id(PDF_URI, bytes32(0), address(dm)));
        assertNotEq(first, second);
        assertNotEq(first, third);
        assertNotEq(first, fourth);
        vm.expectRevert(CyberAgreementRegistry.ContractAlreadyExists.selector);
        registry.createContractWithAgreementUri(
            TEMPLATE, 1, values, parties, partyValues, bytes32(0), address(dm), 0, PDF_URI
        );
        _assertDocument(first, PDF_URI);
    }

    function test_RejectEmptyUriAndKeepSchemaValidation() public {
        vm.expectRevert(CyberAgreementRegistry.LegalContractUriEmpty.selector);
        registry.createContractWithAgreementUri(
            TEMPLATE, 1, values, parties, partyValues, bytes32(0), address(dm), 0, ""
        );
        vm.expectRevert(CyberAgreementRegistry.TemplateDoesNotExist.selector);
        registry.createContractWithAgreementUri(
            bytes32(0), 1, values, parties, partyValues, bytes32(0), address(dm), 0, PDF_URI
        );
        vm.expectRevert(CyberAgreementRegistry.MismatchedFieldsLength.selector);
        registry.createContractWithAgreementUri(
            TEMPLATE, 1, new string[](0), parties, partyValues, bytes32(0), address(dm), 0, PDF_URI
        );
        vm.expectRevert(DealManager.LegalContractUriEmpty.selector);
        _propose("", "");
    }

    function test_UnsignedProposalUsesInstanceDocument() public {
        vm.prank(issuer);
        (bytes32 id,) = dm.proposeDealWithAgreementUri(
            printers,
            address(payment),
            10 ether,
            TEMPLATE,
            1,
            values,
            parties,
            certDetails,
            partyValues,
            new address[](0),
            bytes32(0),
            0,
            PDF_URI
        );
        _assertDocument(id, PDF_URI);
        assertFalse(registry.hasSigned(id, issuer));
    }

    function test_NewPrintersRetainCertificateUri() public {
        DealManagerStorage.CyberCertData[] memory certData = new DealManagerStorage.CyberCertData[](1);
        certData[0].uri = "ipfs://live-cybercert-document";
        bytes32 expected = _id(PDF_URI, bytes32(0), address(dm));
        bytes memory signature = _signature(expected, PDF_URI, false);
        vm.prank(issuer);
        (address[] memory created, bytes32 id, uint256[] memory ids) = dm.proposeAndSignNewCertsDealWithAgreementUri(
            1,
            certData,
            TEMPLATE,
            values,
            parties,
            10 ether,
            partyValues,
            signature,
            certDetails,
            new address[](0),
            bytes32(0),
            0,
            address(payment),
            PDF_URI
        );
        assertEq(id, expected);
        assertEq(issuance.lastCertificateUri(), certData[0].uri);
        assertEq(CyberCertPrinterMock(created[0]).ownerOf(ids[0]), address(dm));
        _assertDocument(id, PDF_URI);
    }

    function test_NewEntryPointsRemainOwnerOnly() public {
        vm.startPrank(investor);
        vm.expectRevert();
        dm.proposeDealWithAgreementUri(
            printers,
            address(payment),
            10 ether,
            TEMPLATE,
            1,
            values,
            parties,
            certDetails,
            partyValues,
            new address[](0),
            bytes32(0),
            0,
            PDF_URI
        );
        vm.expectRevert();
        dm.proposeAndSignDealWithAgreementUri(
            printers,
            address(payment),
            10 ether,
            TEMPLATE,
            1,
            values,
            parties,
            certDetails,
            issuer,
            "",
            partyValues,
            new address[](0),
            bytes32(0),
            0,
            PDF_URI
        );
        vm.expectRevert();
        dm.proposeAndSignNewCertsDealWithAgreementUri(
            1,
            new DealManagerStorage.CyberCertData[](0),
            TEMPLATE,
            values,
            parties,
            10 ether,
            partyValues,
            "",
            certDetails,
            new address[](0),
            bytes32(0),
            0,
            address(payment),
            PDF_URI
        );
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/IssuanceManager.sol";
import "../src/LedgerEntryToken.sol";
import "../src/CyberScrip.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import "../src/interfaces/IUriBuilder.sol";
import {RestrictiveLegend} from "../src/storage/CyberCertPrinterStorage.sol";
import {IssuanceManagerStorage} from "../src/storage/IssuanceManagerStorage.sol";
import "../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";

contract MockCyberCorpForIM {
    function cyberCORPName() external pure returns (string memory) { return "TestCorp"; }
    function cyberCORPType() external pure returns (string memory) { return "C-Corp"; }
    function cyberCORPJurisdiction() external pure returns (string memory) { return "DE"; }
    function cyberCORPContactDetails() external pure returns (string memory) { return "test@corp.test"; }
    function dealManager() external pure returns (address) { return address(0); }
    function roundManager() external pure returns (address) { return address(0); }
}

contract MockUriBuilderForIM is IUriBuilder {
    function buildCertificateUri(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) { return "uri://mock"; }

    function buildCertificateUri(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        RestrictiveLegend[] memory,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) { return "uri://mock"; }

    function buildCertificateUriNotEncoded(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        string[] memory,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) { return "uri://mock"; }

    function buildCertificateUriNotEncoded(
        string memory,
        string memory,
        string memory,
        string memory,
        SecurityClass,
        SecuritySeries,
        string memory,
        RestrictiveLegend[] memory,
        CertificateDetails memory,
        Endorsement[] memory,
        OwnerDetails memory,
        address,
        bytes32,
        uint256,
        address,
        address
    ) external pure returns (string memory) { return "uri://mock"; }
}

contract IssuanceManagerTest is Test {
    bytes32 constant SALT = bytes32(keccak256("IssuanceManagerTest"));

    IssuanceManager public issuanceManager;
    BorgAuth public auth;

    address public owner;
    address public investor;

    function setUp() public {
        owner = address(this);
        investor = makeAddr("investor");

        auth = new BorgAuth(owner);

        IssuanceManagerFactory imFactory = IssuanceManagerFactory(address(
            new ERC1967Proxy{salt: SALT}(
                address(new IssuanceManagerFactory{salt: SALT}()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(auth),
                    new IssuanceManager(),
                    new LedgerEntryToken(),
                    new CyberScrip()
                )
            )
        ));

        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(SALT));
        issuanceManager.initialize(
            address(auth),
            address(new MockCyberCorpForIM()),
            address(new MockUriBuilderForIM()),
            address(imFactory)
        );
    }

    function test_createCert_emitsCertificateCreated() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");
        CertificateDetails memory details = _buildCertificateDetails(100);

        vm.expectEmit(true, true, false, true);
        emit IssuanceManager.CertificateCreated(
            0,
            address(certPrinter),
            details.investmentAmountUSD,
            details.issuerUSDValuationAtTimeOfInvestment,
            details
        );
        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, details);
    }

    function test_createCertAndAssign_emitsCertificateCreated() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");
        CertificateDetails memory details = _buildCertificateDetails(100);

        vm.expectEmit(true, true, false, true);
        emit IssuanceManager.CertificateCreated(
            0,
            address(certPrinter),
            details.investmentAmountUSD,
            details.issuerUSDValuationAtTimeOfInvestment,
            details
        );
        vm.prank(owner);
        issuanceManager.createCertAndAssign(address(certPrinter), investor, details);
    }

    function test_createCertSignAndAssign_emitsCertificateCreated() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");
        CertificateDetails memory details = _buildCertificateDetails(100);

        vm.expectEmit(true, true, false, true);
        emit IssuanceManager.CertificateCreated(
            0,
            address(certPrinter),
            details.investmentAmountUSD,
            details.issuerUSDValuationAtTimeOfInvestment,
            details
        );
        vm.prank(owner);
        issuanceManager.createCertSignAndAssign(
            address(certPrinter),
            investor,
            details,
            bytes(""),
            address(0),
            bytes32(0),
            ""
        );
    }

    function test_isPrinter_TrueForCreatedPrinter() public {
        ICyberCertPrinter certPrinter = _deployPrinter("Cert", "CERT");
        assertTrue(issuanceManager.isPrinter(address(certPrinter)), "created printer should be tracked");
    }

    function test_isPrinter_FalseForUnknownAddress() public {
        _deployPrinter("Cert", "CERT");
        assertFalse(issuanceManager.isPrinter(address(0xBEEF)), "foreign address is not a printer");
        assertFalse(issuanceManager.isPrinter(address(0)), "zero address is not a printer");
    }

    function test_isPrinter_TracksMultiplePrinters() public {
        ICyberCertPrinter a = _deployPrinter("CertA", "CERTA");
        ICyberCertPrinter b = _deployPrinter("CertB", "CERTB");
        assertTrue(issuanceManager.isPrinter(address(a)), "first printer tracked");
        assertTrue(issuanceManager.isPrinter(address(b)), "second printer tracked");
    }

    function test_createCertPrinter_CreatesAndPairsCanonicalClass() public {
        ICyberCertPrinter first = _deployPrinter("CertA", "CERTA");
        uint256 classId = issuanceManager.getPrinterClassId(address(first));

        assertEq(classId, 1, "first security type creates the first class");
        SecurityClassInfo memory classInfo = issuanceManager.getSecurityClass(classId);
        assertEq(
            uint256(classInfo.classType),
            uint256(SecurityClass.CommonStock),
            "class type matches printer type"
        );
        assertEq(bytes(classInfo.documentURI).length, 0, "class URI starts empty");
        assertEq(classInfo.dataExtension, address(0), "class extension starts empty");
        assertEq(classInfo.classData.length, 0, "class data starts empty");

        ICyberCertPrinter second = _deployPrinter("CertB", "CERTB");
        assertEq(
            issuanceManager.getPrinterClassId(address(second)),
            classId,
            "printers of the same security type share its canonical class"
        );
        assertEq(issuanceManager.getSecurityClassCount(), 1, "class is created once");
    }

    function test_defineSecurityClass_RevertsForExistingSecurityType() public {
        _deployPrinter("Cert", "CERT");

        vm.expectRevert(IssuanceManagerStorage.SecurityClassAlreadyDefined.selector);
        issuanceManager.defineSecurityClass(
            SecurityClass.CommonStock,
            "uri://class",
            address(0),
            bytes("")
        );
    }

    function test_updateSecurityClass_ReindexesOnTypeChange() public {
        _deployPrinter("Cert", "CERT");

        issuanceManager.updateSecurityClass(
            1,
            SecurityClass.PreferredStock,
            "uri://class",
            address(0),
            bytes("")
        );

        assertEq(
            uint256(issuanceManager.getSecurityClass(1).classType),
            uint256(SecurityClass.PreferredStock),
            "class type is updated"
        );

        // The reverse index must follow the type, or a printer of the new type creates a duplicate class.
        ICyberCertPrinter preferred = _deployPrinterOfType(
            "CertP",
            "CERTP",
            SecurityClass.PreferredStock
        );
        assertEq(
            issuanceManager.getPrinterClassId(address(preferred)),
            1,
            "printer of the new type reuses the re-indexed class"
        );
        assertEq(issuanceManager.getSecurityClassCount(), 1, "no duplicate class is created");

        // The vacated type is released and can be defined again.
        uint256 commonId = issuanceManager.defineSecurityClass(
            SecurityClass.CommonStock,
            "uri://common",
            address(0),
            bytes("")
        );
        assertEq(commonId, 2, "vacated type is definable again");
    }

    function test_updateSecurityClass_RevertsWhenTargetTypeAlreadyDefined() public {
        _deployPrinter("Cert", "CERT");
        issuanceManager.defineSecurityClass(
            SecurityClass.PreferredStock,
            "uri://preferred",
            address(0),
            bytes("")
        );

        vm.expectRevert(IssuanceManagerStorage.SecurityClassAlreadyDefined.selector);
        issuanceManager.updateSecurityClass(
            1,
            SecurityClass.PreferredStock,
            "uri://class",
            address(0),
            bytes("")
        );
    }

    function test_updateSecurityClass_KeepsIndexWhenTypeUnchanged() public {
        _deployPrinter("Cert", "CERT");

        issuanceManager.updateSecurityClass(
            1,
            SecurityClass.CommonStock,
            "uri://class",
            address(0),
            bytes("")
        );

        assertEq(
            bytes(issuanceManager.getSecurityClass(1).documentURI).length,
            bytes("uri://class").length,
            "non-type fields still update"
        );
        vm.expectRevert(IssuanceManagerStorage.SecurityClassAlreadyDefined.selector);
        issuanceManager.defineSecurityClass(
            SecurityClass.CommonStock,
            "uri://class",
            address(0),
            bytes("")
        );
    }

    function _deployPrinter(
        string memory name,
        string memory symbol
    ) internal returns (ICyberCertPrinter) {
        return _deployPrinterOfType(name, symbol, SecurityClass.CommonStock);
    }

    function _deployPrinterOfType(
        string memory name,
        string memory symbol,
        SecurityClass securityClass
    ) internal returns (ICyberCertPrinter) {
        return ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                name,
                symbol,
                "uri://cert",
                securityClass,
                SecuritySeries.SeriesA,
                address(0),
                bytes("")
            )
        );
    }

    function _buildCertificateDetails(uint256 units) internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units * 1e18,
            legalDetails: "",
            extensionData: bytes("")
        });
    }
}

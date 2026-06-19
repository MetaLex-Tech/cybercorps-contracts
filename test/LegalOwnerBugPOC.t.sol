// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/IssuanceManager.sol";
import "../src/IssuanceManagerFactory.sol";
import "../src/CyberCertPrinter.sol";
import "../src/CyberScrip.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import "../src/interfaces/ITransferRestrictionHook.sol";
import "../src/interfaces/ICondition.sol";
import "../src/interfaces/IUriBuilder.sol";
import "../src/libs/auth.sol";
import {RestrictiveLegend} from "../src/storage/CyberCertPrinterStorage.sol";

contract LegalOwnerMockCyberCorp {
    function cyberCORPName() external pure returns (string memory) {
        return "MockCorp";
    }

    function cyberCORPType() external pure returns (string memory) {
        return "C-Corp";
    }

    function cyberCORPJurisdiction() external pure returns (string memory) {
        return "DE";
    }

    function cyberCORPContactDetails() external pure returns (string memory) {
        return "mock@corp.test";
    }

    function dealManager() external pure returns (address) {
        return address(0xD34D);
    }

    function roundManager() external pure returns (address) {
        return address(0xB0B0);
    }
}

contract LegalOwnerMockUriBuilder is IUriBuilder {
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
    ) external pure returns (string memory) {
        return "uri://mock";
    }

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
    ) external pure returns (string memory) {
        return "uri://mock";
    }

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
    ) external pure returns (string memory) {
        return "uri://mock";
    }

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
    ) external pure returns (string memory) {
        return "uri://mock";
    }
}

contract LegalOwnerBugPOCTest is Test {
    bytes32 internal constant SALT = bytes32(keccak256("LegalOwnerBugPOC"));

    IssuanceManager internal issuanceManager;
    ICyberCertPrinter internal certPrinter;
    BorgAuth internal auth;

    address internal owner;
    address internal investor;

    function setUp() public {
        owner = address(this);
        investor = makeAddr("investor");

        auth = new BorgAuth(owner);

        IssuanceManagerFactory factory = IssuanceManagerFactory(
            address(
                new ERC1967Proxy(
                    address(new IssuanceManagerFactory()),
                    abi.encodeWithSelector(
                        IssuanceManagerFactory.initialize.selector,
                        address(auth),
                        new IssuanceManager(),
                        new CyberCertPrinter(),
                        new CyberScrip()
                    )
                )
            )
        );

        issuanceManager = IssuanceManager(factory.deployIssuanceManager(SALT));
        issuanceManager.initialize(
            address(auth),
            address(new LegalOwnerMockCyberCorp()),
            address(new LegalOwnerMockUriBuilder()),
            address(factory)
        );

        certPrinter = ICyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                "Legal Owner Cert",
                "LOC",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );
    }

    function test_POC_CreateCert_MintsNftButLeavesLegalOwnerUnset() public {
        uint256 certId = issuanceManager.createCert(
            address(certPrinter),
            investor,
            _details(10)
        );

        assertEq(certPrinter.ownerOf(certId), investor, "ERC721 owner should be investor");
        assertEq(
            certPrinter.legalOwnerOf(certId),
            address(0),
            "legal owner mapping is never initialized on mint"
        );
    }

    function test_POC_ScripifyRevertsBecauseLegalOwnerIsZeroAddress() public {
        uint256 certId = issuanceManager.createCert(
            address(certPrinter),
            investor,
            _details(10)
        );

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1,
            1,
            new uint256[](0),
            false,
            true,
            true,
            true
        );

        assertEq(certPrinter.ownerOf(certId), investor, "ERC721 owner should be investor");
        assertEq(certPrinter.legalOwnerOf(certId), address(0), "legal owner should still be unset");

        vm.prank(investor);
        vm.expectRevert(IssuanceManager.ConditionCheckFailed.selector);
        issuanceManager.scripifyCert(address(certPrinter), certId, 1, address(0));
    }

    function test_POC_CreateCertAndAssign_AlsoLeavesLegalOwnerUnset() public {
        uint256 certId = issuanceManager.createCertAndAssign(
            address(certPrinter),
            investor,
            _details(5)
        );

        assertEq(certPrinter.ownerOf(certId), investor, "ERC721 owner should be investor");
        assertEq(
            certPrinter.legalOwnerOf(certId),
            address(0),
            "recert mint path also leaves legal owner unset"
        );
    }

    function _details(uint256 units) internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: ""
        });
    }
}

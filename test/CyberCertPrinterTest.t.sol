// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/IssuanceManager.sol";
import "../src/IssuanceManagerFactory.sol";
import "../src/CyberCertPrinter.sol";
import "../src/CyberScrip.sol";
import "../src/interfaces/ICyberCertPrinter.sol";
import "../src/interfaces/IUriBuilder.sol";
import "../src/libs/auth.sol";

contract CertMockCyberCorp {
    function cyberCORPName() external pure returns (string memory) { return "MockCorp"; }
    function cyberCORPType() external pure returns (string memory) { return "C-Corp"; }
    function cyberCORPJurisdiction() external pure returns (string memory) { return "DE"; }
    function cyberCORPContactDetails() external pure returns (string memory) { return "mock@corp.test"; }
    function dealManager() external pure returns (address) { return address(0xD34D); }
    function roundManager() external pure returns (address) { return address(0xB0B0); }
}

contract CertMockUriBuilder is IUriBuilder {
    function buildCertificateUri(string memory, string memory, string memory, string memory, SecurityClass, SecuritySeries, string memory, string[] memory, CertificateDetails memory, Endorsement[] memory, OwnerDetails memory, address, bytes32, uint256, address, address) external pure returns (string memory) { return "uri://mock"; }
    function buildCertificateUriNotEncoded(string memory, string memory, string memory, string memory, SecurityClass, SecuritySeries, string memory, string[] memory, CertificateDetails memory, Endorsement[] memory, OwnerDetails memory, address, bytes32, uint256, address, address) external pure returns (string memory) { return "uri://mock"; }
}

contract CyberCertPrinterTest is Test {
    bytes32 internal constant SALT = bytes32(keccak256("CyberCertPrinterTest"));

    event MaxLegalHolderCountUpdated(uint256 maxLegalHolderCount);

    CyberCertPrinter internal cert;
    address internal im;

    address internal investor1;
    address internal investor2;
    address internal investor3;

    function setUp() public {
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        investor3 = makeAddr("investor3");

        BorgAuth auth = new BorgAuth(address(this));

        IssuanceManagerFactory factory = IssuanceManagerFactory(
            address(new ERC1967Proxy(
                address(new IssuanceManagerFactory()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(auth),
                    new IssuanceManager(),
                    new CyberCertPrinter(),
                    new CyberScrip()
                )
            ))
        );

        IssuanceManager issuanceManager = IssuanceManager(factory.deployIssuanceManager(SALT));
        issuanceManager.initialize(
            address(auth),
            address(new CertMockCyberCorp()),
            address(new CertMockUriBuilder()),
            address(factory)
        );

        im = address(issuanceManager);

        cert = CyberCertPrinter(
            issuanceManager.createCertPrinter(
                new string[](0),
                "Test Cert",
                "TC",
                "uri://cert",
                SecurityClass.CommonStock,
                SecuritySeries.SeriesA,
                address(0)
            )
        );

        // Enable global transfers so transferFrom works
        vm.prank(im);
        cert.setGlobalTransferable(true);
    }

    function _details() internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: 10,
            legalDetails: "",
            extensionData: ""
        });
    }

    function _mint(uint256 tokenId, address to) internal {
        vm.prank(im);
        cert.safeMint(tokenId, to, _details());
    }

    function _mintAndAssign(uint256 tokenId, address to) internal {
        vm.prank(im);
        cert.safeMintAndAssign(to, tokenId, _details(), "Investor Name");
    }

    // endorseAndTransfer: investor (current legal+ERC721 owner) endorses `to` then transfers.
    // endorsementRequired=true by default, so this is the required flow for transfer tests.
    function _endorseAndTransfer(uint256 tokenId, address from, address to) internal {
        Endorsement memory e = Endorsement({
            endorser: from,
            timestamp: block.timestamp,
            signatureHash: "",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: to,
            endorseeName: ""
        });
        vm.prank(from);
        cert.endorseAndTransfer(tokenId, e, from, to);
    }

    // -------------------------------------------------------------------------
    // Getters and setter
    // -------------------------------------------------------------------------

    function test_LegalHolderCount_InitiallyZero() public view {
        assertEq(cert.legalHolderCount(), 0);
        assertEq(cert.maxLegalHolderCount(), 0);
    }

    function test_SetMaxLegalHolderCount_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit MaxLegalHolderCountUpdated(5);
        vm.prank(im);
        cert.setMaxLegalHolderCount(5);
        assertEq(cert.maxLegalHolderCount(), 5);
    }

    function test_RemainingSlots_UnlimitedWhenZero() public view {
        assertEq(cert.remainingLegalHolderSlots(), type(uint256).max);
    }

    function test_RemainingSlots_CorrectDelta() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(3);
        _mint(1, investor1);
        assertEq(cert.remainingLegalHolderSlots(), 2);
        _mint(2, investor2);
        assertEq(cert.remainingLegalHolderSlots(), 1);
    }

    function test_RemainingSlots_ZeroAtCap() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(1);
        _mint(1, investor1);
        assertEq(cert.remainingLegalHolderSlots(), 0);
    }

    // -------------------------------------------------------------------------
    // safeMint increments
    // -------------------------------------------------------------------------

    function test_SafeMint_IncrementCount() public {
        _mint(1, investor1);
        assertEq(cert.legalHolderCount(), 1);
    }

    function test_SafeMint_TwoCertsToSameAddress_CountStaysOne() public {
        _mint(1, investor1);
        _mint(2, investor1);
        assertEq(cert.legalHolderCount(), 1);
    }

    function test_SafeMintAndAssign_IncrementCount() public {
        _mintAndAssign(1, investor1);
        assertEq(cert.legalHolderCount(), 1);
    }

    function test_SafeMint_TwoDifferentAddresses_CountIsTwo() public {
        _mint(1, investor1);
        _mint(2, investor2);
        assertEq(cert.legalHolderCount(), 2);
    }

    // -------------------------------------------------------------------------
    // burn decrements
    // -------------------------------------------------------------------------

    function test_Burn_DecrementsCount() public {
        _mint(1, investor1);
        assertEq(cert.legalHolderCount(), 1);
        vm.prank(im);
        cert.burn(1);
        assertEq(cert.legalHolderCount(), 0);
    }

    function test_Burn_OneCertOfTwoForSameHolder_CountUnchanged() public {
        _mint(1, investor1);
        _mint(2, investor1);
        assertEq(cert.legalHolderCount(), 1);
        vm.prank(im);
        cert.burn(1);
        assertEq(cert.legalHolderCount(), 1);
    }

    function test_Burn_LastCertOfHolder_OtherHolderUnaffected() public {
        _mint(1, investor1);
        _mint(2, investor2);
        assertEq(cert.legalHolderCount(), 2);
        vm.prank(im);
        cert.burn(1);
        assertEq(cert.legalHolderCount(), 1);
    }

    // -------------------------------------------------------------------------
    // transfer (endorsementRequired=true → must use endorseAndTransfer)
    // -------------------------------------------------------------------------

    function test_Transfer_ToNewHolder_SenderLeavesReceiverJoins_NetCountUnchanged() public {
        _mint(1, investor1);
        assertEq(cert.legalHolderCount(), 1);
        _endorseAndTransfer(1, investor1, investor2);
        // investor1 had only cert 1 → leaves; investor2 gains cert 1 → joins; net = 1
        assertEq(cert.legalHolderCount(), 1);
    }

    function test_Transfer_SenderRetainsOtherCert_CountIncreases() public {
        _mint(1, investor1);
        _mint(2, investor1);
        assertEq(cert.legalHolderCount(), 1);
        _endorseAndTransfer(1, investor1, investor2);
        // investor1 still holds cert 2 → stays; investor2 gains cert 1 → joins; net = 2
        assertEq(cert.legalHolderCount(), 2);
    }

    function test_Transfer_ToExistingHolder_SenderLeaves_CountDecreases() public {
        _mint(1, investor1);
        _mint(2, investor2);
        assertEq(cert.legalHolderCount(), 2);
        _endorseAndTransfer(1, investor1, investor2);
        // investor1 had only cert 1 → leaves; investor2 already held cert 2 → no new holder; net = 1
        assertEq(cert.legalHolderCount(), 1);
    }

    // -------------------------------------------------------------------------
    // assignCert updates counts
    // -------------------------------------------------------------------------

    function test_AssignCert_NewRecipient_SwitchesLegalHolder() public {
        _mint(1, investor1);
        assertEq(cert.legalHolderCount(), 1);
        vm.prank(im);
        cert.assignCert(investor1, 1, investor2, _details());
        // investor1's legal count drops to 0 → leaves; investor2 joins; net = 1
        assertEq(cert.legalHolderCount(), 1);
        assertEq(cert.legalOwnerOf(1), investor2);
    }

    function test_AssignCert_ExistingHolder_CountUnchanged() public {
        _mint(1, investor1);
        _mint(2, investor2);
        assertEq(cert.legalHolderCount(), 2);
        vm.prank(im);
        cert.assignCert(investor1, 1, investor2, _details());
        // investor1 leaves; investor2 already present; net = 1
        assertEq(cert.legalHolderCount(), 1);
    }

    // -------------------------------------------------------------------------
    // cap enforcement
    // -------------------------------------------------------------------------

    function test_MaxHolderCount_BlocksMintWhenAtCap() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(1);
        _mint(1, investor1);

        vm.prank(im);
        vm.expectRevert(abi.encodeWithSelector(CyberCertPrinter.HolderLimitExceeded.selector, uint256(1)));
        cert.safeMint(2, investor2, _details());
    }

    function test_MaxHolderCount_AllowsMintToExistingHolder() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(1);
        _mint(1, investor1);

        vm.prank(im);
        cert.safeMint(2, investor1, _details());
        assertEq(cert.legalHolderCount(), 1);
    }

    function test_MaxHolderCount_BlocksTransferToNewHolder() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(1);
        _mint(1, investor1);
        assertEq(cert.legalHolderCount(), 1);

        Endorsement memory e = Endorsement({
            endorser: investor1,
            timestamp: block.timestamp,
            signatureHash: "",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: investor2,
            endorseeName: ""
        });
        vm.prank(investor1);
        vm.expectRevert(abi.encodeWithSelector(CyberCertPrinter.HolderLimitExceeded.selector, uint256(1)));
        cert.endorseAndTransfer(1, e, investor1, investor2);
    }

    function test_MaxHolderCount_AllowsTransferToExistingHolder() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(2);
        _mint(1, investor1);
        _mint(2, investor2);

        _endorseAndTransfer(1, investor1, investor2);
        // investor1 leaves; investor2 gains cert 1 (already had cert 2); net = 1
        assertEq(cert.legalHolderCount(), 1);
    }

    function test_MaxHolderCount_UnlimitedAfterSetToZero() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(1);
        _mint(1, investor1);

        vm.prank(im);
        cert.setMaxLegalHolderCount(0);

        _mint(2, investor2);
        _mint(3, investor3);
        assertEq(cert.legalHolderCount(), 3);
    }

    function test_MaxHolderCount_BlocksAssignCertToNewHolder() public {
        vm.prank(im);
        cert.setMaxLegalHolderCount(1);
        _mint(1, investor1);

        vm.prank(im);
        vm.expectRevert(abi.encodeWithSelector(CyberCertPrinter.HolderLimitExceeded.selector, uint256(1)));
        cert.assignCert(investor1, 1, investor2, _details());
    }
}

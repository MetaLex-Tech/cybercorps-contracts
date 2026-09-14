// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IssuanceManager} from "../src/IssuanceManager.sol";

import {ICondition} from "../src/interfaces/ICondition.sol";
import {ICyberScrip} from "../src/interfaces/ICyberScrip.sol";
import {ILedgerEntryToken} from "../src/interfaces/ILedgerEntryToken.sol";

import {ITransferRestrictionHook} from "../src/interfaces/ITransferRestrictionHook.sol";
import {IssuanceManagerConversionTest} from "./IssuanceManagerConversionTest.t.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

contract RecertCallbackReceiver is IERC721Receiver {
    IssuanceManager immutable manager;
    ILedgerEntryToken immutable printer;
    bool immutable rejectMint;
    uint256 public callbacks;

    error MintRejected();

    constructor(IssuanceManager manager_, ILedgerEntryToken printer_, bool rejectMint_) {
        manager = manager_;
        printer = printer_;
        rejectMint = rejectMint_;
    }

    function convert() external {
        manager.convertScripToCert(address(printer), 100 ether);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(printer), "Unexpected printer");
        (bool approved,,,,) = manager.getRecertificationApproval(address(printer), address(this));
        require(!approved, "Approval still active during callback");
        require(printer.legalOwnerOf(tokenId) == address(this), "Legal owner not recorded");
        require(printer.balanceOfLegalOwner(address(this)) == 1, "Missing legal enumeration");
        require(printer.getActiveCertificateDetails(tokenId).unitsRepresented == 100 ether, "Missing details");
        if (rejectMint) revert MintRejected();
        callbacks++;
        if (callbacks == 1) manager.convertScripToCert(address(printer), 100 ether);
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract IssuanceManagerRecertCallbackTest is IssuanceManagerConversionTest {
    function _prepareReceiver(bool rejectMint)
        internal
        returns (ILedgerEntryToken printer, ICyberScrip scrip, RecertCallbackReceiver receiver)
    {
        printer = _deployPrinter("Callback Cert", "CALL");
        uint256 sourceId = _mintCert(printer, investor, 200);
        scrip = ICyberScrip(
            issuanceManager.deployCyberScrip(
                address(printer),
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
            )
        );
        receiver = new RecertCallbackReceiver(issuanceManager, printer, rejectMint);
        vm.prank(investor);
        issuanceManager.scripifyCert(address(printer), sourceId, 200 ether, address(receiver));
        _stageRecertificationApproval(printer, address(receiver), "Receiver", 100, "Approved metadata", hex"1234");
    }

    function test_RecertCallback_ReentryAddsToExistingCertificate() public {
        (ILedgerEntryToken printer, ICyberScrip scrip, RecertCallbackReceiver receiver) = _prepareReceiver(false);
        receiver.convert();
        assertEq(receiver.callbacks(), 1);
        assertEq(printer.totalSupply(), 2);
        assertEq(printer.balanceOfLegalOwner(address(receiver)), 1);
        assertEq(printer.getActiveCertificateDetails(1).unitsRepresented, 200 ether);
        assertEq(printer.getActiveCertificateDetails(1).legalDetails, "Approved metadata");
        assertEq(scrip.balanceOf(address(receiver)), 0);
        (bool approved,,,,) = issuanceManager.getRecertificationApproval(address(printer), address(receiver));
        assertFalse(approved);
    }

    function test_RecertCallback_RejectedMintRestoresApprovalAndScrip() public {
        (ILedgerEntryToken printer, ICyberScrip scrip, RecertCallbackReceiver receiver) = _prepareReceiver(true);
        vm.expectRevert(RecertCallbackReceiver.MintRejected.selector);
        receiver.convert();
        assertEq(printer.totalSupply(), 1);
        assertEq(printer.balanceOfLegalOwner(address(receiver)), 0);
        assertEq(scrip.balanceOf(address(receiver)), 200 ether);
        (bool approved,,,,) = issuanceManager.getRecertificationApproval(address(printer), address(receiver));
        assertTrue(approved);
    }
}

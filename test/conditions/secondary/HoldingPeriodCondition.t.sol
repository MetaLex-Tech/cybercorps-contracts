// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {CertificateDetails, ILedgerEntryToken} from "../../../src/interfaces/ILedgerEntryToken.sol";
import {LedgerEntryToken} from "../../../src/LedgerEntryToken.sol";
import {SecurityClass, SecuritySeries} from "../../../src/CyberCorpConstants.sol";
import {HoldingPeriodCondition} from "../../../src/libs/conditions/secondary/HoldingPeriodCondition.sol";
import {FundInterestData, FundInterestExtension} from "../../../src/storage/extensions/FundInterestExtension.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// HoldingPeriodCondition — Rule 144 holding-period verification.
//
// Legal/economic intent: a Rule 144 resale requires the seller's lot to have seasoned for the
// required hold (one year for non-reporting issuers). The anchor is the lot's base acquisition
// timestamp; where Rule 144(d)(3) tacking is asserted (non-zero tackedFrom), the EARLIER date
// governs. A missing anchor fails closed. A buy offer at posting has no seller yet, so it is verified later.
//
// Real integration: a real cert printer configured with a live FundInterestExtension holds the seller's
// lot; the base acquisition timestamp and the Rule 144(d)(3) tacking anchor are set via the printer's real
// admin overrides, and the seller's lot is offered through a real postOffer.
//
// Scenario × outcome (hold = 365 days)
// | # | scenario                                          | expect | rationale                          |
// |---|---------------------------------------------------|:------:|------------------------------------|
// | 1 | no acquisition record (anchor 0)                  |  fail  | fail closed                        |
// | 2 | acquired exactly 365 d ago                        |  pass  | hold satisfied (>=)                |
// | 3 | acquired 364 d ago                                |  fail  | one day short                      |
// | 4 | acquired 10 d ago, tacked from 400 d ago          |  pass  | tacking anchor governs (earlier)   |
// | 5 | acquired 10 d ago, tacked from 5 d ago            |  fail  | tacking ignored (not earlier)      |
// | 6 | acquired 10 d ago, no tacking asserted (0)        |  fail  | base anchor governs                |
// | 7 | BUY offer at posting                              |  pass  | seller/hold verified at acceptance |
//
// Config/authorization
// | # | case                          | expect                      |
// |---|-------------------------------|-----------------------------|
// | 8 | initialize zero holding       | revert InvalidHoldingPeriod |
// | 9 | updateHoldingPeriod zero      | revert InvalidHoldingPeriod |
// |10 | updateHoldingPeriod stranger  | revert (not admin)          |
// ─────────────────────────────────────────────────────────────────────────────

contract HoldingPeriodConditionTest is SecondaryConditionIntegrationBase {
    HoldingPeriodCondition internal hold;
    ILedgerEntryToken internal fundPrinter;
    uint256 internal fundTokenId;
    uint64 internal constant HOLD = 365 days;
    uint256 internal constant NOW = 500 days;

    function setUp() public {
        _setUpIntegration();
        vm.warp(NOW);
        hold = HoldingPeriodCondition(
            _proxy(
                address(new HoldingPeriodCondition()),
                abi.encodeCall(HoldingPeriodCondition.initialize, (address(auth), HOLD))
            )
        );
        // A real printer wired to a live FundInterestExtension, holding a seller lot whose base + tacking
        // anchors we drive through the printer's real admin overrides.
        FundInterestExtension extension = FundInterestExtension(
            _proxy(
                address(new FundInterestExtension()),
                abi.encodeCall(FundInterestExtension.initialize, (address(auth)))
            )
        );
        fundPrinter = ILedgerEntryToken(
            im.createCertPrinter(
                new string[](0), "Fund", "FUND", "ipfs://fund",
                SecurityClass.CommonStock, SecuritySeries.SeriesA, address(extension), bytes("")
            )
        );
        CertificateDetails memory d = _certDetails(UNITS);
        FundInterestData memory fid;
        d.extensionData = abi.encode(fid);
        fundTokenId = im.createCertAndAssign(address(fundPrinter), seller, d);
    }

    function _sellPosting(uint64 anchor, uint64 tackedFrom) internal returns (bool) {
        LedgerEntryToken(address(fundPrinter)).setAcquisitionTimestamp(fundTokenId, anchor);
        if (tackedFrom != 0) {
            LedgerEntryToken(address(fundPrinter)).updateCertificateTackedFromAcquisitionDate(fundTokenId, tackedFrom);
        }
        bytes32 offerId = _postSellOn(address(fundPrinter), fundTokenId);
        return hold.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0));
    }

    // 1
    function test_NoRecord_FailsClosed() public {
        LedgerEntryToken(address(fundPrinter)).setAcquisitionTimestamp(fundTokenId, 0);
        bytes32 offerId = _postSellOn(address(fundPrinter), fundTokenId);
        assertFalse(hold.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0)));
    }

    // 2
    function test_ExactlyHold_Passes() public {
        assertTrue(_sellPosting(uint64(NOW) - HOLD, 0));
    }

    // 3
    function test_OneDayShort_Fails() public {
        assertFalse(_sellPosting(uint64(NOW) - (HOLD - 1 days), 0));
    }

    // 4
    function test_TackingEarlier_Passes() public {
        assertTrue(_sellPosting(uint64(NOW) - 10 days, uint64(NOW) - 400 days));
    }

    // 5
    function test_TackingNotEarlier_Ignored_Fails() public {
        assertFalse(_sellPosting(uint64(NOW) - 10 days, uint64(NOW) - 5 days));
    }

    // 6
    function test_NoTacking_BaseAnchorGoverns_Fails() public {
        assertFalse(_sellPosting(uint64(NOW) - 10 days, 0));
    }

    // 7
    function test_BuyPosting_Passes() public {
        bytes32 offerId = _postBuy();
        assertTrue(hold.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0)));
    }

    // 8
    function test_Initialize_ZeroHolding_Reverts() public {
        HoldingPeriodCondition impl = new HoldingPeriodCondition();
        vm.expectRevert(HoldingPeriodCondition.InvalidHoldingPeriod.selector);
        _proxy(address(impl), abi.encodeCall(HoldingPeriodCondition.initialize, (address(auth), 0)));
    }

    // 9
    function test_UpdateHoldingPeriod_Zero_Reverts() public {
        vm.expectRevert(HoldingPeriodCondition.InvalidHoldingPeriod.selector);
        hold.updateHoldingPeriod(0);
    }

    // 10
    function test_UpdateHoldingPeriod_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        hold.updateHoldingPeriod(30 days);
    }
}

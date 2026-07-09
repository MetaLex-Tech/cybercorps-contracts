// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, OfferSide, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {HoldingPeriodCondition} from "../../../src/libs/conditions/secondary/HoldingPeriodCondition.sol";
import {FundInterestData} from "../../../src/storage/extensions/FundInterestExtension.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// HoldingPeriodCondition — Rule 144 holding-period verification.
//
// Legal/economic intent: a Rule 144 resale requires the seller's lot to have seasoned for the
// required hold (one year for non-reporting issuers). The anchor is the lot's base acquisition
// timestamp; where Rule 144(d)(3) tacking is asserted (non-zero tackedFrom), the EARLIER date
// governs. A missing anchor fails closed. A buy offer at posting has no seller yet, so it is verified later.
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

contract HoldingPeriodConditionTest is SecondaryConditionTestBase {
    HoldingPeriodCondition internal hold;
    uint64 internal constant HOLD = 365 days;
    uint256 internal constant NOW = 500 days;

    function setUp() public {
        _setUpBase();
        vm.warp(NOW);
        hold = HoldingPeriodCondition(
            _proxy(
                address(new HoldingPeriodCondition()),
                abi.encodeCall(HoldingPeriodCondition.initialize, (address(auth), HOLD))
            )
        );
    }

    function _sellPosting(uint64 anchor, uint64 tackedFrom) internal returns (bool) {
        cert.setAcquisitionTimestamp(1, anchor);
        cert.setExtensionData(
            1,
            abi.encode(
                FundInterestData({acquisitionDate: 0, tackedFromAcquisitionDate: tackedFrom, customProvisions: ""})
            )
        );
        dm.setOffer(OFFER_ID, _sellOffer());
        return hold.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, bytes32(0));
    }

    // 1
    function test_NoRecord_FailsClosed() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertFalse(hold.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, bytes32(0)));
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
        Offer memory o = _sellOffer();
        o.side = OfferSide.BUY;
        o.tokenId = 0;
        dm.setOffer(OFFER_ID, o);
        assertTrue(hold.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, bytes32(0)));
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

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CategoryKind} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {LexChexBadgeKindCondition} from "../../../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// LexChexBadgeKindCondition — parameterizable investor-status gate on the LeXcheXBadge layer.
//
// Legal/economic intent: one primitive deployed per investor-status parameterization —
// AccreditedInvestor (buyer only, §4(a)(7)), QIB (buyer only, Rule 144A), QualifiedPurchaser
// (buyer + seller, §3(c)(7)). An optional investorType filter narrows within the kind.
//
// Scenario × outcome
// | # | config                 | context      | buyer status | seller status | expect | rationale             |
// |---|------------------------|--------------|:------------:|:-------------:|:------:|-----------------------|
// | 1 | ACCREDITED, buyer-only | SELL posting |     n/a      |      no       |  pass  | seller ungated        |
// | 2 | ACCREDITED, buyer-only | accepted     |     yes      |      no       |  pass  | buyer accredited      |
// | 3 | ACCREDITED, buyer-only | accepted     |      no      |      yes      |  fail  | buyer not accredited  |
// | 4 | ACCREDITED + filter    | accepted     | wrong filter |      no       |  fail  | subtype mismatch      |
// | 5 | ACCREDITED + filter    | accepted     | right filter |      no       |  pass  | subtype match         |
// | 6 | QP, buyer+seller       | accepted     |     yes      |      no       |  fail  | seller also gated     |
// | 7 | QP, buyer+seller       | accepted     |     yes      |      yes      |  pass  | both qualified        |
//
// Config/authorization
// | # | case                        | expect              |
// |---|-----------------------------|---------------------|
// | 8 | initialize zero badge       | revert InvalidBadge |
// | 9 | updateParameters by stranger| revert (not admin)  |
// ─────────────────────────────────────────────────────────────────────────────

contract LexChexBadgeKindConditionTest is SecondaryConditionTestBase {
    LexChexBadgeKindCondition internal cond;

    function setUp() public {
        _setUpBase();
        cond = _deploy(CategoryKind.ACCREDITED_INVESTOR, "", false);
    }

    function _deploy(CategoryKind kind, string memory filter, bool checkSeller)
        internal
        returns (LexChexBadgeKindCondition c)
    {
        c = LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(
                    LexChexBadgeKindCondition.initialize, (address(auth), address(badge), kind, filter, checkSeller)
                )
            )
        );
    }

    function _check(LexChexBadgeKindCondition c, bytes32 agreementId) internal view returns (bool) {
        return c.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_BuyerOnly_Posting_Passes() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertTrue(_check(cond, bytes32(0)));
    }

    // 2
    function test_BuyerOnly_Accredited_Passes() public {
        badge.setValidKind(buyer, CategoryKind.ACCREDITED_INVESTOR, "", true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(cond, AGREEMENT_ID));
    }

    // 3
    function test_BuyerOnly_NotAccredited_Fails() public {
        badge.setValidKind(seller, CategoryKind.ACCREDITED_INVESTOR, "", true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(cond, AGREEMENT_ID));
    }

    // 4
    function test_Filter_Mismatch_Fails() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.ACCREDITED_INVESTOR, "Reg D 501(a)(5)", false);
        badge.setValidKind(buyer, CategoryKind.ACCREDITED_INVESTOR, "", true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(c, AGREEMENT_ID));
    }

    // 5
    function test_Filter_Match_Passes() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.ACCREDITED_INVESTOR, "Reg D 501(a)(5)", false);
        badge.setValidKind(buyer, CategoryKind.ACCREDITED_INVESTOR, "Reg D 501(a)(5)", true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(c, AGREEMENT_ID));
    }

    // 6
    function test_CheckSeller_SellerMissing_Fails() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.QUALIFIED_PURCHASER, "", true);
        badge.setValidKind(buyer, CategoryKind.QUALIFIED_PURCHASER, "", true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(c, AGREEMENT_ID));
    }

    // 7
    function test_CheckSeller_BothQualified_Passes() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.QUALIFIED_PURCHASER, "", true);
        badge.setValidKind(buyer, CategoryKind.QUALIFIED_PURCHASER, "", true);
        badge.setValidKind(seller, CategoryKind.QUALIFIED_PURCHASER, "", true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(c, AGREEMENT_ID));
    }

    // 8
    function test_Initialize_ZeroBadge_Reverts() public {
        LexChexBadgeKindCondition impl = new LexChexBadgeKindCondition();
        vm.expectRevert(LexChexBadgeKindCondition.InvalidBadge.selector);
        _proxy(
            address(impl),
            abi.encodeCall(
                LexChexBadgeKindCondition.initialize, (address(auth), address(0), CategoryKind.QIB, "", false)
            )
        );
    }

    // 9
    function test_UpdateParameters_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        cond.updateParameters(CategoryKind.QIB, "", true);
    }
}

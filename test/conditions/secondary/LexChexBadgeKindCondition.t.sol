// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CategoryKind, Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {LexChexBadgeKindCondition} from "../../../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// LexChexBadgeKindCondition — parameterizable investor-status gate on the LeXcheXBadge layer.
//
// Legal/economic intent: one primitive deployed per investor-status parameterization —
// AccreditedInvestor (buyer only, §4(a)(7)), QIB (buyer only, Rule 144A), QualifiedPurchaser
// (buyer + seller, §3(c)(7)). An optional investorType filter narrows within the kind.
//
// Real integration: investor status is a real badge credential of the required kind (its investorType
// carries the filter); parties are resolved from a real posted/accepted sell offer.
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

contract LexChexBadgeKindConditionTest is SecondaryConditionIntegrationBase {
    LexChexBadgeKindCondition internal cond;
    bytes32 internal constant CAT_ACC = keccak256("cat.acc");
    bytes32 internal constant CAT_QP = keccak256("cat.qp");

    function setUp() public {
        _setUpIntegration();
        _createCategory(CAT_ACC, CategoryKind.ACCREDITED_INVESTOR, address(0), 0);
        _createCategory(CAT_QP, CategoryKind.QUALIFIED_PURCHASER, address(0), 0);
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

    function _grant(address who, bytes32 categoryId, string memory investorType) internal {
        Credential memory c;
        c.investorName = "Inv";
        c.investorType = investorType;
        c.investorJurisdiction = "US";
        _mintCred(who, categoryId, c);
    }

    function _check(LexChexBadgeKindCondition c, bytes32 offerId, bytes32 agreementId) internal view returns (bool) {
        return c.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, agreementId);
    }

    // 1
    function test_BuyerOnly_Posting_Passes() public {
        assertTrue(_check(cond, _postSell(), bytes32(0)));
    }

    // 2
    function test_BuyerOnly_Accredited_Passes() public {
        _grant(buyer, CAT_ACC, "");
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(cond, offerId, settlementId));
    }

    // 3
    function test_BuyerOnly_NotAccredited_Fails() public {
        _grant(seller, CAT_ACC, "");
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(cond, offerId, settlementId));
    }

    // 4
    function test_Filter_Mismatch_Fails() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.ACCREDITED_INVESTOR, "Reg D 501(a)(5)", false);
        _grant(buyer, CAT_ACC, "");
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(c, offerId, settlementId));
    }

    // 5
    function test_Filter_Match_Passes() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.ACCREDITED_INVESTOR, "Reg D 501(a)(5)", false);
        _grant(buyer, CAT_ACC, "Reg D 501(a)(5)");
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(c, offerId, settlementId));
    }

    // 6
    function test_CheckSeller_SellerMissing_Fails() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.QUALIFIED_PURCHASER, "", true);
        _grant(buyer, CAT_QP, "");
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(c, offerId, settlementId));
    }

    // 7
    function test_CheckSeller_BothQualified_Passes() public {
        LexChexBadgeKindCondition c = _deploy(CategoryKind.QUALIFIED_PURCHASER, "", true);
        _grant(buyer, CAT_QP, "");
        _grant(seller, CAT_QP, "");
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(c, offerId, settlementId));
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

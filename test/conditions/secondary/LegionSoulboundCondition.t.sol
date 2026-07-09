// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, OfferSide, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {LegionSoulboundCondition} from "../../../src/libs/conditions/secondary/LegionSoulboundCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// LegionSoulboundCondition — issuer-specific credential category/tier gate.
//
// Legal/economic intent: enforce issuer-specific gating not captured by generic credentials —
// syndicate-circle restrictions, non-accredited-tier requirements. Configured with a required
// category and whether it applies to the buyer only, or buyer and seller.
//
// Scenario × outcome
// | # | applyToSeller | context       | buyer cred | seller cred | expect | rationale                     |
// |---|:-------------:|---------------|:----------:|:-----------:|:------:|-------------------------------|
// | 1 |      no       | SELL posting  |    n/a     |     no      |  pass  | buyer unknown, seller ungated |
// | 2 |      no       | accepted      |    yes     |     no      |  pass  | buyer in the circle           |
// | 3 |      no       | accepted      |     no     |     yes     |  fail  | buyer not in the circle       |
// | 4 |     yes       | accepted      |    yes     |     no      |  fail  | seller also gated             |
// | 5 |     yes       | accepted      |    yes     |     yes     |  pass  | both in the circle            |
// | 6 |     yes       | SELL posting  |    n/a     |     no      |  fail  | seller gated even at posting  |
//
// Config/authorization
// | # | case                            | expect                |
// |---|---------------------------------|-----------------------|
// | 7 | initialize zero badge           | revert InvalidBadge   |
// | 8 | initialize zero category        | revert InvalidCategory|
// | 9 | updateConfig by stranger        | revert (not admin)    |
// ─────────────────────────────────────────────────────────────────────────────

contract LegionSoulboundConditionTest is SecondaryConditionTestBase {
    LegionSoulboundCondition internal legion;
    bytes32 internal constant CAT = keccak256("cat.legion");

    function setUp() public {
        _setUpBase();
        legion = _deploy(false);
    }

    function _deploy(bool applyToSeller) internal returns (LegionSoulboundCondition c) {
        c = LegionSoulboundCondition(
            _proxy(
                address(new LegionSoulboundCondition()),
                abi.encodeCall(LegionSoulboundCondition.initialize, (address(auth), address(badge), CAT, applyToSeller))
            )
        );
    }

    function _check(LegionSoulboundCondition c, bytes32 agreementId) internal view returns (bool) {
        return c.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_BuyerOnly_Posting_SellerUngated_Passes() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertTrue(_check(legion, bytes32(0)));
    }

    // 2
    function test_BuyerOnly_Accepted_BuyerInCircle_Passes() public {
        badge.setValidCredential(buyer, CAT, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(legion, AGREEMENT_ID));
    }

    // 3
    function test_BuyerOnly_Accepted_BuyerNotInCircle_Fails() public {
        badge.setValidCredential(seller, CAT, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(legion, AGREEMENT_ID));
    }

    // 4
    function test_ApplyToSeller_SellerMissing_Fails() public {
        LegionSoulboundCondition c = _deploy(true);
        badge.setValidCredential(buyer, CAT, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(c, AGREEMENT_ID));
    }

    // 5
    function test_ApplyToSeller_BothInCircle_Passes() public {
        LegionSoulboundCondition c = _deploy(true);
        badge.setValidCredential(buyer, CAT, true);
        badge.setValidCredential(seller, CAT, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(c, AGREEMENT_ID));
    }

    // 6
    function test_ApplyToSeller_Posting_SellerMissing_Fails() public {
        LegionSoulboundCondition c = _deploy(true);
        dm.setOffer(OFFER_ID, _sellOffer());
        assertFalse(_check(c, bytes32(0)));
    }

    // 7
    function test_Initialize_ZeroBadge_Reverts() public {
        LegionSoulboundCondition impl = new LegionSoulboundCondition();
        vm.expectRevert(LegionSoulboundCondition.InvalidBadge.selector);
        _proxy(
            address(impl), abi.encodeCall(LegionSoulboundCondition.initialize, (address(auth), address(0), CAT, false))
        );
    }

    // 8
    function test_Initialize_ZeroCategory_Reverts() public {
        LegionSoulboundCondition impl = new LegionSoulboundCondition();
        vm.expectRevert(LegionSoulboundCondition.InvalidCategory.selector);
        _proxy(
            address(impl),
            abi.encodeCall(LegionSoulboundCondition.initialize, (address(auth), address(badge), bytes32(0), false))
        );
    }

    // 9
    function test_UpdateConfig_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        legion.updateConfig(address(badge), CAT, true);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, OfferSide} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {EligibilityCondition} from "../../../src/libs/conditions/secondary/EligibilityCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// EligibilityCondition — both parties must be admin-cleared to trade.
//
// Catch-all gate backing offchain eligibility review (KYC/AML, tax forms, ERISA, …). The admin
// toggles a per-account clearance flag; an uncleared party cannot clear a secondary trade. Buyer
// is unknown at posting, so buyer-facing checks short-circuit until a settlement exists.
//
// Scenario × outcome
// | # | context       | seller cleared | buyer cleared | expect | rationale                     |
// |---|---------------|:--------------:|:-------------:|:------:|-------------------------------|
// | 1 | SELL posting  |      yes       |      n/a      |  pass  | buyer unknown, seller cleared |
// | 2 | SELL posting  |       no       |      n/a      |  fail  | seller not cleared            |
// | 3 | SELL accepted |      yes       |      yes      |  pass  | both cleared                  |
// | 4 | SELL accepted |      yes       |       no      |  fail  | buyer not cleared             |
// | 5 | SELL accepted |       no       |      yes      |  fail  | seller clearance revoked      |
// | 6 | BUY posting   |      n/a       |      yes/no   |  gate  | offeror is the buyer          |
//
// Config/authorization
// | # | case                        | expect                 |
// |---|-----------------------------|------------------------|
// | 7 | setClearance zero account   | revert InvalidAccount  |
// | 8 | setClearance by stranger    | revert (not admin)     |
// ─────────────────────────────────────────────────────────────────────────────

contract EligibilityConditionTest is SecondaryConditionTestBase {
    EligibilityCondition internal eligibility;

    function setUp() public {
        _setUpBase();
        eligibility = EligibilityCondition(
            _proxy(address(new EligibilityCondition()), abi.encodeCall(EligibilityCondition.initialize, (address(auth))))
        );
    }

    function _clear(address who, bool v) internal {
        eligibility.setClearance(who, v);
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return eligibility.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_SellPosting_SellerCleared_Passes() public {
        _clear(seller, true);
        dm.setOffer(OFFER_ID, _sellOffer());
        assertTrue(_check(bytes32(0)));
    }

    // 2
    function test_SellPosting_SellerNotCleared_Fails() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertFalse(_check(bytes32(0)));
    }

    // 3
    function test_SellAccepted_BothCleared_Passes() public {
        _clear(seller, true);
        _clear(buyer, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 4
    function test_SellAccepted_BuyerNotCleared_Fails() public {
        _clear(seller, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 5
    function test_SellAccepted_SellerClearanceRevoked_Fails() public {
        _clear(buyer, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 6
    function test_BuyPosting_BuyerGate() public {
        Offer memory o = _sellOffer();
        o.side = OfferSide.BUY;
        o.offeror = buyer;
        o.tokenId = 0;
        dm.setOffer(OFFER_ID, o);

        assertFalse(_check(bytes32(0)));
        _clear(buyer, true);
        assertTrue(_check(bytes32(0)));
    }

    // 7
    function test_SetClearance_ZeroAccount_Reverts() public {
        vm.expectRevert(EligibilityCondition.InvalidAccount.selector);
        eligibility.setClearance(address(0), true);
    }

    // 8
    function test_SetClearance_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        eligibility.setClearance(buyer, true);
    }
}

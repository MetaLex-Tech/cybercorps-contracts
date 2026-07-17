// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CategoryKind} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, OfferSide, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {BorgAuth} from "../../../src/libs/auth.sol";
import {KYCAMLCondition} from "../../../src/libs/conditions/secondary/KYCAMLCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// KYCAMLCondition — both parties must hold a valid, unexpired KYC/AML badge.
//
// Legal/economic intent: a KYC/AML gate on every counterparty; an unvetted, revoked, or
// never-onboarded party cannot clear a secondary trade. Buyer is unknown at posting, so
// buyer-facing checks short-circuit until a settlement exists.
//
// Scenario × outcome
// | # | context            | seller KYC | buyer KYC | expect | rationale                              |
// |---|--------------------|:----------:|:---------:|:------:|----------------------------------------|
// | 1 | SELL posting       |    yes     |    n/a    |  pass  | buyer unknown, seller vetted           |
// | 2 | SELL posting       |     no     |    n/a    |  fail  | seller not onboarded                   |
// | 3 | SELL accepted      |    yes     |    yes    |  pass  | both vetted                            |
// | 4 | SELL accepted      |    yes     |     no    |  fail  | buyer not onboarded                    |
// | 5 | SELL accepted      |     no     |    yes    |  fail  | seller credential lapsed post-listing  |
// | 6 | BUY posting        |    n/a     |    yes    |  pass  | offeror is the buyer, vetted           |
// | 7 | BUY posting        |    n/a     |     no    |  fail  | buyer not onboarded                    |
//
// Config/authorization
// | # | case                                    | expect                 |
// |---|-----------------------------------------|------------------------|
// | 8 | initialize with zero badge              | revert InvalidBadge    |
// | 9 | updateBadge by owner                     | badge updated          |
// |10 | updateBadge by stranger                  | revert (not admin)     |
// |11 | updateBadge to zero                      | revert InvalidBadge    |
// ─────────────────────────────────────────────────────────────────────────────

contract KYCAMLConditionTest is SecondaryConditionTestBase {
    KYCAMLCondition internal kyc;

    function setUp() public {
        _setUpBase();
        kyc = KYCAMLCondition(
            _proxy(
                address(new KYCAMLCondition()),
                abi.encodeCall(KYCAMLCondition.initialize, (address(auth), address(badge)))
            )
        );
    }

    function _kyc(address who, bool v) internal {
        badge.setValidKind(who, CategoryKind.KYC_AML, "", v);
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return kyc.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_SellPosting_SellerVetted_Passes() public {
        _kyc(seller, true);
        dm.setOffer(OFFER_ID, _sellOffer());
        assertTrue(_check(bytes32(0)));
    }

    // 2
    function test_SellPosting_SellerUnvetted_Fails() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertFalse(_check(bytes32(0)));
    }

    // 3
    function test_SellAccepted_BothVetted_Passes() public {
        _kyc(seller, true);
        _kyc(buyer, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 4
    function test_SellAccepted_BuyerUnvetted_Fails() public {
        _kyc(seller, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 5
    function test_SellAccepted_SellerCredentialLapsed_Fails() public {
        _kyc(buyer, true);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 6 & 7
    function test_BuyPosting_BuyerVettedGate() public {
        Offer memory o = _sellOffer();
        o.side = OfferSide.BUY;
        o.offeror = buyer;
        o.tokenId = 0;
        dm.setOffer(OFFER_ID, o);

        assertFalse(_check(bytes32(0)));
        _kyc(buyer, true);
        assertTrue(_check(bytes32(0)));
    }

    // 8
    function test_Initialize_ZeroBadge_Reverts() public {
        KYCAMLCondition impl = new KYCAMLCondition();
        vm.expectRevert(KYCAMLCondition.InvalidBadge.selector);
        _proxy(address(impl), abi.encodeCall(KYCAMLCondition.initialize, (address(auth), address(0))));
    }

    // 9
    function test_UpdateBadge_ByOwner_Succeeds() public {
        MockBadgeLike b = new MockBadgeLike();
        kyc.updateBadge(address(b));
        assertEq(address(kyc.badge()), address(b));
    }

    // 10
    function test_UpdateBadge_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        kyc.updateBadge(address(badge));
    }

    // 11
    function test_UpdateBadge_Zero_Reverts() public {
        vm.expectRevert(KYCAMLCondition.InvalidBadge.selector);
        kyc.updateBadge(address(0));
    }
}

// Minimal non-zero address that can stand in as a badge for the updateBadge success path.
contract MockBadgeLike {}

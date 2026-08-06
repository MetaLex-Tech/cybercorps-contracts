// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {EligibilityCondition} from "../../../src/libs/conditions/secondary/EligibilityCondition.sol";
import {SecondaryConditionIntegrationBase, SpvFixture} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// EligibilityCondition — both parties must be admin-cleared to trade.
//
// Catch-all gate backing offchain eligibility review (KYC/AML, tax forms, ERISA, …). The admin
// toggles a per-account clearance flag; an uncleared party cannot clear a secondary trade. Buyer
// is unknown at posting, so buyer-facing checks short-circuit until a settlement exists.
//
// Real integration: parties are resolved from real posted/accepted offers — a sell offer (seller =
// offeror, buyer = escrow counterparty) and a buy offer (offeror is the buyer).
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

contract EligibilityConditionTest is SecondaryConditionIntegrationBase {
    EligibilityCondition internal eligibility;

    function setUp() public {
        _setUpIntegration();
        eligibility = EligibilityCondition(
            _proxy(address(new EligibilityCondition()), abi.encodeCall(EligibilityCondition.initialize, (address(auth))))
        );
    }

    function _clear(address who, bool v) internal {
        eligibility.setClearance(address(corp), who, v);
    }

    function _check(bytes32 offerId, bytes32 agreementId) internal view returns (bool) {
        return eligibility.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, agreementId);
    }

    // 1
    function test_SellPosting_SellerCleared_Passes() public {
        _clear(seller, true);
        assertTrue(_check(_postSell(), bytes32(0)));
    }

    // 2
    function test_SellPosting_SellerNotCleared_Fails() public {
        assertFalse(_check(_postSell(), bytes32(0)));
    }

    // 3
    function test_SellAccepted_BothCleared_Passes() public {
        _clear(seller, true);
        _clear(buyer, true);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));
    }

    // 4
    function test_SellAccepted_BuyerNotCleared_Fails() public {
        _clear(seller, true);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 5
    function test_SellAccepted_SellerClearanceRevoked_Fails() public {
        _clear(buyer, true);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 6
    function test_BuyPosting_BuyerGate() public {
        bytes32 offerId = _postBuy();
        assertFalse(_check(offerId, bytes32(0)));
        _clear(buyer, true);
        assertTrue(_check(offerId, bytes32(0)));
    }

    // 7
    function test_SetClearance_ZeroAccount_Reverts() public {
        vm.expectRevert(EligibilityCondition.InvalidAccount.selector);
        eligibility.setClearance(address(corp), address(0), true);
    }

    // 8
    function test_SetClearance_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        eligibility.setClearance(address(corp), buyer, true);
    }

    // A clearance answers for the SPV that granted it. One GP's review must not admit that party
    // everywhere on the platform.
    function test_Clearance_IsPerSpv() public {
        SpvFixture otherSpv = new SpvFixture(address(auth));
        _clear(seller, true);
        _clear(buyer, true);

        assertTrue(eligibility.cleared(address(corp), buyer));
        assertFalse(eligibility.cleared(address(otherSpv), buyer), "clearance did not travel");

        eligibility.setClearance(address(otherSpv), buyer, true);
        assertTrue(eligibility.cleared(address(otherSpv), buyer));
    }
}
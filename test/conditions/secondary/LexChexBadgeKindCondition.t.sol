// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {K_ACCREDITED, K_QP, K_QIB} from "../../../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {LexChexBadgeKindCondition} from "../../../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// LexChexBadgeKindCondition — parameterizable investor-status gate on the LeXcheXBadge layer.
//
// Legal/economic intent: one primitive deployed per investor-status parameterization —
// AccreditedInvestor (buyer only, §4(a)(7)), QIB (buyer only, Rule 144A), QualifiedPurchaser
// (buyer + seller, §3(c)(7)), NonUSPerson (buyer only, Reg S). The status is a single fact-key
// (K_ACCREDITED / K_QP / K_QIB / K_NON_US).
//
// Real integration: investor status is a real badge credential asserting the required fact-key; parties
// are resolved from a real posted/accepted sell offer.
//
// Scenario × outcome
// | # | config                 | context      | buyer status | seller status | expect | rationale             |
// |---|------------------------|--------------|:------------:|:-------------:|:------:|-----------------------|
// | 1 | ACCREDITED, buyer-only | SELL posting |     n/a      |      no       |  pass  | seller ungated        |
// | 2 | ACCREDITED, buyer-only | accepted     |     yes      |      no       |  pass  | buyer accredited      |
// | 3 | ACCREDITED, buyer-only | accepted     |      no      |      yes      |  fail  | buyer not accredited  |
// | 4 | QP, buyer+seller       | accepted     |     yes      |      no       |  fail  | seller also gated     |
// | 5 | QP, buyer+seller       | accepted     |     yes      |      yes      |  pass  | both qualified        |
//
// Config/authorization
// | # | case                        | expect              |
// |---|-----------------------------|---------------------|
// | 6 | initialize zero badge       | revert InvalidBadge |
// | 7 | updateParameters by stranger| revert (not admin)  |
// ─────────────────────────────────────────────────────────────────────────────

contract LexChexBadgeKindConditionTest is SecondaryConditionIntegrationBase {
    LexChexBadgeKindCondition internal cond;

    function setUp() public {
        _setUpIntegration();
        cond = _deploy(K_ACCREDITED, false);
    }

    function _deploy(uint256 kindKey, bool checkSeller) internal returns (LexChexBadgeKindCondition c) {
        c = LexChexBadgeKindCondition(
            _proxy(
                address(new LexChexBadgeKindCondition()),
                abi.encodeCall(
                    LexChexBadgeKindCondition.initialize, (address(auth), address(badge), kindKey, checkSeller)
                )
            )
        );
    }

    /// @dev Grants a status credential asserting `kindKey` (status keys carry no value).
    function _grant(address who, uint256 kindKey) internal {
        Credential memory c;
        _mintCred(who, kindKey, c);
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
        _grant(buyer, K_ACCREDITED);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(cond, offerId, settlementId));
    }

    // 3
    function test_BuyerOnly_NotAccredited_Fails() public {
        _grant(seller, K_ACCREDITED);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(cond, offerId, settlementId));
    }

    // 4
    function test_CheckSeller_SellerMissing_Fails() public {
        LexChexBadgeKindCondition c = _deploy(K_QP, true);
        _grant(buyer, K_QP);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(c, offerId, settlementId));
    }

    // 5
    function test_CheckSeller_BothQualified_Passes() public {
        LexChexBadgeKindCondition c = _deploy(K_QP, true);
        _grant(buyer, K_QP);
        _grant(seller, K_QP);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(c, offerId, settlementId));
    }

    // 6
    function test_Initialize_ZeroBadge_Reverts() public {
        LexChexBadgeKindCondition impl = new LexChexBadgeKindCondition();
        vm.expectRevert(LexChexBadgeKindCondition.InvalidBadge.selector);
        _proxy(
            address(impl),
            abi.encodeCall(
                LexChexBadgeKindCondition.initialize, (address(auth), address(0), K_QIB, false)
            )
        );
    }

    // 7
    function test_UpdateParameters_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        cond.updateParameters(K_QIB, true);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {
    K_ACCREDITED,
    K_BO_COUNT,
    K_INVESTOR_TYPE,
    K_QP,
    K_QIB,
    K_SPV_WHITELIST,
    K_SYNDICATE,
    K_US_STATE
} from "../../../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {LexChexBadgeKindCondition} from "../../../src/libs/conditions/secondary/LexChexBadgeKindCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// LexChexBadgeKindCondition — parameterizable investor-status gate on the LeXcheXBadge layer.
//
// Legal/economic intent: one primitive deployed per parameterization. Four read a status the party carries
// everywhere — AccreditedInvestor (buyer only, §4(a)(7)), QIB (buyer only, Rule 144A), QualifiedPurchaser
// (buyer + seller, §3(c)(7)), NonUSPerson (buyer only, Reg S). Two read an entitlement the issuer grants per
// SPV — SpvWhitelist and Syndicate (§4.1.3A) — which is checked against the offer's own SPV, so a grant made
// for another SPV never clears the gate.
//
// Real integration: status and entitlement alike are real badge credentials asserting the required fact-key;
// parties are resolved from a real posted/accepted sell offer.
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
// Scoped entitlements — read against the offer's SPV
// | #  | config          | buyer's grant           | expect | rationale                          |
// |----|-----------------|-------------------------|:------:|------------------------------------|
// | 6  | SPV_WHITELIST   | this SPV                |  pass  | admitted where the offer lives     |
// | 7  | SPV_WHITELIST   | another SPV             |  fail  | membership never travels           |
// | 8  | SYNDICATE       | this SPV                |  pass  | seated in the issuer's circle      |
// | 9  | SYNDICATE       | whitelist on this SPV   |  fail  | admission is not a seat            |
//
// Config/authorization
// | #  | case                              | expect                |
// |----|-----------------------------------|-----------------------|
// | 10 | initialize zero badge             | revert InvalidBadge   |
// | 11 | updateParameters by stranger      | revert (not admin)    |
// | 12 | initialize kindKey 0              | revert InvalidKindKey |
// | 13 | updateParameters kindKey 0        | revert InvalidKindKey |
// | 14 | updateParameters undefined bit    | revert InvalidKindKey |
// | 15 | updateParameters scoped + status  | revert InvalidKindKey |
// | 16 | updateParameters two scoped keys  | revert InvalidKindKey |
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

    /// @dev Grants a scoped entitlement asserting `kindKey` for one SPV.
    function _grantScoped(address who, uint256 kindKey, address spv) internal {
        Credential memory c;
        c.scope = spv;
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

    // ── Scoped entitlements ─────────────────────────────────────────────────

    // 6
    function test_Whitelist_ForThisSpv_Passes() public {
        LexChexBadgeKindCondition c = _deploy(K_SPV_WHITELIST, false);
        _grantScoped(buyer, K_SPV_WHITELIST, address(corp));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(c, offerId, settlementId));
    }

    // 7 — the same grant made for a different SPV is no admission to this one
    function test_Whitelist_ForAnotherSpv_Fails() public {
        LexChexBadgeKindCondition c = _deploy(K_SPV_WHITELIST, false);
        _grantScoped(buyer, K_SPV_WHITELIST, makeAddr("otherSpv"));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(c, offerId, settlementId));
    }

    // 8
    function test_Syndicate_ForThisSpv_Passes() public {
        LexChexBadgeKindCondition c = _deploy(K_SYNDICATE, false);
        _grantScoped(buyer, K_SYNDICATE, address(corp));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(c, offerId, settlementId));
    }

    // 9 — admission to the SPV is not a seat in its issuer's circle
    function test_Syndicate_WhitelistDoesNotSubstitute_Fails() public {
        LexChexBadgeKindCondition c = _deploy(K_SYNDICATE, false);
        _grantScoped(buyer, K_SPV_WHITELIST, address(corp));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(c, offerId, settlementId));
    }

    // ── Config / authorization ──────────────────────────────────────────────

    // 10
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

    // 11
    function test_UpdateParameters_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        cond.updateParameters(K_QIB, true);
    }

    // 12 — an unset key would match every credential, degrading the gate to "buyer holds any badge"
    function test_Initialize_ZeroKindKey_Reverts() public {
        LexChexBadgeKindCondition impl = new LexChexBadgeKindCondition();
        bytes memory initData =
            abi.encodeCall(LexChexBadgeKindCondition.initialize, (address(auth), address(badge), 0, false));
        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        _proxy(address(impl), initData);
    }

    // 13
    function test_UpdateParameters_ZeroKindKey_Reverts() public {
        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        cond.updateParameters(0, false);
    }

    // 14 — an undefined bit can never be asserted, so it would block every trade
    function test_UpdateParameters_UndefinedKindKey_Reverts() public {
        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        cond.updateParameters(1 << 200, false);
    }

    // 15 — an entitlement is read against one SPV and a status is not, so no single credential can answer
    // both halves of a mixed key
    function test_UpdateParameters_ScopedPlusStatus_Reverts() public {
        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        cond.updateParameters(K_QP | K_SYNDICATE, false);
    }

    // 16 — accepting either of two entitlements is a second condition, not this one
    function test_UpdateParameters_TwoScopedKeys_Reverts() public {
        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        cond.updateParameters(K_SPV_WHITELIST | K_SYNDICATE, false);
    }

    // ── Audit findings ──────────────────────────────────────────────────────────

    // M3 — a value key asks if a party recorded a fact, not if they qualify, so wiring one here would turn
    // an accreditation gate into "has KYC". Only statuses and entitlements are things a gate can ask.
    function test_Audit_M3_ValueKeyRejectedAsStatusGate() public {
        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        cond.updateParameters(K_INVESTOR_TYPE, false);

        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        cond.updateParameters(K_US_STATE, false);

        // Nor hidden alongside a real status key.
        vm.expectRevert(LexChexBadgeKindCondition.InvalidKindKey.selector);
        cond.updateParameters(K_ACCREDITED | K_BO_COUNT, false);

        // Two statuses together are still fine: one credential has to assert both.
        cond.updateParameters(K_QP | K_QIB, false);
        assertEq(cond.kindKey(), K_QP | K_QIB);
    }
}

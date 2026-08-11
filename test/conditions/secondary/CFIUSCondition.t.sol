// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {K_INVESTOR_JURISDICTION, K_INVESTOR_TYPE, K_LOOKTHROUGH_JURISDICTION, InvestorType}
    from "../../../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {BadgeScopedCondition} from "../../../src/libs/conditions/secondary/BadgeScopedCondition.sol";
import {CFIUSCondition} from "../../../src/libs/conditions/secondary/CFIUSCondition.sol";
import {SecondaryConditionIntegrationBase, SpvFixture} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// CFIUSCondition — FIRRMA gating for CFIUS-sensitive SPVs.
//
// Real integration: the buyer's US-ness is derived from one real jurisdiction credential; the buyer is
// resolved from a real posted+accepted sell offer (the settlement is created once in setUp).
//
// Scenario × outcome (deployed tidUsBusiness = true)
// | # | scenario                                        | expect | rationale                        |
// |---|-------------------------------------------------|:------:|----------------------------------|
// | 1 | tidUsBusiness = false (dormant)                 |  pass  | condition not engaged            |
// | 2 | posting (no buyer)                              |  pass  | nothing to gate                  |
// | 3 | U.S. buyer, unblocked jurisdiction              |  pass  | no CFIUS concern                 |
// | 4 | non-U.S.-person badge, no clearance             |  fail  | foreign acquirer, unreviewed     |
// | 5 | non-U.S. jurisdiction, no clearance             |  fail  | foreign acquirer, unreviewed     |
// | 6 | non-U.S. person WITH recorded clearance         |  pass  | GP review cleared it             |
// | 7 | U.S. buyer whose jurisdiction is blocked-listed |  fail  | blocked-affiliation, needs review|
// |7b | U.S. buyer, blocked look-through jurisdiction   |  fail  | U.S.-registered, foreign control |
//
// Config/authorization
// | # | case                          | expect              |
// |---|-------------------------------|---------------------|
// | 8 | setCfiusClearance zero buyer  | revert InvalidBuyer |
// | 9 | setCfiusClearance by stranger | revert (not admin)  |
// |10 | initialize zero badge         | revert InvalidBadge |
// ─────────────────────────────────────────────────────────────────────────────

contract CFIUSConditionTest is SecondaryConditionIntegrationBase {
    CFIUSCondition internal cfius;
    bytes32 internal offerId;
    bytes32 internal settlementId;

    function setUp() public {
        _setUpIntegration();
        cfius = _deploy(true, new string[](0));
        _setJurisdiction("US");
        (offerId, settlementId) = _postAndAcceptSell();
    }

    function _deploy(bool tid, string[] memory blocked) internal returns (CFIUSCondition c) {
        c = CFIUSCondition(
            _proxy(
                address(new CFIUSCondition()),
                abi.encodeCall(CFIUSCondition.initialize, (address(auth), address(badge)))
            )
        );
        c.setTidUsBusiness(address(corp), tid);
        if (blocked.length > 0) c.setBlockedJurisdictions(address(corp), blocked);
    }

    function _setJurisdiction(string memory j) internal {
        Credential memory c;
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = j;
        _mintCred(buyer, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION, c);
    }

    /// @dev Non-U.S.-person status is now derived from the jurisdiction fact: mint a superseding non-U.S.
    /// jurisdiction credential (the newest valid one governs the read).
    function _markNonUsPerson() internal {
        _setJurisdiction("KY");
    }

    function _check() internal view returns (bool) {
        return cfius.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId);
    }

    // 1
    function test_Dormant_Passes() public {
        cfius.setTidUsBusiness(address(corp), false);
        _setJurisdiction("KY");
        assertTrue(_check());
    }

    // 2
    function test_Posting_NoBuyer_Passes() public view {
        assertTrue(cfius.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0)));
    }

    // 3
    function test_UsBuyer_Unblocked_Passes() public view {
        assertTrue(_check());
    }

    // 4
    function test_NonUsPersonBadge_Fails() public {
        _markNonUsPerson();
        assertFalse(_check());
    }

    // 5
    function test_NonUsJurisdiction_Fails() public {
        _setJurisdiction("KY");
        assertFalse(_check());
    }

    // 6
    function test_NonUsPerson_WithClearance_Passes() public {
        _markNonUsPerson();
        cfius.setCfiusClearance(address(corp), buyer, true);
        assertTrue(_check());
    }

    // 7
    function test_UsBuyer_BlockedJurisdiction_Fails() public {
        string[] memory blocked = new string[](1);
        blocked[0] = "United States";
        cfius = _deploy(true, blocked);
        _setJurisdiction("United States");
        assertFalse(_check());
    }

    // 7a — polarity: anything not a canonical U.S. spelling reads non-U.S. and falls through to requiring
    // clearance, CFIUS's fail-closed direction.
    function test_UsJurisdiction_CanonicalSpellingsOnly() public {
        string[3] memory us = ["US", "USA", "United States"];
        for (uint256 i = 0; i < us.length; i++) {
            _setJurisdiction(us[i]);
            assertTrue(_check(), us[i]);
        }

        string[3] memory notUs = ["us", "U.S.", "KY"];
        for (uint256 i = 0; i < notUs.length; i++) {
            _setJurisdiction(notUs[i]);
            assertFalse(_check(), notUs[i]);
        }
    }

    // 8
    function test_SetClearance_ZeroBuyer_Reverts() public {
        vm.expectRevert(CFIUSCondition.InvalidBuyer.selector);
        cfius.setCfiusClearance(address(corp), address(0), true);
    }

    // 9
    function test_SetClearance_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        cfius.setCfiusClearance(address(corp), buyer, true);
    }

    // 10
    function test_Initialize_ZeroBadge_Reverts() public {
        CFIUSCondition impl = new CFIUSCondition();
        vm.expectRevert(BadgeScopedCondition.InvalidBadge.selector);
        _proxy(address(impl), abi.encodeCall(CFIUSCondition.initialize, (address(auth), address(0))));
    }

    // ── Audit findings ──────────────────────────────────────────────────────────

    // L3 — a foreign acquirer already needs clearance, so listing a foreign jurisdiction changed nothing.
    // The list is for the U.S.-registered buyer under foreign control, so it reads the look-through too.
    function test_Audit_L3_BlockedLookThroughJurisdictionNeedsClearance() public {
        string[] memory blocked = new string[](1);
        blocked[0] = "CN";
        CFIUSCondition c = _deploy(true, blocked);

        // A Delaware vehicle: U.S.-registered, so nationality alone clears it.
        Credential memory usOnly;
        usOnly.investorType = InvestorType.ENTITY;
        usOnly.investorJurisdiction = "US";
        _mintCred(buyer, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION, usOnly);
        assertTrue(c.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));

        // But its look-through puts control in a jurisdiction the GP treats as sensitive.
        Credential memory controlled;
        controlled.investorType = InvestorType.ENTITY;
        controlled.investorJurisdiction = "US";
        controlled.lookThroughJurisdiction = "CN";
        _mintCred(
            buyer, K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION, controlled
        );
        assertFalse(
            c.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId),
            "foreign control needs review even with a U.S. domicile"
        );

        // The GP's recorded review still settles it, as for anyone else.
        c.setCfiusClearance(address(corp), buyer, true);
        assertTrue(c.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
    }

    // A CFIUS review is the GP's, for their own SPV. It must not clear that buyer elsewhere, and an SPV
    // that never records a determination stays dormant.
    function test_Config_AndClearance_ArePerSpv() public {
        SpvFixture otherSpv = new SpvFixture(address(auth));
        cfius.setCfiusClearance(address(corp), buyer, true);

        assertTrue(cfius.cfiusCleared(address(corp), buyer));
        assertFalse(cfius.cfiusCleared(address(otherSpv), buyer), "clearance did not travel");

        assertTrue(cfius.tidUsBusiness(address(corp)));
        assertFalse(cfius.tidUsBusiness(address(otherSpv)), "no determination recorded elsewhere");
    }

    // Attaching the condition says CFIUS reaches this SPV, so silence is not the fund exception. Only a
    // recorded determination — either way — lets a trade through.
    function test_UnconfiguredSpv_Blocks() public {
        CFIUSCondition fresh = CFIUSCondition(
            _proxy(
                address(new CFIUSCondition()),
                abi.encodeCall(CFIUSCondition.initialize, (address(auth), address(badge)))
            )
        );
        assertFalse(fresh.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));

        // The GP records the fund exception: dormant, and it passes.
        fresh.setTidUsBusiness(address(corp), false);
        assertTrue(fresh.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
    }

    function test_Setters_ByStranger_Revert() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        cfius.setTidUsBusiness(address(corp), false);
        vm.expectRevert();
        cfius.setBlockedJurisdictions(address(corp), new string[](0));
        vm.stopPrank();
    }
}
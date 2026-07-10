// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {CategoryKind} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {CFIUSCondition} from "../../../src/libs/conditions/secondary/CFIUSCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// CFIUSCondition — FIRRMA gating for CFIUS-sensitive SPVs.
//
// Legal/economic intent: for SPVs holding a TID U.S. business (and not qualifying for the FIRRMA
// investment-fund exception), block transfers to non-U.S. persons — or U.S. persons from a blocked-
// affiliation jurisdiction — until the GP records a manual CFIUS clearance. Dormant (always passes)
// when the SPV is not TID-sensitive.
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
//
// Config/authorization
// | # | case                          | expect              |
// |---|-------------------------------|---------------------|
// | 8 | setCfiusClearance zero buyer  | revert InvalidBuyer |
// | 9 | setCfiusClearance by stranger | revert (not admin)  |
// |10 | initialize zero badge         | revert InvalidBadge |
// ─────────────────────────────────────────────────────────────────────────────

contract CFIUSConditionTest is SecondaryConditionTestBase {
    CFIUSCondition internal cfius;

    function setUp() public {
        _setUpBase();
        cfius = _deploy(true, new string[](0));
        badge.setInvestorJurisdiction(buyer, "US");
        _postSellAndAccept(_sellOffer(), _sellEscrow());
    }

    function _deploy(bool tid, string[] memory blocked) internal returns (CFIUSCondition c) {
        c = CFIUSCondition(
            _proxy(
                address(new CFIUSCondition()),
                abi.encodeCall(CFIUSCondition.initialize, (address(auth), address(badge), tid, blocked))
            )
        );
    }

    function _check() internal view returns (bool) {
        return cfius.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, AGREEMENT_ID);
    }

    // 1
    function test_Dormant_Passes() public {
        cfius.setTidUsBusiness(false);
        badge.setInvestorJurisdiction(buyer, "KY");
        assertTrue(_check());
    }

    // 2
    function test_Posting_NoBuyer_Passes() public view {
        assertTrue(cfius.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, bytes32(0)));
    }

    // 3
    function test_UsBuyer_Unblocked_Passes() public view {
        assertTrue(_check());
    }

    // 4
    function test_NonUsPersonBadge_Fails() public {
        badge.setValidKind(buyer, CategoryKind.NON_US_PERSON, "", true);
        assertFalse(_check());
    }

    // 5
    function test_NonUsJurisdiction_Fails() public {
        badge.setInvestorJurisdiction(buyer, "KY");
        assertFalse(_check());
    }

    // 6
    function test_NonUsPerson_WithClearance_Passes() public {
        badge.setValidKind(buyer, CategoryKind.NON_US_PERSON, "", true);
        cfius.setCfiusClearance(buyer, true);
        assertTrue(_check());
    }

    // 7
    function test_UsBuyer_BlockedJurisdiction_Fails() public {
        string[] memory blocked = new string[](1);
        blocked[0] = "United States";
        cfius = _deploy(true, blocked);
        badge.setInvestorJurisdiction(buyer, "United States");
        assertFalse(_check());
    }

    // 8
    function test_SetClearance_ZeroBuyer_Reverts() public {
        vm.expectRevert(CFIUSCondition.InvalidBuyer.selector);
        cfius.setCfiusClearance(address(0), true);
    }

    // 9
    function test_SetClearance_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        cfius.setCfiusClearance(buyer, true);
    }

    // 10
    function test_Initialize_ZeroBadge_Reverts() public {
        CFIUSCondition impl = new CFIUSCondition();
        vm.expectRevert(CFIUSCondition.InvalidBadge.selector);
        _proxy(
            address(impl), abi.encodeCall(CFIUSCondition.initialize, (address(auth), address(0), true, new string[](0)))
        );
    }
}

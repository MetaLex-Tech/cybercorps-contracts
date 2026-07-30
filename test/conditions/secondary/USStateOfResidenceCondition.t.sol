// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {K_INVESTOR_JURISDICTION, K_INVESTOR_TYPE, K_US_STATE, InvestorType}
    from "../../../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {USStateOfResidenceCondition} from "../../../src/libs/conditions/secondary/USStateOfResidenceCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// USStateOfResidenceCondition — blue-sky state gating for U.S. acceptors (§6.9, Addendum D).
//
// Real integration: the acceptor's usState is a real badge credential; the buyer is resolved from a real
// posted+accepted sell offer, whose spvAddress is the CyberCorp — so the per-SPV setters target `corp`.
//
// Scenario × outcome
// | #  | scenario                                       | expect | rationale                          |
// |----|------------------------------------------------|:------:|------------------------------------|
// | 1  | posting (no acquirer)                          |  pass  | nothing to gate                    |
// | 2  | acceptor with no credential at all             |  fail  | jurisdiction unestablished         |
// | 3  | unestablished jurisdiction, unlisted state     |  fail  | jurisdiction unestablished         |
// | 4  | U.S. acceptor, no usState                      |  fail  | U.S. acceptor must record a state  |
// | 5  | non-U.S. acceptor, no usState                  |  pass  | out of blue-sky reach              |
// | 6  | non-U.S. acceptor, unlisted state              |  pass  | state not blocked                  |
// | 7  | non-U.S. acceptor carrying a blocked state     |  fail  | contradictory; blue sky wins       |
// | 8  | U.S. acceptor, unlisted state (CA)             |  pass  | state not blocked                  |
// | 9  | U.S. acceptor, NY, no Martin Act registration  |  fail  | NY default-blocked                 |
// | 10 | U.S. acceptor, NY, Martin Act registered       |  pass  | NY default cleared                 |
// | 11 | U.S. acceptor, GP-blocked state (AL)           |  fail  | explicitly blocked by SPV          |
// | 12 | GP blocks then unblocks a state                |  pass  | block is reversible                |
// | 13 | only canonical U.S. spellings screen           |  n/a   | guards this condition's own copy   |
//
// Config/authorization
// | #  | case                                | expect             |
// |----|-------------------------------------|--------------------|
// | 14 | setStateBlocked zero spv            | revert InvalidSpv  |
// | 15 | setStateBlocked by non-SPV-admin    | revert (not admin) |
// | 16 | setMartinActRegistered by non-admin | revert (not admin) |
// | 17 | initialize zero badge               | revert InvalidBadge|
// ─────────────────────────────────────────────────────────────────────────────

contract USStateOfResidenceConditionTest is SecondaryConditionIntegrationBase {
    USStateOfResidenceCondition internal usState;

    function setUp() public {
        _setUpIntegration();
        usState = USStateOfResidenceCondition(
            _proxy(
                address(new USStateOfResidenceCondition()),
                abi.encodeCall(USStateOfResidenceCondition.initialize, (address(auth), address(badge)))
            )
        );
    }

    /// @dev Mints the acceptor's credential; each fact is asserted only when non-empty, as `_validate`
    /// requires a value for every asserted key. Minting again supersedes — the newest valid one governs.
    function _mintCredential(string memory jurisdiction, bytes2 state) internal {
        Credential memory c;
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = jurisdiction;
        c.usState = state;
        uint256 asserts = K_INVESTOR_TYPE;
        if (bytes(jurisdiction).length > 0) asserts |= K_INVESTOR_JURISDICTION;
        if (state != bytes2(0)) asserts |= K_US_STATE;
        _mintCred(buyer, asserts, c);
    }

    function _accepted(string memory jurisdiction, bytes2 state) internal returns (bool) {
        _mintCredential(jurisdiction, state);
        return _check();
    }

    function _acceptedUs(bytes2 state) internal returns (bool) {
        return _accepted("US", state);
    }

    function _check() internal returns (bool) {
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        return _checkOn(offerId, settlementId);
    }

    function _checkOn(bytes32 offerId, bytes32 settlementId) internal view returns (bool) {
        return usState.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId);
    }

    // 1
    function test_Posting_NoAcquirer_Passes() public {
        assertTrue(_checkOn(_postSell(), bytes32(0)));
    }

    // 2
    function test_NoCredential_Fails() public {
        assertFalse(_check());
    }

    // 3
    function test_UnknownJurisdiction_Fails() public {
        assertFalse(_accepted("", "CA"));
    }

    // 4
    function test_UsAcceptor_NoState_Fails() public {
        assertFalse(_acceptedUs(bytes2(0)));
    }

    // 5
    function test_NonUsAcceptor_NoState_Passes() public {
        assertTrue(_accepted("KY", bytes2(0)));
    }

    // 6
    function test_NonUsAcceptor_UnlistedState_Passes() public {
        assertTrue(_accepted("KY", "CA"));
    }

    // 7 — the foreign jurisdiction does not excuse a blocked state
    function test_NonUsAcceptor_BlockedState_Fails() public {
        usState.setStateBlocked(address(corp), "AL", true);
        assertFalse(_accepted("KY", "AL"));
    }

    // 8
    function test_UnlistedState_Passes() public {
        assertTrue(_acceptedUs("CA"));
    }

    // 9
    function test_NewYork_Default_Fails() public {
        assertFalse(_acceptedUs("NY"));
    }

    // 10
    function test_NewYork_MartinActRegistered_Passes() public {
        usState.setMartinActRegistered(address(corp), true);
        assertTrue(_acceptedUs("NY"));
    }

    // 11
    function test_GpBlockedState_Fails() public {
        usState.setStateBlocked(address(corp), "AL", true);
        assertFalse(_acceptedUs("AL"));
    }

    // 12
    function test_BlockThenUnblock_Passes() public {
        usState.setStateBlocked(address(corp), "AL", true);
        usState.setStateBlocked(address(corp), "AL", false);
        assertTrue(_acceptedUs("AL"));
    }

    // 13 — polarity: only a canonical U.S. spelling obliges the acceptor to record a state, so a misread
    // would silently excuse one. Decides the no-state case alone; a recorded state is screened either way.
    function test_UsJurisdiction_CanonicalSpellingsOnly() public {
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();

        string[3] memory us = ["US", "USA", "United States"];
        for (uint256 i = 0; i < us.length; i++) {
            _mintCredential(us[i], bytes2(0));
            assertFalse(_checkOn(offerId, settlementId), us[i]);
        }

        string[3] memory notUs = ["us", "U.S.", "KY"];
        for (uint256 i = 0; i < notUs.length; i++) {
            _mintCredential(notUs[i], bytes2(0));
            assertTrue(_checkOn(offerId, settlementId), notUs[i]);
        }
    }

    // 14
    function test_SetStateBlocked_ZeroSpv_Reverts() public {
        vm.expectRevert(USStateOfResidenceCondition.InvalidSpv.selector);
        usState.setStateBlocked(address(0), "AL", true);
    }

    // 15
    function test_SetStateBlocked_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        usState.setStateBlocked(address(corp), "AL", true);
    }

    // 16
    function test_SetMartinAct_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        usState.setMartinActRegistered(address(corp), true);
    }

    // 17
    function test_Initialize_ZeroBadge_Reverts() public {
        USStateOfResidenceCondition impl = new USStateOfResidenceCondition();
        vm.expectRevert(USStateOfResidenceCondition.InvalidBadge.selector);
        _proxy(address(impl), abi.encodeCall(USStateOfResidenceCondition.initialize, (address(auth), address(0))));
    }
}

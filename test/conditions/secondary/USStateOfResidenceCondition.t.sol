// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ATTR_INVESTOR_JURISDICTION, ATTR_US_STATE, CategoryKind, Credential}
    from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {USStateOfResidenceCondition} from "../../../src/libs/conditions/secondary/USStateOfResidenceCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// USStateOfResidenceCondition — blue-sky state gating for U.S. acceptors (§6.9, Addendum D).
//
// Legal/economic intent: honor state securities (blue-sky) restrictions. Each SPV keeps a blocked-
// states list; New York is blocked by default until the SPV registers under the Martin Act. Non-U.S.
// acceptors carry no usState and are silent; U.S. acceptors in an unlisted state pass. Setters are
// gated on the SPV's own BorgAuth admin (the GP), not the condition's global admin.
//
// Real integration: the acceptor's usState is a real badge credential; the buyer is resolved from a real
// posted+accepted sell offer, whose spvAddress is the CyberCorp — so the per-SPV setters target `corp`.
//
// Scenario × outcome
// | # | scenario                                        | expect | rationale                          |
// |---|-------------------------------------------------|:------:|------------------------------------|
// | 1 | posting (no acquirer)                           |  pass  | nothing to gate                    |
// | 2 | non-U.S. acceptor (no usState)                  |  pass  | no state attribute                 |
// | 3 | U.S. acceptor, unlisted state (CA)              |  pass  | state not blocked                  |
// | 4 | U.S. acceptor, NY, no Martin Act registration   |  fail  | NY default-blocked                 |
// | 5 | U.S. acceptor, NY, Martin Act registered        |  pass  | NY default cleared                 |
// | 6 | U.S. acceptor, GP-blocked state (AL)            |  fail  | explicitly blocked by SPV          |
// | 7 | GP blocks then unblocks a state                 |  pass  | block is reversible                |
//
// Config/authorization
// | # | case                                | expect             |
// |---|-------------------------------------|--------------------|
// | 8 | setStateBlocked zero spv            | revert InvalidSpv  |
// | 9 | setStateBlocked by non-SPV-admin    | revert (not admin) |
// |10 | setMartinActRegistered by non-admin | revert (not admin) |
// |11 | initialize zero badge               | revert InvalidBadge|
// ─────────────────────────────────────────────────────────────────────────────

contract USStateOfResidenceConditionTest is SecondaryConditionIntegrationBase {
    USStateOfResidenceCondition internal usState;
    bytes32 internal constant CAT_KYC = keccak256("cat.kyc");

    function setUp() public {
        _setUpIntegration();
        _createCategory(CAT_KYC, CategoryKind.KYC_AML, address(0), ATTR_INVESTOR_JURISDICTION | ATTR_US_STATE);
        usState = USStateOfResidenceCondition(
            _proxy(
                address(new USStateOfResidenceCondition()),
                abi.encodeCall(USStateOfResidenceCondition.initialize, (address(auth), address(badge)))
            )
        );
    }

    function _accepted(bytes2 state) internal returns (bool) {
        Credential memory c;
        c.investorName = "Inv";
        c.investorType = "Individual";
        c.investorJurisdiction = state == bytes2(0) ? "KY" : "US";
        c.usState = state;
        _mintCred(buyer, CAT_KYC, c);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        return usState.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId);
    }

    // 1
    function test_Posting_NoAcquirer_Passes() public {
        bytes32 offerId = _postSell();
        assertTrue(usState.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0)));
    }

    // 2
    function test_NonUsAcceptor_Passes() public {
        assertTrue(_accepted(bytes2(0)));
    }

    // 3
    function test_UnlistedState_Passes() public {
        assertTrue(_accepted("CA"));
    }

    // 4
    function test_NewYork_Default_Fails() public {
        assertFalse(_accepted("NY"));
    }

    // 5
    function test_NewYork_MartinActRegistered_Passes() public {
        usState.setMartinActRegistered(address(corp), true);
        assertTrue(_accepted("NY"));
    }

    // 6
    function test_GpBlockedState_Fails() public {
        usState.setStateBlocked(address(corp), "AL", true);
        assertFalse(_accepted("AL"));
    }

    // 7
    function test_BlockThenUnblock_Passes() public {
        usState.setStateBlocked(address(corp), "AL", true);
        usState.setStateBlocked(address(corp), "AL", false);
        assertTrue(_accepted("AL"));
    }

    // 8
    function test_SetStateBlocked_ZeroSpv_Reverts() public {
        vm.expectRevert(USStateOfResidenceCondition.InvalidSpv.selector);
        usState.setStateBlocked(address(0), "AL", true);
    }

    // 9
    function test_SetStateBlocked_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        usState.setStateBlocked(address(corp), "AL", true);
    }

    // 10
    function test_SetMartinAct_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        usState.setMartinActRegistered(address(corp), true);
    }

    // 11
    function test_Initialize_ZeroBadge_Reverts() public {
        USStateOfResidenceCondition impl = new USStateOfResidenceCondition();
        vm.expectRevert(USStateOfResidenceCondition.InvalidBadge.selector);
        _proxy(address(impl), abi.encodeCall(USStateOfResidenceCondition.initialize, (address(auth), address(0))));
    }
}

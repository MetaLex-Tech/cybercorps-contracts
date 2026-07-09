// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {Section4a7DisclosureCondition} from "../../../src/libs/conditions/secondary/Section4a7DisclosureCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Section4a7DisclosureCondition — §4(a)(7) information-delivery gate (two-part test).
//
// Legal/economic intent: §4(a)(7)(d)(3) requires (1) the SPV to have a fresh information package on
// record (incl. two years of GAAP financials), enforced from posting onward, and (2) the buyer to
// acknowledge receipt of it, recorded as a party value at acceptance. Both must hold to clear.
//
// Scenario × outcome (freshness policy = 480 days)
// | # | context   | package        | buyer ack | expect | rationale                        |
// |---|-----------|----------------|:---------:|:------:|----------------------------------|
// | 1 | posting   | none           |    n/a    |  fail  | package missing (part 1)         |
// | 2 | posting   | fresh          |    n/a    |  pass  | ack deferred to acceptance       |
// | 3 | accepted  | fresh          |    yes    |  pass  | both parts satisfied             |
// | 4 | accepted  | fresh          |     no    |  fail  | receipt not acknowledged         |
// | 5 | accepted  | stale          |    yes    |  fail  | package stale (part 1 fails)     |
//
// Config/authorization
// | # | case                              | expect                    |
// |---|-----------------------------------|---------------------------|
// | 6 | initialize zero registry          | revert InvalidRegistry    |
// | 7 | initialize empty acknowledgment   | revert InvalidAcknowledgment |
// | 8 | initialize zero maxAge            | revert InvalidMaxAge      |
// | 9 | setDisclosurePackage non-SPV-admin| revert (not admin)        |
// ─────────────────────────────────────────────────────────────────────────────

contract Section4a7DisclosureConditionTest is SecondaryConditionTestBase {
    Section4a7DisclosureCondition internal disc;
    uint256 internal constant MAX_AGE = 480 days;
    uint256 internal constant NOW = 500 days;
    string internal constant URI = "ipfs://4a7-package";
    string internal constant ACK = "4a7:information-package-received";

    function setUp() public {
        _setUpBase();
        vm.warp(NOW);
        disc = Section4a7DisclosureCondition(
            _proxy(
                address(new Section4a7DisclosureCondition()),
                abi.encodeCall(
                    Section4a7DisclosureCondition.initialize, (address(auth), address(registry), ACK, MAX_AGE)
                )
            )
        );
        dm.setOffer(OFFER_ID, _sellOffer());
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return disc.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_Posting_NoPackage_Fails() public view {
        assertFalse(_check(bytes32(0)));
    }

    // 2
    function test_Posting_FreshPackage_Passes() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW));
        assertTrue(_check(bytes32(0)));
    }

    // 3
    function test_Accepted_FreshAndAcked_Passes() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW));
        registry.setSignerValues(AGREEMENT_ID, buyer, _one(ACK));
        dm.setEscrow(AGREEMENT_ID, _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 4
    function test_Accepted_FreshNoAck_Fails() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW));
        dm.setEscrow(AGREEMENT_ID, _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 5
    function test_Accepted_StalePackage_Fails() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW - MAX_AGE - 1));
        registry.setSignerValues(AGREEMENT_ID, buyer, _one(ACK));
        dm.setEscrow(AGREEMENT_ID, _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 6
    function test_Initialize_ZeroRegistry_Reverts() public {
        Section4a7DisclosureCondition impl = new Section4a7DisclosureCondition();
        vm.expectRevert(Section4a7DisclosureCondition.InvalidRegistry.selector);
        _proxy(
            address(impl),
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (address(auth), address(0), ACK, MAX_AGE))
        );
    }

    // 7
    function test_Initialize_EmptyAck_Reverts() public {
        Section4a7DisclosureCondition impl = new Section4a7DisclosureCondition();
        vm.expectRevert(Section4a7DisclosureCondition.InvalidAcknowledgment.selector);
        _proxy(
            address(impl),
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (address(auth), address(registry), "", MAX_AGE))
        );
    }

    // 8
    function test_Initialize_ZeroMaxAge_Reverts() public {
        Section4a7DisclosureCondition impl = new Section4a7DisclosureCondition();
        vm.expectRevert(Section4a7DisclosureCondition.InvalidMaxAge.selector);
        _proxy(
            address(impl),
            abi.encodeCall(Section4a7DisclosureCondition.initialize, (address(auth), address(registry), ACK, 0))
        );
    }

    // 9
    function test_SetDisclosure_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW));
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {Rule144DisclosureCondition} from "../../../src/libs/conditions/secondary/Rule144DisclosureCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Rule144DisclosureCondition — current public information gate for Rule 144 trades.
//
// Legal/economic intent: Rule 144(c)(2) / 15c2-11(b)(5) require current public information about the
// issuer. The SPV records a disclosure package (URI + as-of date); the gate fails when the record is
// missing or older than the freshness policy (e.g. balance sheet > 16 months). SPV-wide: no party
// lookup, enforced at posting, acceptance, and finalize alike.
//
// Scenario × outcome (freshness policy = 480 days)
// | # | scenario                                     | expect | rationale                        |
// |---|----------------------------------------------|:------:|----------------------------------|
// | 1 | no disclosure record                         |  fail  | no current public information    |
// | 2 | fresh record                                 |  pass  | within freshness policy          |
// | 3 | exactly at the freshness boundary            |  pass  | boundary inclusive (<=)          |
// | 4 | stale by one second                          |  fail  | outside freshness policy         |
// | 5 | fresh record, evaluated at acceptance context|  pass  | SPV-wide, context-independent    |
//
// Config/authorization
// | # | case                              | expect                 |
// |---|-----------------------------------|------------------------|
// | 6 | setDisclosurePackage zero spv     | revert InvalidSpv      |
// | 7 | setDisclosurePackage asOf 0       | revert InvalidTimestamp|
// | 8 | setDisclosurePackage future asOf  | revert InvalidTimestamp|
// | 9 | setDisclosurePackage non-SPV-admin| revert (not admin)     |
// |10 | initialize zero maxAge            | revert InvalidMaxAge   |
// ─────────────────────────────────────────────────────────────────────────────

contract Rule144DisclosureConditionTest is SecondaryConditionTestBase {
    Rule144DisclosureCondition internal disc;
    uint256 internal constant MAX_AGE = 480 days;
    uint256 internal constant NOW = 500 days;
    string internal constant URI = "ipfs://144-package";

    function setUp() public {
        _setUpBase();
        vm.warp(NOW);
        disc = Rule144DisclosureCondition(
            _proxy(
                address(new Rule144DisclosureCondition()),
                abi.encodeCall(Rule144DisclosureCondition.initialize, (address(auth), MAX_AGE))
            )
        );
        dm.setOffer(OFFER_ID, _sellOffer());
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return disc.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_NoRecord_Fails() public view {
        assertFalse(_check(bytes32(0)));
    }

    // 2
    function test_FreshRecord_Passes() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW));
        assertTrue(_check(bytes32(0)));
    }

    // 3
    function test_AtFreshnessBoundary_Passes() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW - MAX_AGE));
        assertTrue(_check(bytes32(0)));
    }

    // 4
    function test_StaleByOneSecond_Fails() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW - MAX_AGE - 1));
        assertFalse(_check(bytes32(0)));
    }

    // 5
    function test_FreshRecord_AcceptanceContext_Passes() public {
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW));
        dm.setEscrow(AGREEMENT_ID, _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 6
    function test_SetDisclosure_ZeroSpv_Reverts() public {
        vm.expectRevert(Rule144DisclosureCondition.InvalidSpv.selector);
        disc.setDisclosurePackage(address(0), URI, uint64(NOW));
    }

    // 7
    function test_SetDisclosure_ZeroAsOf_Reverts() public {
        vm.expectRevert(Rule144DisclosureCondition.InvalidTimestamp.selector);
        disc.setDisclosurePackage(address(dm), URI, 0);
    }

    // 8
    function test_SetDisclosure_FutureAsOf_Reverts() public {
        vm.expectRevert(Rule144DisclosureCondition.InvalidTimestamp.selector);
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW + 1));
    }

    // 9
    function test_SetDisclosure_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        disc.setDisclosurePackage(address(dm), URI, uint64(NOW));
    }

    // 10
    function test_Initialize_ZeroMaxAge_Reverts() public {
        Rule144DisclosureCondition impl = new Rule144DisclosureCondition();
        vm.expectRevert(Rule144DisclosureCondition.InvalidMaxAge.selector);
        _proxy(address(impl), abi.encodeCall(Rule144DisclosureCondition.initialize, (address(auth), 0)));
    }
}

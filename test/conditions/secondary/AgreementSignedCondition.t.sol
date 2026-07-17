// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {AgreementSignedCondition} from "../../../src/libs/conditions/secondary/AgreementSignedCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// AgreementSignedCondition — every party's signature recorded on the trade agreement.
//
// Legal/economic intent: a defensive invariant that the settlement agreement is fully executed before
// it clears. Trivially true at acceptance (acceptOffer creates it fully signed) but guards any flow
// that composes conditions independently. Silent at posting — no settlement agreement exists yet.
//
// Scenario × outcome
// | # | context   | all parties signed | expect | rationale                     |
// |---|-----------|:------------------:|:------:|-------------------------------|
// | 1 | posting   |        n/a          |  pass  | no agreement yet              |
// | 2 | accepted  |        yes          |  pass  | fully executed                |
// | 3 | accepted  |        no           |  fail  | a signature is missing        |
//
// Config/authorization
// | # | case                        | expect                 |
// |---|-----------------------------|------------------------|
// | 4 | initialize zero registry    | revert InvalidRegistry |
// | 5 | updateRegistry zero         | revert InvalidRegistry |
// | 6 | updateRegistry by stranger  | revert (not admin)     |
// ─────────────────────────────────────────────────────────────────────────────

contract AgreementSignedConditionTest is SecondaryConditionTestBase {
    AgreementSignedCondition internal signed;

    function setUp() public {
        _setUpBase();
        signed = AgreementSignedCondition(
            _proxy(
                address(new AgreementSignedCondition()),
                abi.encodeCall(AgreementSignedCondition.initialize, (address(auth), address(registry)))
            )
        );
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return signed.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_Posting_Silent_Passes() public view {
        assertTrue(_check(bytes32(0)));
    }

    // 2
    function test_Accepted_AllSigned_Passes() public {
        registry.setAllPartiesSigned(AGREEMENT_ID, true);
        assertTrue(_check(AGREEMENT_ID));
    }

    // 3
    function test_Accepted_NotAllSigned_Fails() public view {
        assertFalse(_check(AGREEMENT_ID));
    }

    // 4
    function test_Initialize_ZeroRegistry_Reverts() public {
        AgreementSignedCondition impl = new AgreementSignedCondition();
        vm.expectRevert(AgreementSignedCondition.InvalidRegistry.selector);
        _proxy(address(impl), abi.encodeCall(AgreementSignedCondition.initialize, (address(auth), address(0))));
    }

    // 5
    function test_UpdateRegistry_Zero_Reverts() public {
        vm.expectRevert(AgreementSignedCondition.InvalidRegistry.selector);
        signed.updateRegistry(address(0));
    }

    // 6
    function test_UpdateRegistry_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        signed.updateRegistry(address(registry));
    }
}

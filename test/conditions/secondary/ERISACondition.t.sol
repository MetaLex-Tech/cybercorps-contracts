// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {ExemptionPathway, Offer, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {ERISACondition} from "../../../src/libs/conditions/secondary/ERISACondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// ERISACondition — buyer's ERISA negative attestation (no plan assets).
//
// Legal/economic intent: keep "benefit plan investor" money out unless the buyer affirmatively
// attests it holds no plan assets. The attestation is a party value recorded on the settlement
// agreement at acceptance. Reg S trades are exempt (that pathway already requires a non-U.S. buyer),
// so the condition is silent there; and it is silent at posting (no settlement agreement yet).
//
// Scenario × outcome
// | # | context                         | attestation recorded | expect | rationale                       |
// |---|---------------------------------|----------------------|:------:|---------------------------------|
// | 1 | Reg S pathway                   |         no           |  pass  | silent for Reg S                |
// | 2 | posting (no agreement)          |         n/a          |  pass  | no attestation surface yet      |
// | 3 | accepted, exact attestation     |         yes          |  pass  | negative attestation on file    |
// | 4 | accepted, no party values       |         no           |  fail  | attestation missing             |
// | 5 | accepted, wrong value           |     wrong string     |  fail  | attestation does not match      |
// | 6 | accepted, attestation among many|         yes          |  pass  | scan finds the marker           |
//
// Config/authorization
// | # | case                               | expect                   |
// |---|------------------------------------|--------------------------|
// | 7 | initialize zero registry           | revert InvalidRegistry   |
// | 8 | initialize empty attestation       | revert InvalidAttestation|
// | 9 | updateAttestationValue empty       | revert InvalidAttestation|
// |10 | updateRegistry by stranger         | revert (not admin)       |
// ─────────────────────────────────────────────────────────────────────────────

contract ERISAConditionTest is SecondaryConditionTestBase {
    ERISACondition internal erisa;
    string internal constant ATTEST = "ERISA:no-plan-assets";

    function setUp() public {
        _setUpBase();
        erisa = ERISACondition(
            _proxy(
                address(new ERISACondition()),
                abi.encodeCall(ERISACondition.initialize, (address(auth), address(registry), ATTEST))
            )
        );
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return erisa.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_RegS_Silent_Passes() public {
        Offer memory o = _sellOffer();
        o.exemptionPathway = ExemptionPathway.REGULATION_S;
        _postSellAndAccept(o, _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 2
    function test_Posting_Silent_Passes() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertTrue(_check(bytes32(0)));
    }

    // 3
    function test_Accepted_ExactAttestation_Passes() public {
        registry.setSignerValues(AGREEMENT_ID, buyer, _one(ATTEST));
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 4
    function test_Accepted_NoValues_Fails() public {
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 5
    function test_Accepted_WrongValue_Fails() public {
        registry.setSignerValues(AGREEMENT_ID, buyer, _one("ERISA:is-a-plan"));
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 6
    function test_Accepted_AttestationAmongMany_Passes() public {
        string[] memory values = new string[](3);
        values[0] = "some-other-field";
        values[1] = ATTEST;
        values[2] = "4a7:ack";
        registry.setSignerValues(AGREEMENT_ID, buyer, values);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 7
    function test_Initialize_ZeroRegistry_Reverts() public {
        ERISACondition impl = new ERISACondition();
        vm.expectRevert(ERISACondition.InvalidRegistry.selector);
        _proxy(address(impl), abi.encodeCall(ERISACondition.initialize, (address(auth), address(0), ATTEST)));
    }

    // 8
    function test_Initialize_EmptyAttestation_Reverts() public {
        ERISACondition impl = new ERISACondition();
        vm.expectRevert(ERISACondition.InvalidAttestation.selector);
        _proxy(address(impl), abi.encodeCall(ERISACondition.initialize, (address(auth), address(registry), "")));
    }

    // 9
    function test_UpdateAttestationValue_Empty_Reverts() public {
        vm.expectRevert(ERISACondition.InvalidAttestation.selector);
        erisa.updateAttestationValue("");
    }

    // 10
    function test_UpdateRegistry_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        erisa.updateRegistry(address(registry));
    }
}

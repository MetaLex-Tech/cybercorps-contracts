// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {TaxInfoCondition} from "../../../src/libs/conditions/secondary/TaxInfoCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// TaxInfoCondition — blocks acceptance until the buyer's tax form is on file.
//
// Legal/economic intent: K-1 readiness and §1446(f) withholding posture require the acquirer's
// W-9 / W-8BEN(-E) on record before they can take the interest. The seller's record is readable
// but does NOT gate (it should already exist from primary issuance). Nothing to gate at posting.
//
// Scenario × outcome
// | # | context       | buyer form   | seller form | expect | rationale                          |
// |---|---------------|--------------|-------------|:------:|------------------------------------|
// | 1 | SELL posting  |    n/a       |    n/a      |  pass  | no acquirer yet                    |
// | 2 | SELL accepted | W-9          |    none     |  pass  | U.S. buyer form on file            |
// | 3 | SELL accepted | W-8BEN       |    none     |  pass  | non-U.S. buyer form on file        |
// | 4 | SELL accepted | none         |    W-9      |  fail  | seller's form does not cover buyer |
// | 5 | SELL accepted | NONE (empty) |    none     |  fail  | explicit NONE is not "on file"     |
// | 6 | SELL accepted | cleared      |    none     |  fail  | form withdrawn before settlement   |
//
// Config/authorization
// | # | case                                | expect                 |
// |---|-------------------------------------|------------------------|
// | 7 | setTaxForm zero account             | revert InvalidAccount  |
// | 8 | setTaxForm by stranger              | revert (not admin)     |
// | 9 | clearTaxForm by stranger            | revert (not admin)     |
// ─────────────────────────────────────────────────────────────────────────────

contract TaxInfoConditionTest is SecondaryConditionTestBase {
    TaxInfoCondition internal tax;

    function setUp() public {
        _setUpBase();
        tax = TaxInfoCondition(
            _proxy(address(new TaxInfoCondition()), abi.encodeCall(TaxInfoCondition.initialize, (address(auth))))
        );
    }

    function _check(bytes32 agreementId) internal view returns (bool) {
        return tax.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, agreementId);
    }

    // 1
    function test_Posting_NoBuyer_Passes() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertTrue(_check(bytes32(0)));
    }

    // 2
    function test_Accepted_BuyerW9_Passes() public {
        tax.setTaxForm(buyer, TaxInfoCondition.TaxFormType.W9, keccak256("w9"));
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 3
    function test_Accepted_BuyerW8BEN_Passes() public {
        tax.setTaxForm(buyer, TaxInfoCondition.TaxFormType.W8BEN, keccak256("w8"));
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertTrue(_check(AGREEMENT_ID));
    }

    // 4
    function test_Accepted_OnlySellerHasForm_Fails() public {
        tax.setTaxForm(seller, TaxInfoCondition.TaxFormType.W9, keccak256("w9"));
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 5
    function test_Accepted_ExplicitNone_Fails() public {
        tax.setTaxForm(buyer, TaxInfoCondition.TaxFormType.NONE, keccak256("none"));
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 6
    function test_Accepted_FormCleared_Fails() public {
        tax.setTaxForm(buyer, TaxInfoCondition.TaxFormType.W9, keccak256("w9"));
        tax.clearTaxForm(buyer);
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        assertFalse(_check(AGREEMENT_ID));
    }

    // 7
    function test_SetTaxForm_ZeroAccount_Reverts() public {
        vm.expectRevert(TaxInfoCondition.InvalidAccount.selector);
        tax.setTaxForm(address(0), TaxInfoCondition.TaxFormType.W9, keccak256("w9"));
    }

    // 8
    function test_SetTaxForm_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        tax.setTaxForm(buyer, TaxInfoCondition.TaxFormType.W9, keccak256("w9"));
    }

    // 9
    function test_ClearTaxForm_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        tax.clearTaxForm(buyer);
    }
}

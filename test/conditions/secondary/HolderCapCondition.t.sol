// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {Offer, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {HolderCapCondition} from "../../../src/libs/conditions/secondary/HolderCapCondition.sol";
import {SecondaryConditionTestBase} from "./SecondaryConditionMocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// HolderCapCondition — ICA §3(c)(1)/§3(c)(1)(C)/§3(c)(7) holder limits at transfer time.
//
// Legal/economic intent: keep the SPV within its Investment Company Act exception. A fresh holder
// counts against the numeric cap (100 / 250); an existing holder increasing a position does not; a
// look-through entity contributes its credentialed beneficial-owner count instead of 1; §3(c)(7)
// funds have no numeric cap. Offshore variants: count only U.S. residents (Touche Remnant), or block
// U.S. buyers outright. The count is read at acceptance/finalization, never at posting.
//
// Scenario × outcome (default deployment: §3(c)(1), cap = 100)
// |  # | scenario                                        | expect | rationale                             |
// |----|-------------------------------------------------|:------:|---------------------------------------|
// |  1 | posting (no acquirer)                           |  pass  | cap evaluated later                   |
// |  2 | fresh U.S. buyer, count 99 (+1 = 100)           |  pass  | lands exactly on the cap              |
// |  3 | fresh U.S. buyer, count 100 (+1 = 101)          |  fail  | would breach the cap                  |
// |  4 | existing holder (isLegalHolder), count 100      |  pass  | position increase, not a new holder   |
// |  5 | entity look-through boCount 5, count 95 (=100)  |  pass  | 5 BOs flow through, lands on cap      |
// |  6 | entity look-through boCount 5, count 96 (=101)  |  fail  | look-through breaches the cap         |
// |  7 | §3(c)(7) (cap 0), fresh buyer, count 500        |  pass  | no numeric cap                        |
// |  8 | blockUsInvestors, U.S. buyer                    |  fail  | offshore no-U.S.-investor floor       |
// |  9 | blockUsInvestors, non-U.S. buyer                |  pass  | floor only bites U.S. buyers          |
// | 10 | usResidentOnlyCount, non-U.S. buyer             |  pass  | non-U.S. acquirer not counted         |
// | 11 | usResidentOnlyCount, fresh U.S. buyer at cap    |  fail  | only U.S. residents counted, breaches |
//
// Config/authorization
// | # | case                              | expect              |
// |---|-----------------------------------|---------------------|
// |12 | initialize zero badge             | revert InvalidBadge |
// |13 | updateConfig by stranger          | revert (not admin)  |
// |14 | updateBadge by stranger           | revert (not admin)  |
// ─────────────────────────────────────────────────────────────────────────────

contract HolderCapConditionTest is SecondaryConditionTestBase {
    HolderCapCondition internal holderCap;

    function setUp() public {
        _setUpBase();
        holderCap = HolderCapCondition(
            _proxy(
                address(new HolderCapCondition()),
                abi.encodeCall(
                    HolderCapCondition.initialize,
                    (address(auth), address(badge), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false)
                )
            )
        );
        badge.setInvestorJurisdiction(buyer, "US");
    }

    function _check() internal returns (bool) {
        _postSellAndAccept(_sellOffer(), _sellEscrow());
        return holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, AGREEMENT_ID);
    }

    // 1
    function test_Posting_NoAcquirer_Passes() public {
        dm.setOffer(OFFER_ID, _sellOffer());
        assertTrue(holderCap.checkCondition(IDealManager(address(dm)), bytes4(0), OFFER_ID, bytes32(0)));
    }

    // 2
    function test_FreshUsBuyer_LandsOnCap_Passes() public {
        cert.setLookThroughHolderCount(99);
        assertTrue(_check());
    }

    // 3
    function test_FreshUsBuyer_BreachesCap_Fails() public {
        cert.setLookThroughHolderCount(100);
        assertFalse(_check());
    }

    // 4
    function test_ExistingHolder_PositionIncrease_Passes() public {
        cert.setLookThroughHolderCount(100);
        cert.setIsLegalHolder(buyer, true);
        assertTrue(_check());
    }

    // 5
    function test_EntityLookThrough_LandsOnCap_Passes() public {
        cert.setLookThroughHolderCount(95);
        badge.setBeneficialOwnerCount(buyer, 5);
        assertTrue(_check());
    }

    // 6
    function test_EntityLookThrough_BreachesCap_Fails() public {
        cert.setLookThroughHolderCount(96);
        badge.setBeneficialOwnerCount(buyer, 5);
        assertFalse(_check());
    }

    // 7
    function test_Section3c7_NoNumericCap_Passes() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
        cert.setLookThroughHolderCount(500);
        assertTrue(_check());
    }

    // 8
    function test_BlockUsInvestors_UsBuyer_Fails() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        cert.setLookThroughHolderCount(0);
        assertFalse(_check());
    }

    // 9
    function test_BlockUsInvestors_NonUsBuyer_Passes() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 100, false, true);
        badge.setInvestorJurisdiction(buyer, "KY");
        cert.setLookThroughHolderCount(0);
        assertTrue(_check());
    }

    // 10
    function test_UsResidentOnlyCount_NonUsBuyer_NotCounted_Passes() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 1, true, false);
        badge.setInvestorJurisdiction(buyer, "KY");
        // Even with a "full" U.S. tally, a non-U.S. acquirer does not add to the U.S.-resident count.
        cert.setUsLookThroughHolderCount(1);
        assertTrue(_check());
    }

    // 11
    function test_UsResidentOnlyCount_UsBuyerBreaches_Fails() public {
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C1, 1, true, false);
        // The printer's U.S.-resident look-through tally already stands at the cap (= 1). A fresh U.S.
        // buyer would make 2 > cap 1. (The base is the printer's maintained count; the base-side
        // look-through math itself is covered in CyberCertPrinterTest.)
        cert.setUsLookThroughHolderCount(1);
        assertFalse(_check());
    }

    // 12
    function test_Initialize_ZeroBadge_Reverts() public {
        HolderCapCondition impl = new HolderCapCondition();
        vm.expectRevert(HolderCapCondition.InvalidBadge.selector);
        _proxy(
            address(impl),
            abi.encodeCall(
                HolderCapCondition.initialize,
                (address(auth), address(0), HolderCapCondition.IcaException.SECTION_3C1, 100, false, false)
            )
        );
    }

    // 13
    function test_UpdateConfig_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.updateConfig(HolderCapCondition.IcaException.SECTION_3C7, 0, false, false);
    }

    // 14
    function test_UpdateBadge_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        holderCap.updateBadge(address(badge));
    }
}

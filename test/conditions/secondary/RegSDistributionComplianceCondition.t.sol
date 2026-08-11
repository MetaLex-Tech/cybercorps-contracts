// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {LedgerEntryToken} from "../../../src/LedgerEntryToken.sol";
import {
    RegSDistributionComplianceCondition
} from "../../../src/libs/conditions/secondary/RegSDistributionComplianceCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// RegSDistributionComplianceCondition — Regulation S distribution compliance period.
//
// Legal/economic intent: a Reg S resale requires the applicable distribution compliance period to
// have elapsed since the interest was acquired. The period is a per-SPV parameter encoded by counsel
// (issuer category 1/2/3). An unconfigured SPV fails closed; a missing acquisition anchor fails
// closed; a buy offer at posting has no seller yet and is verified at acceptance.
//
// Real integration: the config is keyed by the SPV (offer.spvAddress = corp); the seller lot's base
// acquisition timestamp is set via the real printer's admin override and the lot offered through a real
// postOffer.
//
// Scenario × outcome (compliance period = 365 days)
// | # | scenario                                         | expect | rationale                       |
// |---|--------------------------------------------------|:------:|---------------------------------|
// | 1 | SPV not configured (even if seasoned)            |  fail  | fail closed, no counsel config  |
// | 2 | configured, no acquisition record                |  fail  | fail closed                     |
// | 3 | configured, seasoned exactly the period          |  pass  | period elapsed (>=)             |
// | 4 | configured, not yet seasoned                     |  fail  | period not elapsed              |
// | 5 | configured, BUY offer at posting                 |  pass  | verified at acceptance          |
//
// Config/authorization
// | # | case                              | expect                |
// |---|-----------------------------------|-----------------------|
// | 6 | setRegSConfig zero spv            | revert InvalidSpv     |
// | 7 | setRegSConfig category 0          | revert InvalidCategory|
// | 8 | setRegSConfig category 4          | revert InvalidCategory|
// | 9 | setRegSConfig by non-SPV-admin    | revert (not admin)    |
// ─────────────────────────────────────────────────────────────────────────────

contract RegSDistributionComplianceConditionTest is SecondaryConditionIntegrationBase {
    RegSDistributionComplianceCondition internal regS;
    uint64 internal constant PERIOD = 365 days;
    uint256 internal constant NOW = 500 days;

    function setUp() public {
        _setUpIntegration();
        vm.warp(NOW);
        regS = RegSDistributionComplianceCondition(
            _proxy(
                address(new RegSDistributionComplianceCondition()),
                abi.encodeCall(RegSDistributionComplianceCondition.initialize, (address(auth)))
            )
        );
    }

    function _configure() internal {
        regS.setRegSConfig(address(corp), 3, PERIOD);
    }

    function _sellPosting(uint64 anchor) internal returns (bool) {
        LedgerEntryToken(address(printer)).setAcquisitionTimestamp(sellerTokenId, anchor);
        bytes32 offerId = _postSell();
        return regS.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0));
    }

    // 1
    function test_Unconfigured_FailsClosed() public {
        assertFalse(_sellPosting(uint64(NOW) - PERIOD));
    }

    // 2
    function test_Configured_NoRecord_FailsClosed() public {
        _configure();
        assertFalse(_sellPosting(0));
    }

    // 3
    function test_Configured_Seasoned_Passes() public {
        _configure();
        assertTrue(_sellPosting(uint64(NOW) - PERIOD));
    }

    // 4
    function test_Configured_NotSeasoned_Fails() public {
        _configure();
        assertFalse(_sellPosting(uint64(NOW) - (PERIOD - 1 days)));
    }

    // 5
    function test_Configured_BuyPosting_Passes() public {
        _configure();
        bytes32 offerId = _postBuy();
        assertTrue(regS.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, bytes32(0)));
    }

    // 6
    function test_SetRegSConfig_ZeroSpv_Reverts() public {
        vm.expectRevert(RegSDistributionComplianceCondition.InvalidSpv.selector);
        regS.setRegSConfig(address(0), 3, PERIOD);
    }

    // 7
    function test_SetRegSConfig_CategoryZero_Reverts() public {
        vm.expectRevert(RegSDistributionComplianceCondition.InvalidCategory.selector);
        regS.setRegSConfig(address(corp), 0, PERIOD);
    }

    // 8
    function test_SetRegSConfig_CategoryFour_Reverts() public {
        vm.expectRevert(RegSDistributionComplianceCondition.InvalidCategory.selector);
        regS.setRegSConfig(address(corp), 4, PERIOD);
    }

    // 9
    function test_SetRegSConfig_ByNonSpvAdmin_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        regS.setRegSConfig(address(corp), 3, PERIOD);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MinimumRaiseFixture} from "./RoundManagerMinimumRaiseTest.t.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {ILexChexMinter} from "../src/storage/RoundManagerStorage.sol";
import {ILexScrowStorage} from "../src/interfaces/ILexScrowStorage.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {ILexChex} from "../src/interfaces/ILexChex.sol";

/// @notice Minimum raise: commitments against ordinary allocation and LeXcheX minting.
/// @dev Separate from `RoundManagerMinimumRaiseTest` because one larger test contract hits a
/// via-IR compiler limit. All values are fictional.
contract RoundManagerMinimumRaiseCommitmentTest is MinimumRaiseFixture {
    function setUp() public {
        _deployFixture(address(0));
    }

    /// @notice Open commitments hold their capacity: an ordinary allocation after the minimum
    /// is met can use only what commitments leave, so each commitment settles in full.
    function test_AfterMet_OrdinaryAllocationLeavesCommittedCapacity() public {
        capOverride = MIN_RAISE + MAX_TICKET / 2; // room for both commitments and half a ticket
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        bytes32 a2 = _submitEOI(roundId, 2);
        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);
        _markMet(roundId, ids);

        uint256 before2 = paymentToken.balanceOf(investors[2]);
        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(a2, MAX_TICKET);
        // Only the uncommitted half ticket was available; the rest is refunded.
        assertEq(paymentToken.balanceOf(investors[2]), before2 + MAX_TICKET / 2);

        RoundManager(roundManager).settle(ids);
        assertEq(RoundManager(roundManager).getEscrowDetails(a0).buyerAssets[0].amount, MAX_TICKET);
        assertEq(RoundManager(roundManager).getEscrowDetails(a1).buyerAssets[0].amount, MAX_TICKET);
        assertEq(RoundManager(roundManager).getRound(roundId).raised, capOverride);
    }

    /// @notice An investor whose LeXcheX credential `allocate` would mint can be committed
    /// although the LeXcheX condition fails now; settlement mints it and checks every condition.
    function test_Commit_AllowsInvestorThatSettlementWouldCredential() public {
        (address lexChexCondition, address otherCondition) = _lexChexSetup();
        maxTicketOverride = 2 * MAX_TICKET; // $200k: the natural-person mint threshold
        naturalPersonNext = true;
        conditionsNext = [lexChexCondition];
        bytes32 roundId = _createMinimumRound(2 * MAX_TICKET);
        bytes32 a0 = _submitEOIAs(roundId, investors[0], investorKeys[0], 1, MIN_TICKET, 2 * MAX_TICKET);

        // Below the threshold no credential is minted, so the failing condition refuses.
        vm.prank(corpOwner);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        RoundManager(roundManager).setCommitments(_one(a0), _oneAmount(2 * MAX_TICKET - 1));

        // At the threshold settlement would mint it, so the commitment is accepted.
        _commit(_one(a0), _oneAmount(2 * MAX_TICKET));
        _markMet(roundId, _one(a0));

        // Settlement mints the credential, then requires every condition to pass.
        vm.mockCall(lexChexCondition, abi.encodeWithSelector(ICondition.checkCondition.selector), abi.encode(true));
        vm.expectCall(LEXCHEX_MINTER, abi.encodeWithSelector(ILexChexMinter.requestMintFor.selector));
        RoundManager(roundManager).settle(_one(a0));
        _assertAllocated(a0);

        // Any other failing condition still refuses the commitment.
        conditionsNext = [lexChexCondition, otherCondition];
        maxTicketOverride = 2 * MAX_TICKET + 1; // a distinct round id
        bytes32 roundB = _createMinimumRound(2 * MAX_TICKET);
        bytes32 b1 = _submitEOIAs(roundB, investors[1], investorKeys[1], 2, MIN_TICKET, 2 * MAX_TICKET);
        vm.prank(corpOwner);
        vm.expectRevert(ILexScrowStorage.AgreementConditionsNotMet.selector);
        RoundManager(roundManager).setCommitments(_one(b1), _oneAmount(2 * MAX_TICKET));
    }

    address internal constant LEXCHEX_MINTER = 0x0dD1a2a89eC172ac322B6a7a6c869180CBD0F960;

    /// @dev Investors 0 and 1 have no credential; the payment token is whitelisted; the
    /// RoundManager's LeXcheX condition and another condition both fail; the minter answers.
    function _lexChexSetup() internal returns (address lexChexCondition, address otherCondition) {
        lexChexCondition = 0x4a08547d57C8d01e59bA8F884aB90CEe0d6d5b42;
        otherCondition = makeAddr("otherCondition");
        address lexChex = 0xc8db0c3f47656aee725b0AD1835F9A3FbD0a0b62;
        for (uint256 i = 0; i < 2; i++)
            vm.mockCall(lexChex, abi.encodeWithSelector(ILexChex.hasValidLexCheX.selector, investors[i]), abi.encode(false));
        vm.prank(owner);
        RoundManagerFactory(rmFactory).setWhitelistedToken(address(paymentToken), true);
        vm.etch(lexChexCondition, hex"00");
        vm.etch(otherCondition, hex"00");
        vm.etch(LEXCHEX_MINTER, hex"00");
        vm.mockCall(lexChexCondition, abi.encodeWithSelector(ICondition.checkCondition.selector), abi.encode(false));
        vm.mockCall(otherCondition, abi.encodeWithSelector(ICondition.checkCondition.selector), abi.encode(false));
        vm.mockCall(
            LEXCHEX_MINTER,
            abi.encodeWithSelector(ILexChexMinter.requestMintFor.selector),
            abi.encode(bytes32(uint256(1)), uint256(7))
        );
    }

}

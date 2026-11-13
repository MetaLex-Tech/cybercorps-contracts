// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";
import {SecuritySeries, SecurityClass} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundLib, Round, RoundType} from "../src/libs/RoundLib.sol";
import {CyberCertData, EOI} from "../src/storage/RoundManagerStorage.sol";
import {Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";

/// @notice Shared fixture for the minimum raise tests.
abstract contract MinimumRaiseFixture is Test {
    using RoundLib for Round;

    MockPaymentToken internal paymentToken;
    CyberAgreementRegistry internal registry;
    CyberCorpFactory internal corpFactory;

    address internal corp;
    address internal roundManager;
    address internal rmFactory;

    address internal owner;
    address internal corpOwner;
    uint256 internal corpOwnerPrivKey;

    address[3] internal investors;
    uint256[3] internal investorKeys;

    uint256 internal constant MIN_TICKET = 1000 * 10 ** 6;
    uint256 internal constant MAX_TICKET = 100000 * 10 ** 6;
    uint256 internal constant RAISE_CAP = 1000000 * 10 ** 6;
    uint256 internal constant PRICE_PER_UNIT = 10 * 10 ** 18;
    uint256 internal constant VALUATION = 10000000 * 10 ** 18;
    uint256 internal constant ROUND_DURATION = 30 days;

    uint256 internal constant MIN_RAISE = 2 * MAX_TICKET;
    uint256 internal constant DEADLINE_SLACK = 30 days;

    event RoundMinimumSet(bytes32 indexed roundId, uint256 minRaise, uint256 deadline);
    event RoundMinimumMet(bytes32 indexed roundId, uint256 raised);

    /// @param v5Implementation when non-zero, the RoundManager reference implementation used to
    /// deploy the company (a deployed v5 build on a fork); zero keeps the local build.
    function _deployFixture(address v5Implementation) internal {
        (owner, ) = makeAddrAndKey("owner");
        (corpOwner, corpOwnerPrivKey) = makeAddrAndKey("corpOwner");
        (investors[0], investorKeys[0]) = makeAddrAndKey("investor0");
        (investors[1], investorKeys[1]) = makeAddrAndKey("investor1");
        (investors[2], investorKeys[2]) = makeAddrAndKey("investor2");

        paymentToken = new MockPaymentToken();

        (registry, corpFactory, , , , rmFactory, , ) = CyberCorpHelper.deployRegistryAndFactories(owner);

        vm.startPrank(owner);
        CyberCorpHelper.createTemplate(registry);
        RoundManagerFactory(rmFactory).setPlatformPayable(owner);
        RoundManagerFactory(rmFactory).setDefaultFeeRatio(25);
        if (v5Implementation != address(0)) {
            RoundManagerFactory(rmFactory).setRefImplementation(v5Implementation);
        }
        vm.stopPrank();

        (corp, , , , roundManager) = CyberCorpHelper.deployCorp(corpFactory, "Test Corp", corpOwner, corpOwner);

        for (uint256 i = 0; i < investors.length; i++) {
            paymentToken.transfer(investors[i], MAX_TICKET * 2);
            vm.prank(investors[i]);
            paymentToken.approve(roundManager, type(uint256).max);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 helpers
    //////////////////////////////////////////////////////////////*/

    function _draft(RoundType roundType, uint256 valuation)
        internal
        view
        returns (Round memory draft, CyberCertData[] memory certData)
    {
        string[] memory defaultLegend = new string[](1);
        defaultLegend[0] = "Legend";
        certData = new CyberCertData[](1);
        certData[0] = CyberCertData({
            name: "Equity",
            symbol: "EQ",
            uri: "ipfs://eq",
            securityClass: SecurityClass.CommonStock,
            securitySeries: SecuritySeries.NA,
            extension: address(0),
            seriesData: bytes(""),
            defaultLegend: defaultLegend
        });

        string[] memory roundPartyValues = new string[](2);
        roundPartyValues[0] = "Alice Officer";
        roundPartyValues[1] = "CEO";

        (bytes memory escrowedSig, ) = CyberCorpHelper.computeEscrowSignature(
            roundManager,
            SecuritySeries.SeriesSeed,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            roundType,
            block.timestamp,
            block.timestamp + ROUND_DURATION,
            CyberCorpHelper.TEMPLATE_ID,
            address(paymentToken),
            PRICE_PER_UNIT,
            valuation,
            corpOwnerPrivKey,
            corp
        );

        draft = RoundLib.draft()
            .setTickets(
                SecuritySeries.SeriesSeed,
                roundType,
                false,
                false,
                false,
                RAISE_CAP,
                MIN_TICKET,
                MAX_TICKET,
                address(paymentToken),
                PRICE_PER_UNIT,
                valuation,
                block.timestamp,
                block.timestamp + ROUND_DURATION
            )
            .setAgreement(
                CyberCorpHelper.TEMPLATE_ID,
                corpOwner,
                "Officer",
                "CEO",
                new string[](certData.length),
                roundPartyValues,
                new bytes[](certData.length),
                new address[](0),
                escrowedSig
            );
    }

    function _createMinimumRound(uint256 minRaise) internal returns (bytes32) {
        (Round memory draft, CyberCertData[] memory certData) = _draft(RoundType.FounderApproved, VALUATION);
        vm.prank(corpOwner);
        return RoundManager(roundManager).createRoundWithMinimum(
            draft, certData, minRaise, block.timestamp + ROUND_DURATION + DEADLINE_SLACK
        );
    }

    function _createPlainRound(uint256 valuation) internal returns (bytes32) {
        (Round memory draft, CyberCertData[] memory certData) = _draft(RoundType.FounderApproved, valuation);
        vm.prank(corpOwner);
        return RoundManager(roundManager).createRound(draft, certData);
    }

    /// @dev Builds the draft first: an external call between `vm.expectRevert` and the target
    /// would consume the expectation.
    function _expectCreateRevert(RoundType roundType, uint256 minRaise, uint256 deadline, bytes4 selector) internal {
        (Round memory draft, CyberCertData[] memory certData) = _draft(roundType, VALUATION);
        vm.prank(corpOwner);
        vm.expectRevert(selector);
        RoundManager(roundManager).createRoundWithMinimum(draft, certData, minRaise, deadline);
    }

    function _submitEOI(bytes32 roundId, uint256 investorIndex) internal returns (bytes32 agreementId) {
        return _submitEOIAs(
            roundId, investors[investorIndex], investorKeys[investorIndex], investorIndex + 1, MIN_TICKET, MAX_TICKET
        );
    }

    function _submitEOIAs(
        bytes32 roundId,
        address investor,
        uint256 investorKey,
        uint256 salt,
        uint256 minAmount,
        uint256 maxAmount
    ) internal returns (bytes32 agreementId) {
        EOI memory eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: minAmount,
            maxAmount: maxAmount,
            expiry: 0,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        bytes memory sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            salt,
            new string[](1),
            new string[](2),
            corpOwner,
            investorKey,
            roundManager,
            eoi.expiry,
            bytes32(0)
        );

        vm.prank(investor);
        (agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId, eoi, new string[](1), new string[](2), sig, salt, new address[](0), bytes32(0)
        );
    }

    /// @dev Commits `ids` at `amounts` as the company owner.
    function _commit(bytes32[] memory ids, uint256[] memory amounts) internal {
        vm.prank(corpOwner);
        RoundManager(roundManager).setCommitments(ids, amounts);
    }

    /// @dev Marks the minimum met as the company owner, listing `ids` in ascending order.
    function _markMet(bytes32 roundId, bytes32[] memory ids) internal {
        vm.prank(corpOwner);
        RoundManager(roundManager).markMinimumMet(roundId, _sorted(ids));
    }

    function _sorted(bytes32[] memory ids) internal pure returns (bytes32[] memory out) {
        out = new bytes32[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            bytes32 value = ids[i];
            uint256 j = i;
            while (j > 0 && out[j - 1] > value) {
                out[j] = out[j - 1];
                j--;
            }
            out[j] = value;
        }
    }

    function _one(bytes32 id) internal pure returns (bytes32[] memory ids) {
        ids = new bytes32[](1);
        ids[0] = id;
    }

    function _oneAmount(uint256 amount) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = amount;
    }

    function _batch(bytes32 first, bytes32 second, uint256 firstAmount, uint256 secondAmount)
        internal
        pure
        returns (bytes32[] memory ids, uint256[] memory amounts)
    {
        ids = new bytes32[](2);
        ids[0] = first;
        ids[1] = second;
        amounts = new uint256[](2);
        amounts[0] = firstAmount;
        amounts[1] = secondAmount;
    }

    function _assertPaid(bytes32 agreementId) internal view {
        Escrow memory escrow = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escrow.status), uint256(EscrowStatus.PAID), "escrow should still be paid");
        assertEq(escrow.corpAssets.length, 0, "nothing should be allocated");
    }

    function _assertAllocated(bytes32 agreementId) internal view {
        Escrow memory escrow = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escrow.status), uint256(EscrowStatus.FINALIZED), "escrow should be finalized");
        assertTrue(registry.isFinalized(agreementId), "agreement should be finalized");
    }
}

/// @notice Minimum raise (DEPLOY_VERSION 5.1): commit, then settle.
/// @dev Invariants pinned here:
///   I1. On a round whose minimum is unmet, nothing is allocated and no funds move.
///   I2. The minimum is met only while the round is open, when every committed escrow can still
///       settle (open for at least SETTLE_WINDOW) and the commitments add up to the minimum.
///   I3. After the minimum is met, commitments are locked: the owner cannot change, reject or
///       directly allocate them, and an investor can recall only once the escrow has expired.
///       Anyone can settle them, each at its committed amount, in any number of transactions.
///   I4. Below the minimum, every payment stays refundable in full (`reject`, `recallEOI`).
///   I5. While the minimum is unmet, the end time cannot move past the deadline.
///   I6. A round created without a minimum behaves exactly as before.
contract RoundManagerMinimumRaiseTest is MinimumRaiseFixture {
    using RoundLib for Round;

    event AllocationCommitted(bytes32 indexed agreementId, bytes32 indexed roundId, uint256 amount, uint256 committedTotal);
    event AllocationUncommitted(bytes32 indexed agreementId, bytes32 indexed roundId, uint256 amount, uint256 committedTotal);

    function setUp() public {
        _deployFixture(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                 creation
    //////////////////////////////////////////////////////////////*/

    function test_Version() public view {
        assertEq(RoundManager(roundManager).DEPLOY_VERSION(), "5.1");
        assertEq(RoundManager(roundManager).SETTLE_WINDOW(), 2 days);
    }

    function test_Create_StoresMinimumAndEmits() public {
        uint256 deadline = block.timestamp + ROUND_DURATION + DEADLINE_SLACK;
        (Round memory draft, CyberCertData[] memory certData) = _draft(RoundType.FounderApproved, VALUATION);

        vm.expectEmit(false, false, false, true, roundManager);
        emit RoundMinimumSet(bytes32(0), MIN_RAISE, deadline);
        vm.prank(corpOwner);
        bytes32 roundId = RoundManager(roundManager).createRoundWithMinimum(draft, certData, MIN_RAISE, deadline);

        (uint256 minRaise, uint256 storedDeadline, bool met, uint256 raised, uint256 committed) =
            RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(minRaise, MIN_RAISE);
        assertEq(storedDeadline, deadline);
        assertFalse(met);
        assertEq(raised, 0);
        assertEq(committed, 0);
    }

    function test_Create_RefusesFcfs() public {
        _expectCreateRevert(RoundType.FCFS, MIN_RAISE, block.timestamp + ROUND_DURATION, RoundManager.InvalidMinimum.selector);
    }

    function test_Create_RefusesZeroMinimum() public {
        _expectCreateRevert(RoundType.FounderApproved, 0, block.timestamp + ROUND_DURATION, RoundManager.InvalidMinimum.selector);
    }

    function test_Create_RefusesMinimumAboveCap() public {
        _expectCreateRevert(
            RoundType.FounderApproved, RAISE_CAP + 1, block.timestamp + ROUND_DURATION, RoundManager.InvalidMinimum.selector
        );
    }

    function test_Create_RefusesDeadlineBeforeEnd() public {
        _expectCreateRevert(
            RoundType.FounderApproved, MIN_RAISE, block.timestamp + ROUND_DURATION - 1, RoundManager.InvalidMinimum.selector
        );
    }

    /// @notice The minimum variants keep the existing signature check (MTLX1-26 response).
    function test_Create_KeepsEscrowedSignatureCheck() public {
        (Round memory draft, CyberCertData[] memory certData) = _draft(RoundType.FounderApproved, VALUATION);
        draft.raiseCap = RAISE_CAP - 1; // signed fields no longer match

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.InvalidEscrowedSignature.selector);
        RoundManager(roundManager).createRoundWithMinimum(draft, certData, MIN_RAISE, block.timestamp + ROUND_DURATION);
    }

    function test_Create_OnlyOwner() public {
        (Round memory draft, CyberCertData[] memory certData) = _draft(RoundType.FounderApproved, VALUATION);

        vm.prank(investors[0]);
        vm.expectRevert();
        RoundManager(roundManager).createRoundWithMinimum(draft, certData, MIN_RAISE, block.timestamp + ROUND_DURATION);
    }

    function test_CreateWithPrinters_StoresMinimum() public {
        bytes32 firstRound = _createPlainRound(VALUATION);
        address[] memory printers = RoundManager(roundManager).getRound(firstRound).certPrinter;

        (Round memory draft, ) = _draft(RoundType.FounderApproved, VALUATION * 2);
        draft.legalDetails = new string[](printers.length);
        draft.extensionData = new bytes[](printers.length);
        uint256 deadline = block.timestamp + ROUND_DURATION;

        vm.prank(corpOwner);
        bytes32 roundId =
            RoundManager(roundManager).createRoundWithPrintersAndMinimum(draft, printers, MIN_RAISE, deadline);

        (uint256 minRaise, uint256 storedDeadline, bool met, , ) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(minRaise, MIN_RAISE);
        assertEq(storedDeadline, deadline);
        assertFalse(met);
    }

    /*//////////////////////////////////////////////////////////////
                         before the minimum is met
    //////////////////////////////////////////////////////////////*/

    function test_Allocate_RevertsWhileMinimumPending() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.MinimumNotMet.selector);
        RoundManager(roundManager).allocate(a0, MAX_TICKET);
    }

    function test_AllocateBatch_RevertsWhileMinimumPending() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);

        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.MinimumNotMet.selector);
        RoundManager(roundManager).allocateBatch(ids, amounts);
    }

    /// @notice I1: committing records amounts and moves no funds.
    function test_Commit_RecordsWithoutMovingFunds() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        uint256 managerBalance = paymentToken.balanceOf(roundManager);

        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MIN_TICKET);
        vm.expectEmit(true, true, false, true, roundManager);
        emit AllocationCommitted(a0, roundId, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);

        assertEq(RoundManager(roundManager).getCommittedAmount(a0), MAX_TICKET);
        assertEq(RoundManager(roundManager).getCommittedAmount(a1), MIN_TICKET);
        (, , bool met, uint256 raised, uint256 committed) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertFalse(met);
        assertEq(raised, 0);
        assertEq(committed, MAX_TICKET + MIN_TICKET);
        assertEq(paymentToken.balanceOf(roundManager), managerBalance, "no funds move on commit");
        _assertPaid(a0);
        _assertPaid(a1);
    }

    function test_Commit_ReducesAmountToPayment() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);

        _commit(_one(a0), _oneAmount(MAX_TICKET * 5));

        assertEq(RoundManager(roundManager).getCommittedAmount(a0), MAX_TICKET);
    }

    function test_Commit_ReplaceAndRemove() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);

        _commit(_one(a0), _oneAmount(MAX_TICKET));
        _commit(_one(a0), _oneAmount(MIN_TICKET));
        (, , , , uint256 committed) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(committed, MIN_TICKET, "replacement adjusts the total");

        vm.expectEmit(true, true, false, true, roundManager);
        emit AllocationUncommitted(a0, roundId, MIN_TICKET, 0);
        _commit(_one(a0), _oneAmount(0));
        assertEq(RoundManager(roundManager).getCommittedAmount(a0), 0);

        vm.prank(corpOwner);
        vm.expectRevert(abi.encodeWithSelector(RoundManager.NotCommitted.selector, a0));
        RoundManager(roundManager).setCommitments(_one(a0), _oneAmount(0));
    }

    function test_Commit_Refusals() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 plainRound = _createPlainRound(VALUATION * 3);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 p1 = _submitEOI(plainRound, 1);

        vm.prank(investors[0]);
        vm.expectRevert();
        RoundManager(roundManager).setCommitments(_one(a0), _oneAmount(MAX_TICKET));

        vm.startPrank(corpOwner);
        vm.expectRevert(RoundManager.InvalidMinimum.selector);
        RoundManager(roundManager).setCommitments(_one(p1), _oneAmount(MAX_TICKET));

        vm.expectRevert(RoundManager.InvalidAllocation.selector);
        RoundManager(roundManager).setCommitments(_one(a0), _oneAmount(MIN_TICKET - 1));

        (bytes32[] memory mixed, uint256[] memory amounts) = _batch(a0, p1, MAX_TICKET, MAX_TICKET);
        vm.expectRevert(abi.encodeWithSelector(RoundManager.AgreementNotInRound.selector, p1));
        RoundManager(roundManager).setCommitments(mixed, amounts);

        vm.expectRevert(RoundManager.ArrayLengthMismatch.selector);
        RoundManager(roundManager).setCommitments(_one(a0), new uint256[](0));
        vm.stopPrank();
    }

    /// @notice A commitment needs at least SETTLE_WINDOW before its escrow expires.
    function test_Commit_RefusesInsideSettleWindow() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);

        vm.warp(block.timestamp + ROUND_DURATION - 1 days);
        vm.prank(corpOwner);
        vm.expectRevert(abi.encodeWithSelector(RoundManager.SettleWindowTooShort.selector, a0));
        RoundManager(roundManager).setCommitments(_one(a0), _oneAmount(MAX_TICKET));
    }

    function test_Commit_RefusesAfterEnd() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.RoundNotOpen.selector);
        RoundManager(roundManager).setCommitments(_one(a0), _oneAmount(MAX_TICKET));
    }

    function test_Settle_RevertsBeforeMet() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        _commit(_one(a0), _oneAmount(MAX_TICKET));

        vm.expectRevert(RoundManager.MinimumNotMet.selector);
        RoundManager(roundManager).settle(_one(a0));
    }

    /*//////////////////////////////////////////////////////////////
                              marking it met
    //////////////////////////////////////////////////////////////*/

    function test_MarkMet_RefusesBelowMinimum() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        _commit(_one(a0), _oneAmount(MAX_TICKET));

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.MinimumNotMet.selector);
        RoundManager(roundManager).markMinimumMet(roundId, _one(a0));
    }

    /// @notice I2: the list must be complete, ascending and without duplicates.
    function test_MarkMet_RequiresCompleteAscendingList() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        bytes32 a2 = _submitEOI(roundId, 2);
        bytes32[] memory three = new bytes32[](3);
        three[0] = a0;
        three[1] = a1;
        three[2] = a2;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = MAX_TICKET;
        amounts[1] = MAX_TICKET;
        amounts[2] = MIN_TICKET;
        _commit(three, amounts);

        bytes32[] memory sorted = _sorted(three);

        bytes32[] memory missing = new bytes32[](2);
        missing[0] = sorted[0];
        missing[1] = sorted[1];
        vm.startPrank(corpOwner);
        vm.expectRevert(RoundManager.CommitmentListInvalid.selector);
        RoundManager(roundManager).markMinimumMet(roundId, missing);

        bytes32[] memory descending = new bytes32[](3);
        descending[0] = sorted[2];
        descending[1] = sorted[1];
        descending[2] = sorted[0];
        vm.expectRevert(RoundManager.CommitmentListInvalid.selector);
        RoundManager(roundManager).markMinimumMet(roundId, descending);

        bytes32[] memory duplicate = new bytes32[](3);
        duplicate[0] = sorted[0];
        duplicate[1] = sorted[0];
        duplicate[2] = sorted[1];
        vm.expectRevert(RoundManager.CommitmentListInvalid.selector);
        RoundManager(roundManager).markMinimumMet(roundId, duplicate);

        RoundManager(roundManager).markMinimumMet(roundId, sorted);
        vm.stopPrank();
        (, , bool met, , ) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertTrue(met);
    }

    /// @notice I2: refused when a committed escrow could no longer settle in time.
    function test_MarkMet_RefusesInsideSettleWindow() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);

        vm.warp(block.timestamp + ROUND_DURATION - 1 days);
        bytes32[] memory sorted = _sorted(ids);
        vm.prank(corpOwner);
        vm.expectRevert(abi.encodeWithSelector(RoundManager.SettleWindowTooShort.selector, sorted[0]));
        RoundManager(roundManager).markMinimumMet(roundId, sorted);
    }

    function test_MarkMet_OnlyOwner() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);

        bytes32[] memory sorted = _sorted(ids);
        vm.prank(investors[0]);
        vm.expectRevert();
        RoundManager(roundManager).markMinimumMet(roundId, sorted);
    }

    /*//////////////////////////////////////////////////////////////
                         after the minimum is met
    //////////////////////////////////////////////////////////////*/

    /// @notice I3: anyone settles; each EOI is allocated at its committed amount.
    function test_Settle_AnyoneAfterMet() public {
        (bytes32 roundId, bytes32 a0, bytes32 a1) = _metRound();

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        RoundManager(roundManager).settle(_one(a0));
        vm.prank(investors[2]);
        RoundManager(roundManager).settle(_one(a1));

        _assertAllocated(a0);
        _assertAllocated(a1);
        (, , bool met, uint256 raised, uint256 committed) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertTrue(met);
        assertEq(raised, MIN_RAISE);
        assertEq(committed, 0);

        vm.expectRevert(abi.encodeWithSelector(RoundManager.NotCommitted.selector, a0));
        RoundManager(roundManager).settle(_one(a0));
    }

    /// @notice I3: commitments are locked once the minimum is met.
    function test_AfterMet_CommitmentsLocked() public {
        (bytes32 roundId, bytes32 a0, ) = _metRound();
        bytes32 a2 = _submitEOI(roundId, 2);

        vm.startPrank(corpOwner);
        vm.expectRevert(RoundManager.MinimumAlreadyMet.selector);
        RoundManager(roundManager).setCommitments(_one(a0), _oneAmount(0));

        vm.expectRevert(RoundManager.MinimumAlreadyMet.selector);
        RoundManager(roundManager).setCommitments(_one(a2), _oneAmount(MAX_TICKET));

        vm.expectRevert(abi.encodeWithSelector(RoundManager.CommitmentLocked.selector, a0));
        RoundManager(roundManager).reject(a0);

        vm.expectRevert(abi.encodeWithSelector(RoundManager.CommitmentLocked.selector, a0));
        RoundManager(roundManager).allocate(a0, MIN_TICKET);
        vm.stopPrank();
    }

    /// @notice After the minimum is met, EOIs that were not committed use the ordinary path.
    function test_AfterMet_UncommittedEoiAllocates() public {
        (bytes32 roundId, , ) = _metRound();
        bytes32 a2 = _submitEOI(roundId, 2);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(a2, MAX_TICKET);

        _assertAllocated(a2);
    }

    /// @notice I3: a committed EOI settles up to its expiry; the investor can recall only after.
    function test_AfterMet_RecallOnlyAfterEscrowExpiry() public {
        (, bytes32 a0, bytes32 a1) = _metRound();
        uint256 expiry = RoundManager(roundManager).getEscrowDetails(a0).expiry;

        vm.warp(expiry);
        vm.prank(investors[0]);
        vm.expectRevert(abi.encodeWithSelector(RoundManager.CommitmentLocked.selector, a0));
        RoundManager(roundManager).recallEOI(a0);

        RoundManager(roundManager).settle(_one(a1));
        _assertAllocated(a1);

        vm.warp(expiry + 1);
        uint256 before0 = paymentToken.balanceOf(investors[0]);
        vm.prank(investors[0]);
        RoundManager(roundManager).recallEOI(a0);
        assertEq(paymentToken.balanceOf(investors[0]), before0 + MAX_TICKET);
    }

    /// @notice I3 at scale: many commitments over several transactions, then separate settlements.
    function test_ManyCommitments_SettleAcrossTransactions() public {
        uint256 count = 40;
        bytes32 roundId = _createMinimumRound(count * MIN_TICKET);

        bytes32[] memory ids = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            (address investor, uint256 key) = makeAddrAndKey(string.concat("many", vm.toString(i)));
            paymentToken.transfer(investor, MIN_TICKET);
            vm.prank(investor);
            paymentToken.approve(roundManager, MIN_TICKET);
            ids[i] = _submitEOIAs(roundId, investor, key, 100 + i, MIN_TICKET, MIN_TICKET);
        }

        uint256 half = count / 2;
        bytes32[] memory first = new bytes32[](half);
        bytes32[] memory second = new bytes32[](count - half);
        uint256[] memory firstAmounts = new uint256[](half);
        uint256[] memory secondAmounts = new uint256[](count - half);
        for (uint256 i = 0; i < count; i++) {
            if (i < half) {
                first[i] = ids[i];
                firstAmounts[i] = MIN_TICKET;
            } else {
                second[i - half] = ids[i];
                secondAmounts[i - half] = MIN_TICKET;
            }
        }
        _commit(first, firstAmounts);
        _commit(second, secondAmounts);
        _markMet(roundId, ids);

        uint256 group = 10;
        for (uint256 start = 0; start < count; start += group) {
            bytes32[] memory part = new bytes32[](group);
            for (uint256 j = 0; j < group; j++) part[j] = ids[start + j];
            RoundManager(roundManager).settle(part);
        }

        for (uint256 i = 0; i < count; i++) _assertAllocated(ids[i]);
        (, , , uint256 raised, uint256 committed) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(raised, count * MIN_TICKET);
        assertEq(committed, 0);
    }

    /*//////////////////////////////////////////////////////////////
                       unmet minimum, deadline, refunds
    //////////////////////////////////////////////////////////////*/

    /// @notice I4: after the end time below the minimum, nothing can be met or allocated and
    /// recall refunds in full, clearing the commitment.
    function test_PastEnd_Unmet_RecallRefundsAndClears() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        bytes32[] memory sorted = _sorted(ids);
        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.RoundNotOpen.selector);
        RoundManager(roundManager).markMinimumMet(roundId, sorted);

        uint256 before0 = paymentToken.balanceOf(investors[0]);
        vm.prank(investors[0]);
        RoundManager(roundManager).recallEOI(a0);
        assertEq(paymentToken.balanceOf(investors[0]), before0 + MAX_TICKET);
        assertEq(RoundManager(roundManager).getCommittedAmount(a0), 0);
        (, , , , uint256 committed) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(committed, MAX_TICKET);
    }

    /// @notice An early close before the minimum is met aborts the round.
    function test_CloseRoundNow_AbortsPendingMinimum() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);

        vm.prank(corpOwner);
        RoundManager(roundManager).closeRoundNow(roundId);
        vm.warp(block.timestamp + 1);

        bytes32[] memory sorted = _sorted(ids);
        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.RoundNotOpen.selector);
        RoundManager(roundManager).markMinimumMet(roundId, sorted);

        uint256 before1 = paymentToken.balanceOf(investors[1]);
        vm.prank(investors[1]);
        RoundManager(roundManager).recallEOI(a1);
        assertEq(paymentToken.balanceOf(investors[1]), before1 + MAX_TICKET);
    }

    /// @notice I4: the founder can refund a committed EOI while the minimum is pending.
    function test_Reject_WhilePending_RefundsAndClears() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        bytes32 a0 = _submitEOI(roundId, 0);
        _commit(_one(a0), _oneAmount(MAX_TICKET));

        uint256 before0 = paymentToken.balanceOf(investors[0]);
        vm.prank(corpOwner);
        RoundManager(roundManager).reject(a0);

        assertEq(paymentToken.balanceOf(investors[0]), before0 + MAX_TICKET);
        assertEq(RoundManager(roundManager).getCommittedAmount(a0), 0);
        (, , , , uint256 committed) = RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(committed, 0);
    }

    /// @notice I5: the end time cannot pass the deadline while the minimum is unmet.
    function test_SetEndTime_DeadlineBindsOnlyWhilePending() public {
        bytes32 roundId = _createMinimumRound(MIN_RAISE);
        (, uint256 deadline, , , ) = RoundManager(roundManager).getRoundMinimum(roundId);

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.EndTimeAfterMinimumDeadline.selector);
        RoundManager(roundManager).setRoundEndTime(roundId, deadline + 1);

        vm.prank(corpOwner);
        RoundManager(roundManager).setRoundEndTime(roundId, deadline);
        assertEq(RoundManager(roundManager).getRound(roundId).endTime, deadline);

        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);
        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);
        _markMet(roundId, ids);

        vm.prank(corpOwner);
        RoundManager(roundManager).setRoundEndTime(roundId, deadline + 1);
        assertEq(RoundManager(roundManager).getRound(roundId).endTime, deadline + 1);
    }

    /*//////////////////////////////////////////////////////////////
                    rounds without a minimum, batch inputs
    //////////////////////////////////////////////////////////////*/

    /// @notice I6: a round without a minimum allocates one EOI at a time as before.
    function test_NoMinimum_AllocateUnchanged() public {
        bytes32 roundId = _createPlainRound(VALUATION);
        bytes32 a0 = _submitEOI(roundId, 0);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(a0, MAX_TICKET);

        _assertAllocated(a0);
        (uint256 minRaise, uint256 deadline, bool met, uint256 raised, uint256 committed) =
            RoundManager(roundManager).getRoundMinimum(roundId);
        assertEq(minRaise, 0);
        assertEq(deadline, 0);
        assertFalse(met);
        assertEq(raised, MAX_TICKET);
        assertEq(committed, 0);
    }

    /// @notice I6: on a round without a minimum, `allocateBatch` is a plain batch and the end
    /// time has no deadline.
    function test_NoMinimum_BatchIsPlainAndEndTimeFree() public {
        bytes32 roundId = _createPlainRound(VALUATION);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);

        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MIN_TICKET);
        vm.prank(corpOwner);
        RoundManager(roundManager).allocateBatch(ids, amounts);

        _assertAllocated(a0);
        _assertAllocated(a1);

        vm.prank(corpOwner);
        RoundManager(roundManager).setRoundEndTime(roundId, block.timestamp + 365 days);
    }

    /// @notice One failing allocation reverts the whole batch (MTLX1-17 / MTLX1-21: the app must
    /// leave out EOIs that do not simulate).
    function test_Batch_OneFailingAllocation_RevertsAll() public {
        bytes32 roundId = _createPlainRound(VALUATION);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);

        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MIN_TICKET - 1);
        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.InvalidAllocation.selector);
        RoundManager(roundManager).allocateBatch(ids, amounts);

        _assertPaid(a0);
        _assertPaid(a1);
    }

    function test_Batch_RefusesMixedRounds() public {
        bytes32 roundA = _createPlainRound(VALUATION);
        bytes32 roundB = _createPlainRound(VALUATION * 3);
        bytes32 a0 = _submitEOI(roundA, 0);
        bytes32 b1 = _submitEOI(roundB, 1);

        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, b1, MAX_TICKET, MAX_TICKET);
        vm.prank(corpOwner);
        vm.expectRevert(abi.encodeWithSelector(RoundManager.AgreementNotInRound.selector, b1));
        RoundManager(roundManager).allocateBatch(ids, amounts);
    }

    function test_Batch_RefusesLengthMismatchAndEmpty() public {
        bytes32[] memory ids = new bytes32[](1);
        uint256[] memory amounts = new uint256[](2);

        vm.startPrank(corpOwner);
        vm.expectRevert(RoundManager.ArrayLengthMismatch.selector);
        RoundManager(roundManager).allocateBatch(ids, amounts);

        vm.expectRevert(RoundManager.ArrayLengthMismatch.selector);
        RoundManager(roundManager).allocateBatch(new bytes32[](0), new uint256[](0));
        vm.stopPrank();
    }

    function test_Batch_OnlyOwner() public {
        bytes32 roundId = _createPlainRound(VALUATION);
        bytes32 a0 = _submitEOI(roundId, 0);
        bytes32 a1 = _submitEOI(roundId, 1);

        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        vm.prank(investors[0]);
        vm.expectRevert();
        RoundManager(roundManager).allocateBatch(ids, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                                 helpers
    //////////////////////////////////////////////////////////////*/

    /// @dev A minimum round with two EOIs committed at the maximum ticket and the minimum met.
    function _metRound() internal returns (bytes32 roundId, bytes32 a0, bytes32 a1) {
        roundId = _createMinimumRound(MIN_RAISE);
        a0 = _submitEOI(roundId, 0);
        a1 = _submitEOI(roundId, 1);
        (bytes32[] memory ids, uint256[] memory amounts) = _batch(a0, a1, MAX_TICKET, MAX_TICKET);
        _commit(ids, amounts);
        _markMet(roundId, ids);
    }
}

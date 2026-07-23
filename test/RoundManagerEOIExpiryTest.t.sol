// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CyberCorpHelper, MockPaymentToken} from "./RoundManagerTest.t.sol";
import {SecuritySeries, SecurityClass} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundType} from "../src/libs/RoundLib.sol";
import {CyberCertData, EOI} from "../src/storage/RoundManagerStorage.sol";
import {Escrow, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";

/// @notice Scenario matrix for `eoi.expiry` against the `allowTimedOffers` flag.
/// @dev Pins the invariant from `specs/analysis/roundManager EOI expiry — scenario matrix.md`:
/// with `allowTimedOffers == false` the investor's stated expiry must have no observable effect
/// on any state transition, so `round.endTime` is the only deadline in play. The flag-on tests
/// are the no-regression column — there the expiry is binding and must stay binding.
///
/// Expiry classes, all describing `eoi.expiry` while the round is still open:
///   F — future at submit, still future when the founder allocates
///   E — future at submit, elapsed by the time the founder allocates
///   P — already in the past at submit (non-zero)
///   Z — zero, the natural way to express "no deadline"
///
/// allowTimedOffers = false — expiry ignored, `round.endTime` is the only deadline
///
/// | Class | submitEOI | allocate | recallEOI       | unilateral void | test                                            |
/// |-------|-----------|----------|-----------------|-----------------|-------------------------------------------------|
/// | F     | ok        | succeeds | `EOINotExpired` | blocked         | FlagOff_FutureExpiry_Allocates                  |
/// | E     | ok        | succeeds | `EOINotExpired` | blocked         | FlagOff_ElapsedExpiry_Allocates                 |
/// |       |           |          | `EOINotExpired` |                 | FlagOff_ElapsedExpiry_RecallBlockedWhileOpen    |
/// |       |           |          |                 | blocked         | FlagOff_ElapsedExpiry_UnilateralVoidBlocked     |
/// | P     | ok        | succeeds |                 |                 | FlagOff_StaleExpiry_SubmitsAndAllocates         |
/// | Z     | ok        | succeeds | `EOINotExpired` | blocked         | FlagOff_ZeroExpiry_Allocates                    |
/// |       |           |          | `EOINotExpired` |                 | FlagOff_ZeroExpiry_RecallBlockedWhileOpen       |
/// |       |           |          |                 | blocked         | FlagOff_ZeroExpiry_UnilateralVoidBlocked        |
///
/// Past `round.endTime` the escrow deadline governs, identically for every class:
///   allocate `EOIExpired` + recall refunds  → FlagOff_PastRoundEnd_AllocateBlocked_RecallRefunds
///   unilateral void allowed                 → FlagOff_PastRoundEnd_UnilateralVoidAllowed
/// `reject` refunds at any time, no expiry dependency → FlagOff_ElapsedExpiry_RejectRefunds
///
/// allowTimedOffers = true — deadline is binding (reference column, must not regress)
///
/// | Class | submitEOI    | allocate     | recallEOI       | unilateral void | test                                        |
/// |-------|--------------|--------------|-----------------|-----------------|---------------------------------------------|
/// | F     | ok           | succeeds     | `EOINotExpired` | blocked         | FlagOn_LiveExpiry_Allocates                 |
/// |       |              |              | `EOINotExpired` |                 | FlagOn_LiveExpiry_RecallBlocked             |
/// |       |              |              |                 | blocked         | FlagOn_LiveExpiry_UnilateralVoidBlocked     |
/// | E     | ok           | `EOIExpired` | refunds         | allowed         | FlagOn_ElapsedExpiry_AllocateBlocked_RecallRefunds |
/// |       |              |              |                 | allowed         | FlagOn_ElapsedExpiry_UnilateralVoidAllowed  |
/// | P     | `EOIExpired` | —            | —               | —               | FlagOn_StaleExpiry_SubmitReverts            |
/// | Z     | `EOIExpired` | —            | —               | —               | FlagOn_ZeroExpiry_SubmitReverts             |
contract RoundManagerEOIExpiryTest is Test {
    MockPaymentToken private paymentToken;
    CyberAgreementRegistry private registry;
    CyberCorpFactory private corpFactory;

    address private corp;
    address private roundManager;
    address private rmFactory;

    address private owner;
    uint256 private ownerPrivKey;
    address private corpOwner;
    uint256 private corpOwnerPrivKey;
    address private investor;
    uint256 private investorPrivKey;

    string[] private roundPartyValues;

    uint256 private constant MIN_TICKET = 1000 * 10 ** 6;
    uint256 private constant MAX_TICKET = 100000 * 10 ** 6;
    uint256 private constant RAISE_CAP = 1000000 * 10 ** 6;
    uint256 private constant PRICE_PER_UNIT = 10 * 10 ** 18;
    uint256 private constant VALUATION = 10000000 * 10 ** 18;

    uint256 private constant ROUND_DURATION = 30 days;

    function setUp() public {
        roundPartyValues = new string[](2);
        roundPartyValues[0] = "Officer";
        roundPartyValues[1] = "CEO";

        (owner, ownerPrivKey) = makeAddrAndKey("owner");
        (corpOwner, corpOwnerPrivKey) = makeAddrAndKey("corpOwner");
        (investor, investorPrivKey) = makeAddrAndKey("investor");

        paymentToken = new MockPaymentToken();

        address issuanceManagerFactory;
        address cyberCorpSingleFactory;
        address dealManagerFactory;
        address uriBuilder;
        address helper;
        (
            registry,
            corpFactory,
            issuanceManagerFactory,
            cyberCorpSingleFactory,
            dealManagerFactory,
            rmFactory,
            uriBuilder,
            helper
        ) = CyberCorpHelper.deployRegistryAndFactories(owner);

        vm.startPrank(owner);
        CyberCorpHelper.createTemplate(registry);
        RoundManagerFactory(rmFactory).setPlatformPayable(owner);
        RoundManagerFactory(rmFactory).setDefaultFeeRatio(25);
        vm.stopPrank();

        (corp, , , , roundManager) = CyberCorpHelper.deployCorp(
            corpFactory,
            "Test Corp",
            corpOwner,
            corpOwner
        );

        paymentToken.transfer(investor, 1000000 * 10 ** 6);
        vm.prank(investor);
        paymentToken.approve(roundManager, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                    allowTimedOffers = false — expiry ignored
    //////////////////////////////////////////////////////////////*/

    /// @notice Class Z: expiry == 0 is the natural way to say "no deadline"; allocation must work.
    function test_FlagOff_ZeroExpiry_Allocates() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, 0);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        _assertAllocated(agreementId);
    }

    /// @notice Class E: the stated expiry elapses while the round is still open.
    /// @dev This is the case that distinguishes the two layers — with only the `allocate`
    /// duplicate removed it still fails, deeper, on `finalizeContract`'s `ContractExpired`.
    function test_FlagOff_ElapsedExpiry_Allocates() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        _assertAllocated(agreementId);
    }

    /// @notice Class F: a live expiry behaves the same as every other class when the flag is off.
    function test_FlagOff_FutureExpiry_Allocates() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 7 days);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        _assertAllocated(agreementId);
    }

    /// @notice Class P: a stale non-zero expiry is admitted by the submit gate, so the whole
    /// submit path must accept it — not revert `ContractExpired` further down — and still allocate.
    function test_FlagOff_StaleExpiry_SubmitsAndAllocates() public {
        bytes32 roundId = _createRound(false);

        vm.warp(block.timestamp + 1 days);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp - 1 hours);

        Escrow memory escrow = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escrow.status), uint256(EscrowStatus.PAID));

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        _assertAllocated(agreementId);
    }

    /// @notice Recall stays shut until the round ends, whatever the stated expiry was.
    function test_FlagOff_ZeroExpiry_RecallBlockedWhileOpen() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, 0);

        vm.prank(investor);
        vm.expectRevert(RoundManager.EOINotExpired.selector);
        RoundManager(roundManager).recallEOI(agreementId);
    }

    function test_FlagOff_ElapsedExpiry_RecallBlockedWhileOpen() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(investor);
        vm.expectRevert(RoundManager.EOINotExpired.selector);
        RoundManager(roundManager).recallEOI(agreementId);
    }

    /// @notice A zero expiry must not let one party void the agreement alone.
    function test_FlagOff_ZeroExpiry_UnilateralVoidBlocked() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, 0);

        _requestVoid(agreementId);

        assertFalse(registry.isVoided(agreementId), "one party must not void alone");

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        _assertAllocated(agreementId);
    }

    /// @notice Same for an elapsed expiry — the round, not the EOI, decides.
    function test_FlagOff_ElapsedExpiry_UnilateralVoidBlocked() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 2 hours);
        _requestVoid(agreementId);

        assertFalse(registry.isVoided(agreementId), "one party must not void alone");

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        _assertAllocated(agreementId);
    }

    /// @notice Past `endTime` the escrow deadline governs: allocation closes and recall opens.
    function test_FlagOff_PastRoundEnd_AllocateBlocked_RecallRefunds() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, 0);

        uint256 balanceBefore = paymentToken.balanceOf(investor);
        vm.warp(block.timestamp + ROUND_DURATION + 1);

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.EOIExpired.selector);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        vm.prank(investor);
        RoundManager(roundManager).recallEOI(agreementId);

        assertEq(paymentToken.balanceOf(investor), balanceBefore + MAX_TICKET);
    }

    /// @notice Unilateral void unlocks at the same instant recall does.
    function test_FlagOff_PastRoundEnd_UnilateralVoidAllowed() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, 0);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        _requestVoid(agreementId);

        assertTrue(registry.isVoided(agreementId), "void should be allowed once the round has ended");
    }

    /// @notice `reject` has no expiry dependency: the founder can always release the funds.
    function test_FlagOff_ElapsedExpiry_RejectRefunds() public {
        bytes32 roundId = _createRound(false);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 1 hours);

        uint256 balanceBefore = paymentToken.balanceOf(investor);
        vm.warp(block.timestamp + 2 hours);

        vm.prank(corpOwner);
        RoundManager(roundManager).reject(agreementId);

        Escrow memory escrow = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escrow.status), uint256(EscrowStatus.VOIDED));
        assertEq(paymentToken.balanceOf(investor), balanceBefore + MAX_TICKET);
    }

    /*//////////////////////////////////////////////////////////////
                allowTimedOffers = true — expiry stays binding
    //////////////////////////////////////////////////////////////*/

    /// @notice No-regression: with the flag on, an elapsed expiry still stops allocation and
    /// releases the funds in the same instant.
    function test_FlagOn_ElapsedExpiry_AllocateBlocked_RecallRefunds() public {
        bytes32 roundId = _createRound(true);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 1 hours);

        uint256 balanceBefore = paymentToken.balanceOf(investor);
        vm.warp(block.timestamp + 2 hours);

        vm.prank(corpOwner);
        vm.expectRevert(RoundManager.EOIExpired.selector);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        vm.prank(investor);
        RoundManager(roundManager).recallEOI(agreementId);

        assertEq(paymentToken.balanceOf(investor), balanceBefore + MAX_TICKET);
    }

    /// @notice No-regression: with the flag on, a live expiry allocates normally.
    function test_FlagOn_LiveExpiry_Allocates() public {
        bytes32 roundId = _createRound(true);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 7 days);

        vm.prank(corpOwner);
        RoundManager(roundManager).allocate(agreementId, MAX_TICKET);

        _assertAllocated(agreementId);
    }

    /// @notice A live offer cannot be recalled — the investor is committed until it expires.
    function test_FlagOn_LiveExpiry_RecallBlocked() public {
        bytes32 roundId = _createRound(true);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 7 days);

        vm.prank(investor);
        vm.expectRevert(RoundManager.EOINotExpired.selector);
        RoundManager(roundManager).recallEOI(agreementId);
    }

    /// @notice Nor unilaterally voided while it is still live.
    function test_FlagOn_LiveExpiry_UnilateralVoidBlocked() public {
        bytes32 roundId = _createRound(true);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 7 days);

        _requestVoid(agreementId);

        assertFalse(registry.isVoided(agreementId), "one party must not void a live offer alone");
    }

    /// @notice Once the binding deadline passes, walking away alone is the intended behaviour.
    function test_FlagOn_ElapsedExpiry_UnilateralVoidAllowed() public {
        bytes32 roundId = _createRound(true);
        bytes32 agreementId = _submitEOI(roundId, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 2 hours);
        _requestVoid(agreementId);

        assertTrue(registry.isVoided(agreementId), "expired offer should be voidable");
    }

    /// @notice Class P: with the flag on, a stale expiry is rejected at the submit gate.
    function test_FlagOn_StaleExpiry_SubmitReverts() public {
        bytes32 roundId = _createRound(true);

        vm.warp(block.timestamp + 1 days);
        _expectSubmitRevert(roundId, block.timestamp - 1 hours);
    }

    /// @notice Class Z: with the flag on, a missing expiry is rejected at the submit gate.
    function test_FlagOn_ZeroExpiry_SubmitReverts() public {
        bytes32 roundId = _createRound(true);
        _expectSubmitRevert(roundId, 0);
    }

    /*//////////////////////////////////////////////////////////////
                                 helpers
    //////////////////////////////////////////////////////////////*/

    function _createRound(bool allowTimedOffers) private returns (bytes32) {
        vm.prank(corpOwner);
        return CyberCorpHelper.createRound(
            RoundManager(roundManager),
            address(paymentToken),
            CyberCorpHelper.TEMPLATE_ID,
            RAISE_CAP,
            MIN_TICKET,
            MAX_TICKET,
            PRICE_PER_UNIT,
            VALUATION,
            RoundType.FounderApproved,
            corpOwnerPrivKey,
            corp,
            false,
            allowTimedOffers
        );
    }

    uint256 private constant SALT = 1;

    function _prepareEOI(uint256 expiry) private view returns (EOI memory eoi, bytes memory sig) {
        eoi = EOI({
            name: "Test Investor",
            investorType: "Individual",
            jurisdiction: "US",
            contact: "test@example.com",
            minAmount: MIN_TICKET,
            maxAmount: MAX_TICKET,
            expiry: expiry,
            naturalPerson: false,
            lexchexDetails: CyberCorpHelper.emptyLex()
        });

        sig = CyberCorpHelper.computeEOISignature(
            registry,
            CyberCorpHelper.TEMPLATE_ID,
            SALT,
            new string[](1),
            new string[](2),
            corpOwner,
            investorPrivKey,
            roundManager,
            eoi.expiry,
            bytes32(0)
        );
    }

    function _submitEOI(bytes32 roundId, uint256 expiry) private returns (bytes32 agreementId) {
        (EOI memory eoi, bytes memory sig) = _prepareEOI(expiry);

        vm.prank(investor);
        (agreementId, ) = RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            sig,
            SALT,
            new address[](0),
            bytes32(0)
        );
    }

    /// @dev The EOI and its signature are built first: any external call between
    /// `vm.expectRevert` and the target would consume the expectation.
    function _expectSubmitRevert(bytes32 roundId, uint256 expiry) private {
        (EOI memory eoi, bytes memory sig) = _prepareEOI(expiry);

        vm.prank(investor);
        vm.expectRevert(RoundManager.EOIExpired.selector);
        RoundManager(roundManager).submitEOI(
            roundId,
            eoi,
            new string[](1),
            new string[](2),
            sig,
            SALT,
            new address[](0),
            bytes32(0)
        );
    }

    /// @dev The investor asks to void on their own; whether that is enough to void the
    /// agreement is what each caller asserts.
    function _requestVoid(bytes32 agreementId) private {
        bytes32 structHash = keccak256(
            abi.encode(registry.VOIDSIGNATUREDATA_TYPEHASH(), agreementId, investor)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", registry.DOMAIN_SEPARATOR(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(investorPrivKey, digest);

        vm.prank(investor);
        registry.voidContractFor(agreementId, investor, abi.encodePacked(r, s, v));
    }

    function _assertAllocated(bytes32 agreementId) private view {
        Escrow memory escrow = RoundManager(roundManager).getEscrowDetails(agreementId);
        assertEq(uint256(escrow.status), uint256(EscrowStatus.FINALIZED), "escrow should be finalized");
        assertTrue(registry.isFinalized(agreementId), "agreement should be finalized");
    }
}

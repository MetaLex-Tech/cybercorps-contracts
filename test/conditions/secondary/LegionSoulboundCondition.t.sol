// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Credential} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {IDealManager} from "../../../src/interfaces/IDealManager.sol";
import {ILexChexBadge, K_ACCREDITED, K_DATA, K_SYNDICATE} from "../../../src/interfaces/ILexChexBadge.sol";
import {BadgeScopedCondition} from "../../../src/libs/conditions/secondary/BadgeScopedCondition.sol";
import {
    LegionSoulboundCondition,
    LegionTier
} from "../../../src/libs/conditions/secondary/LegionSoulboundCondition.sol";
import {SecondaryConditionIntegrationBase} from "./SecondaryConditionIntegration.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Legion's circle gate — "a MEMBER or better in Legion's circle, for this SPV".
//
// Supersedes the old circle gate (LexChexBadgeKindCondition + K_SYNDICATE), which answered the seat but not
// the rank. A qualifying credential now carries both: K_SYNDICATE scoped to this SPV, and K_DATA holding the
// rank. Membership alone is just the lowest rung.
//
// Two things a plain fact-key gate cannot do:
//  - Issuer keys: Legion may assert K_SYNDICATE | K_DATA and nothing else. The gate names Legion, so only
//    its circle counts.
//  - Value-key resolution: a rank is a value, not a flag, so two of them contradict. getMostRecentValidWith
//    picks the holder's current seat and the rank on THAT one is compared to the bar, so a demotion counts
//    even when the old seat was never voided.
//
// Real integration: parties come from a real posted/accepted sell offer. Config is MEMBER, buyer-only,
// issuer filter = Legion, unless a row says otherwise.
//
// Rank ladder — higher up the ladder is what "clears" means. A rank is a value, so the NEWEST seat answers.
// | # | applyToSeller | context      | buyer rank | seller rank | expect | rationale                       |
// |---|:-------------:|--------------|:----------:|:-----------:|:------:|---------------------------------|
// | 1 |      no       | SELL posting |    n/a     |    none     |  pass  | buyer unknown, seller ungated   |
// | 2 |      no       | accepted     |   MEMBER   |    none     |  pass  | buyer is exactly at the bar     |
// | 3 |      no       | accepted     |    LEAD    |    none     |  pass  | higher up the ladder clears it  |
// | 4 |      no       | accepted     |  PROSPECT  |    none     |  fail  | seated, but below the bar       |
// | 5 |      no       | accepted     |    none    |   MEMBER    |  fail  | buyer holds no seat at all      |
// | 6 |     yes       | accepted     |   MEMBER   |  PROSPECT   |  fail  | seller gated too, and is below  |
// | 7 |     yes       | accepted     |   MEMBER   |   MEMBER    |  pass  | both at the bar                 |
// | 8 |     yes       | SELL posting |    n/a     |  PROSPECT   |  fail  | seller gated even at posting    |
//
// Seat and rank — one record must carry both; neither half answers alone. (Merged from the circle gate.)
// | #  | case                                    | expect                                                   |
// |----|-----------------------------------------|----------------------------------------------------------|
// | 9  | lowest rung configured                  | pass for any seat — the old circle gate, as a config      |
// | 10 | seat with no rank (K_SYNDICATE only)    | fail — nothing says how far along the holder is           |
// | 11 | rank with no seat (K_DATA only)         | fail — a rank in no circle is not a seat in this one      |
// | 12 | bare seat + bare rank held together     | fail — the two do not add up into a qualifying credential |
// | 13 | rank bytes present but K_DATA unasserted | fail — `asserts` is the authority, not a populated field  |
//
// Issuer authority — who may seat and rank, and whose circle the gate believes.
// | #  | case                                    | expect                                                   |
// |----|-----------------------------------------|----------------------------------------------------------|
// | 14 | issuer holds no grant                   | mint reverts KeysNotAuthorized — cannot seat anyone       |
// | 15 | Legion asserts a key outside its grant  | mint reverts KeysNotAuthorized — seat and rank only       |
// | 16 | rival issuer's MEMBER seat, same SPV    | fail — the filter is what makes it Legion's circle        |
// | 17 | no issuer filter, rival's MEMBER seat   | pass — an empty filter means "anyone's circle"            |
//
// Scope, payload and lifecycle — what the badge's filters and the rank check throw out.
// | #  | case                                    | expect                                                   |
// |----|-----------------------------------------|----------------------------------------------------------|
// | 18 | MEMBER seat in a different SPV          | fail — a seat answers for the SPV it names                |
// | 19 | seat with no scope                      | mint reverts MissingScope — the badge will not issue it   |
// | 20 | rank payload not 32 bytes               | fail closed — an unreadable rank is no rank                |
// | 21 | rank decodes past the ladder's end      | fail closed — unknown rung is not a high rung             |
// | 22 | SPV never configured                    | fail closed, whatever the party holds                      |
// | 23 | newest seat unreadable                  | fail — no falling back to an older readable one            |
// | 24 | promotion via supersede                 | pass — PROSPECT replaced by MEMBER                         |
// | 25 | newer, lower rank minted                | fail — newest wins, so demoting needs no void              |
// | 26 | newer, higher rank minted               | pass — same rule the other way                             |
// | 27 | seat expired                            | fail — the badge filters on validity before recency        |
//
// Configuration — the SPV names its bar; the platform names whose circle is read.
// | #  | case                                    | expect                                                   |
// |----|-----------------------------------------|----------------------------------------------------------|
// | 28 | setConfig by a stranger                 | revert — SPV's own BorgAuth admin only                    |
// | 29 | setConfig with NONE                     | revert InvalidTier — that is the unconfigured value       |
// | 30 | setConfig for the zero SPV              | revert InvalidSpv                                         |
// | 31 | updateIssuers by a stranger             | revert — platform-set, not SPV-set                        |
// | 32 | initialize zero default badge           | revert InvalidBadge                                       |
// ─────────────────────────────────────────────────────────────────────────────

contract LegionSoulboundConditionTest is SecondaryConditionIntegrationBase {
    LegionSoulboundCondition internal legion;

    // Two operators on the one badge, each able to seat and rank, neither holding a BorgAuth role.
    address internal legionIssuer = makeAddr("legion.issuer");
    address internal rivalIssuer = makeAddr("rival.issuer");
    address internal ungrantedIssuer = makeAddr("ungranted.issuer");

    uint256 internal constant SEAT_AND_RANK = K_SYNDICATE | K_DATA;

    function setUp() public {
        _setUpIntegration();
        badge.setIssuerKeys(legionIssuer, SEAT_AND_RANK);
        badge.setIssuerKeys(rivalIssuer, SEAT_AND_RANK);
        legion = _deploy();
        legion.updateIssuers(_only(legionIssuer));
        _configure(LegionTier.MEMBER, false);
    }

    function _deploy() internal returns (LegionSoulboundCondition c) {
        c = LegionSoulboundCondition(
            _proxy(
                address(new LegionSoulboundCondition()),
                abi.encodeCall(LegionSoulboundCondition.initialize, (address(auth), address(badge)))
            )
        );
    }

    /// @dev The test contract is the SPV's own BorgAuth admin, so this runs unpranked.
    function _configure(LegionTier minTier, bool applyToSeller) internal {
        legion.setConfig(address(corp), minTier, applyToSeller);
    }

    /// @dev A seat in `issuer`'s circle for `spv`, at rung `tier`.
    function _grantTierFor(address issuer, address who, address spv, LegionTier tier) internal returns (uint256) {
        return _grantDataFor(issuer, who, spv, legion.encodeTier(tier));
    }

    /// @dev Same, with the rank written by hand, so a test can mint one the gate cannot read.
    function _grantDataFor(address issuer, address who, address spv, bytes memory data) internal returns (uint256) {
        Credential memory c = _tierCred(spv, data);
        vm.prank(issuer);
        return badge.mint(who, c);
    }

    /// @dev A ranked seat: both keys on one record, which is what the gate asks for.
    function _tierCred(address spv, bytes memory data) internal view returns (Credential memory c) {
        c.asserts = SEAT_AND_RANK;
        c.scope = spv;
        c.data = data;
        c.expiryDate = uint64(block.timestamp + 3650 days);
    }

    /// @dev Mints only part of what the gate asks for, to show halves do not qualify.
    function _grantPartial(address who, uint256 asserts, address spv, bytes memory data)
        internal
        returns (uint256)
    {
        Credential memory c = _tierCred(spv, data);
        c.asserts = asserts;
        vm.prank(legionIssuer);
        return badge.mint(who, c);
    }

    function _grant(address who, LegionTier tier) internal returns (uint256) {
        return _grantTierFor(legionIssuer, who, address(corp), tier);
    }

    function _only(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function _check(bytes32 offerId, bytes32 agreementId) internal view returns (bool) {
        return legion.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, agreementId);
    }

    // ── Rank ladder ──────────────────────────────────────────────────────────

    // 1
    function test_BuyerOnly_Posting_SellerUngated_Passes() public {
        assertTrue(_check(_postSell(), bytes32(0)));
    }

    // 2
    function test_BuyerAtRequiredTier_Passes() public {
        _grant(buyer, LegionTier.MEMBER);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));
    }

    // 3 — why the rank is a value and not a key: a bitmask cannot say "MEMBER or better".
    function test_BuyerAboveRequiredTier_Passes() public {
        _grant(buyer, LegionTier.LEAD);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));
    }

    // 4
    function test_BuyerBelowRequiredTier_Fails() public {
        _grant(buyer, LegionTier.PROSPECT);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 5
    function test_BuyerHoldsNoSeat_Fails() public {
        _grant(seller, LegionTier.MEMBER);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 6
    function test_ApplyToSeller_SellerBelowTier_Fails() public {
        _configure(LegionTier.MEMBER, true);
        _grant(buyer, LegionTier.MEMBER);
        _grant(seller, LegionTier.PROSPECT);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 7
    function test_ApplyToSeller_BothAtTier_Passes() public {
        _configure(LegionTier.MEMBER, true);
        _grant(buyer, LegionTier.MEMBER);
        _grant(seller, LegionTier.MEMBER);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));
    }

    // 8
    function test_ApplyToSeller_Posting_SellerBelowTier_Fails() public {
        _configure(LegionTier.MEMBER, true);
        _grant(seller, LegionTier.PROSPECT);
        assertFalse(_check(_postSell(), bytes32(0)));
    }

    // ── Seat and rank (merged from the circle gate) ──────────────────────────

    // 9 — the old circle gate, as a config: name the lowest rung and any seat clears.
    function test_LowestRungConfigured_AnySeatAdmits() public {
        _configure(LegionTier.PROSPECT, false);
        _grant(buyer, LegionTier.PROSPECT);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));
    }

    // 10 — a seat with no rank clears no bar, not even the lowest. So Legion ranks every seat.
    function test_SeatWithoutRank_DoesNotAdmit() public {
        _configure(LegionTier.PROSPECT, false);
        _grantPartial(buyer, K_SYNDICATE, address(corp), "");
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 11 — a rank with no seat is a rank in no circle.
    function test_RankWithoutSeat_DoesNotAdmit() public {
        _grantPartial(buyer, K_DATA, address(corp), legion.encodeTier(LegionTier.LEAD));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 12 — the key set is tested per credential, so the halves never add up to a qualifying one.
    function test_BareSeatPlusBareRank_DoNotCombine() public {
        _grantPartial(buyer, K_SYNDICATE, address(corp), "");
        _grantPartial(buyer, K_DATA, address(corp), legion.encodeTier(LegionTier.LEAD));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 13 — `asserts` is the authority: a full `data` field no key claims is not a rank.
    function test_RankBytesWithoutTheKey_DoNotAdmit() public {
        _grantPartial(buyer, K_SYNDICATE, address(corp), legion.encodeTier(LegionTier.LEAD));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // ── Issuer authority ─────────────────────────────────────────────────────

    // 14 — the grant IS the authority to issue, so an ungranted operator cannot seat anyone.
    function test_UngrantedIssuer_CannotMintSeat() public {
        Credential memory c = _tierCred(address(corp), legion.encodeTier(LegionTier.MEMBER));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, ungrantedIssuer, SEAT_AND_RANK
            )
        );
        vm.prank(ungrantedIssuer);
        badge.mint(buyer, c);
    }

    // 15 — running a circle does not let Legion call anyone accredited.
    function test_LegionIssuer_CannotAssertKeysOutsideItsGrant() public {
        Credential memory c = _tierCred(address(corp), legion.encodeTier(LegionTier.MEMBER));
        c.asserts = SEAT_AND_RANK | K_ACCREDITED;
        vm.expectRevert(
            abi.encodeWithSelector(ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, legionIssuer, K_ACCREDITED)
        );
        vm.prank(legionIssuer);
        badge.mint(buyer, c);
    }

    // 16 — a rival can seat this buyer high in its own circle; the gate reads Legion.
    function test_RivalIssuersTier_DoesNotAdmit() public {
        _grantTierFor(rivalIssuer, buyer, address(corp), LegionTier.LEAD);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 17 — with no issuer named the gate takes any operator's word for where the buyer sits.
    function test_NoIssuerFilter_AnyIssuersTierAdmits() public {
        legion.updateIssuers(new address[](0));
        _grantTierFor(rivalIssuer, buyer, address(corp), LegionTier.MEMBER);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));
    }

    // ── Scope, payload, lifecycle ────────────────────────────────────────────

    // 18
    function test_SeatInAnotherSpv_DoesNotAdmit() public {
        _grantTierFor(legionIssuer, buyer, makeAddr("otherSpv"), LegionTier.LEAD);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 19 — a seat needs an SPV, so an unscoped one fails at issuance, not at the gate.
    function test_UnscopedSeat_CannotBeMinted() public {
        Credential memory c = _tierCred(address(0), legion.encodeTier(LegionTier.LEAD));
        vm.expectRevert(ILexChexBadge.LexChexBadge_MissingScope.selector);
        vm.prank(legionIssuer);
        badge.mint(buyer, c);
    }

    // 20 — a payload the gate cannot parse is no rank at all.
    function test_MalformedPayload_FailsClosed() public {
        _grantDataFor(legionIssuer, buyer, address(corp), bytes("LEAD"));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 21
    function test_TierPastEndOfLadder_FailsClosed() public {
        _grantDataFor(legionIssuer, buyer, address(corp), abi.encode(uint256(99)));
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));
    }

    // 22 — never configured blocks, whatever the party holds.
    function test_UnconfiguredSpv_FailsClosed() public {
        LegionSoulboundCondition fresh = _deploy();
        _grant(buyer, LegionTier.LEAD);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();

        assertFalse(fresh.checkCondition(IDealManager(address(dm)), bytes4(0), offerId, settlementId));
    }

    // 23 — an unreadable newest seat blocks; it does not hand the answer back to an older readable one.
    function test_UnreadableNewestSeat_DoesNotFallBack() public {
        _grant(buyer, LegionTier.MEMBER);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));

        vm.warp(block.timestamp + 1 days);
        _grantDataFor(legionIssuer, buyer, address(corp), bytes("LEAD"));
        assertFalse(_check(offerId, settlementId));
    }

    // 24 — promotion. Credentials are immutable, so moving up means replacing the old one.
    function test_PromotionBySupersede_Passes() public {
        uint256 staleId = _grant(buyer, LegionTier.PROSPECT);
        Credential memory promoted = _tierCred(address(corp), legion.encodeTier(LegionTier.MEMBER));
        vm.prank(legionIssuer);
        badge.supersede(staleId, promoted, "promoted to member");

        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));
    }

    // 25 — two ranks contradict, so the newest wins. Demoting is a mint; no void needed.
    function test_NewestRankWins_DemotionTakesEffectAtOnce() public {
        _grant(buyer, LegionTier.MEMBER);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));

        vm.warp(block.timestamp + 1 days);
        _grant(buyer, LegionTier.PROSPECT);
        assertFalse(_check(offerId, settlementId), "the newer, lower rank is the one that counts");
    }

    // 26 — and the same the other way: a newer higher rank lifts the holder without voiding the old one.
    function test_NewestRankWins_PromotionWithoutVoiding() public {
        _grant(buyer, LegionTier.PROSPECT);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertFalse(_check(offerId, settlementId));

        vm.warp(block.timestamp + 1 days);
        _grant(buyer, LegionTier.MEMBER);
        assertTrue(_check(offerId, settlementId));
    }

    // 27 — the badge drops expired seats before picking the newest.
    function test_ExpiredTier_Fails() public {
        _grant(buyer, LegionTier.LEAD);
        (bytes32 offerId, bytes32 settlementId) = _postAndAcceptSell();
        assertTrue(_check(offerId, settlementId));

        vm.warp(block.timestamp + 3651 days);
        assertFalse(_check(offerId, settlementId));
    }

    // ── Configuration ────────────────────────────────────────────────────────

    // 28 — the bar is the SPV's to set, on its own BorgAuth.
    function test_SetConfig_ByStranger_Reverts() public {
        vm.prank(stranger);
        vm.expectRevert();
        legion.setConfig(address(corp), LegionTier.MEMBER, false);
    }

    // 29
    function test_SetConfig_NoneTier_Reverts() public {
        vm.expectRevert(LegionSoulboundCondition.InvalidTier.selector);
        legion.setConfig(address(corp), LegionTier.NONE, false);
    }

    // 30
    function test_SetConfig_ZeroSpv_Reverts() public {
        vm.expectRevert(LegionSoulboundCondition.InvalidSpv.selector);
        legion.setConfig(address(0), LegionTier.MEMBER, false);
    }

    // 31 — the platform picks whose circle is read; the SPV is the party being judged.
    function test_UpdateIssuers_ByStranger_Reverts() public {
        address[] memory list = _only(rivalIssuer);
        vm.prank(stranger);
        vm.expectRevert();
        legion.updateIssuers(list);
    }

    // 32
    function test_Initialize_ZeroBadge_Reverts() public {
        address impl = address(new LegionSoulboundCondition());
        bytes memory initData = abi.encodeCall(LegionSoulboundCondition.initialize, (address(auth), address(0)));
        vm.expectRevert(BadgeScopedCondition.InvalidBadge.selector);
        _proxy(impl, initData);
    }
}

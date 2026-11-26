// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {ICredentialQueryHook} from "../src/interfaces/ICredentialQueryHook.sol";
import {IERC5484} from "../src/interfaces/IERC5484.sol";
import {
    ILexChexBadge,
    InvestorType,
    K_ACCREDITED,
    K_BAD_ACTOR_CLEAR,
    K_BO_COUNT,
    K_DATA,
    K_INVESTOR_JURISDICTION,
    K_INVESTOR_TYPE,
    K_LOOKTHROUGH_JURISDICTION,
    K_NON_US,
    K_QIB,
    K_QP,
    K_SPV_WHITELIST,
    K_SYNDICATE,
    K_US_STATE,
    K_NATIONALITY_OUT,
    PRESET_ENTITY_LOOKTHROUGH,
    PRESET_KYC_AML
} from "../src/interfaces/ILexChexBadge.sol";
import {IAuthAdapter} from "../src/interfaces/IAuthAdapter.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Unit tests for the LeXcheXBadge credential reads — the credentialing layer every cyberTRADE
/// compliance condition and the offer-visibility UI read from.
///
/// Key invariants / assumptions this suite guards (legal / economic intent, not mechanics):
///  1. Validity is the master gate: a wallet is eligible only while it holds a credential that is issued,
///     unexpired, and not voided. Expiry forces re-attestation; a void locks the holder out at once.
///  2. Current standing governs, per fact: each read reflects the holder's most-recent valid credential that
///     ASSERTS that fact-key, so a superseding credential takes effect immediately and stale facts never win.
///  3. A credential answers a fact only if it asserts the key: a credential that does not assert a fact can
///     neither answer it nor shadow one that does (authority is the `asserts` bitmask, not the credential type).
///  4. Scoped entitlements (whitelist, syndicate) name a single SPV: membership never leaks to another SPV,
///     and admission to an SPV never stands in for a seat in its issuer's circle, or the reverse.
///  5. The two jurisdiction facts are stored and read independently — neither derives from nor shadows the other.
///  6. Credentials are IMMUTABLE: a fact is changed by minting a newer credential and revoked by voiding — never
///     edited in place, never burned. A voided/expired credential is retained on-chain for audit.
///  7. A value read for an unestablished fact returns the field's empty value. What that emptiness *means* is
///     each condition's decision, not the badge's.
///  8. Credentials are soulbound to the verified wallet: non-transferable, no delegation.
///  9. A reading carries its own horizon: `validUntil` reports when the credential answering a fact expires,
///     so a caller that caches an answer can tell when to stop trusting it. Expiry moves nothing on-chain,
///     so without this a cache has no way to learn the fact behind it lapsed.
///
/// What those facts mean for the §3(c)(1)(A) holder count is covered in LookThroughPolicy.t.sol.
contract LeXcheXBadgeTest is Test {
    // Local copies of the emitted events (the indexer surface asserted by the event tests).
    event CredentialIssued(address indexed owner, uint256 indexed tokenId, Credential cred);
    event CredentialVoided(address indexed owner, uint256 indexed tokenId, string reason);
    event CredentialSwept(address indexed owner, uint256 indexed tokenId);
    event Issued(address indexed from, address indexed to, uint256 indexed tokenId, IERC5484.BurnAuth burnAuth);

    // Legion's tier ids. Only the hook knows what these mean; the badge stores 32 opaque bytes.
    bytes32 constant TIER1 = keccak256("legion.tier.1");
    bytes32 constant TIER2 = keccak256("legion.tier.2");
    bytes32 constant TIER3 = keccak256("legion.tier.3");

    address owner;
    BorgAuth auth;
    LeXcheXBadge badge;
    TierQueryHook tierHook; // one deployment; every tier question is a payload (see _tierHook)

    function setUp() public {
        owner = makeAddr("owner");
        auth = new BorgAuth(owner);
        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth))))
            )
        );
    }

    // ── Baseline ────────────────────────────────────────────────────────────

    // A holder with one live credential: every read resolves to that credential's facts.
    function test_SingleCredential_AllReadsResolve() public {
        address holder = makeAddr("holder");
        Credential memory c =
            _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_US_STATE | K_BO_COUNT);
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = "US";
        c.lookThroughJurisdiction = "US";
        c.usState = "CA";
        c.beneficialOwnerCount = 4;
        _mint(holder, c);

        assertEq(uint256(_readInvestorType(holder)), uint256(InvestorType.ENTITY));
        assertEq(_readUsState(holder), bytes2("CA"));
        assertEq(uint256(_readBoCount(holder)), 4);
        assertEq(_readJurisdiction(holder), "US");
        assertEq(_readLookThrough(holder), "US");
    }

    // ── Recency & determinism ─────────────────────────────────────────────────

    // The most-recent (by issuanceDate) valid credential asserting a fact governs it: a newer credential
    // supersedes an older one.
    function test_Recency_NewerValidWins() public {
        address holder = makeAddr("recency");
        _mint(holder, _kyc("US", "NY")); // older
        vm.warp(block.timestamp + 30 days);
        _mint(holder, _kyc("US", "TX")); // newer
        assertEq(_readUsState(holder), bytes2("TX"));
    }

    // Ties on issuanceDate (same block) resolve deterministically to the higher tokenId.
    function test_Recency_TieBreaksOnHigherTokenId() public {
        address holder = makeAddr("tie");
        _mint(holder, _kyc("US", "NY")); // lower tokenId
        _mint(holder, _kyc("US", "TX")); // higher tokenId, same block

        uint256[] memory ids = badge.getTokenIdsByOwner(holder);
        assertGt(ids[1], ids[0]);
        assertEq(_readUsState(holder), bytes2("TX"));
    }

    // A newer credential that does NOT assert a fact cannot shadow an older one that does.
    function test_AssertsAuthority_NonAssertingDoesNotShadow() public {
        address feeder = makeAddr("shadow");
        Credential memory c = _cred(K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION);
        c.investorJurisdiction = "KY";
        c.lookThroughJurisdiction = "US";
        _mint(feeder, c); // older, asserts regulatory

        vm.warp(block.timestamp + 1 days);
        _mint(feeder, _jurisdiction("KY")); // newer, asserts jurisdiction only (not regulatory)

        assertEq(_readLookThrough(feeder), "US"); // preserved: newer didn't assert it
    }

    // Individual vs. entity resolves like any other value fact: UNSET when unestablished, superseded by a
    // newer asserting credential, never shadowed by a non-asserting one, and restored when the newer is voided.
    function test_GetInvestorType_ResolvesAndDefaultsUnset() public {
        address holder = makeAddr("investorType");
        assertEq(uint256(_readInvestorType(holder)), uint256(InvestorType.UNSET));

        Credential memory entity = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION);
        entity.investorType = InvestorType.ENTITY;
        entity.investorJurisdiction = "KY";
        _mint(holder, entity);
        assertEq(uint256(_readInvestorType(holder)), uint256(InvestorType.ENTITY));

        vm.warp(block.timestamp + 1 days);
        _mint(holder, _cred(K_ACCREDITED)); // newer, asserts no type
        assertEq(uint256(_readInvestorType(holder)), uint256(InvestorType.ENTITY));

        vm.warp(block.timestamp + 1 days);
        Credential memory individual = _cred(K_INVESTOR_TYPE);
        individual.investorType = InvestorType.INDIVIDUAL;
        uint256 reclassified = _mint(holder, individual); // newer, asserts the type
        assertEq(uint256(_readInvestorType(holder)), uint256(InvestorType.INDIVIDUAL));

        vm.prank(owner);
        badge.void(reclassified, "revoked");
        assertEq(uint256(_readInvestorType(holder)), uint256(InvestorType.ENTITY)); // older valid governs
    }

    // A newer credential that is merely silent on the look-through count cannot shadow an older one that
    // asserts it. Silence is not a retraction — supersede is (see the recert test below for contradiction).
    function test_AssertsAuthority_BoCountNotShadowed() public {
        address entity = makeAddr("entity");
        _mint(entity, _entityWithBoCount(5)); // older, asserts BO count

        vm.warp(block.timestamp + 1 days);
        Credential memory newer = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION);
        newer.investorType = InvestorType.ENTITY; // still an entity, just says nothing about the count
        newer.investorJurisdiction = "US";
        _mint(entity, newer);

        assertEq(uint256(_readBoCount(entity)), 5);
    }

    // An authoritative INDIVIDUAL is an established fact about beneficial ownership, not a silence: a natural
    // person is one owner. Without this the printer's look-through tally keeps the stale entity count until the
    // holder fully exits, since K_INVESTOR_TYPE is the only key the recert moves.
    function test_EffectiveBoCount_IndividualRecertReadsOne() public {
        address holder = makeAddr("recertified");
        uint256 asEntity = _mint(holder, _entityWithBoCount(5));
        assertEq(uint256(_readBoCount(holder)), 5);

        // Supersede voids the entity credential outright: nothing asserts K_BO_COUNT any more.
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        badge.supersede(asEntity, _kyc("US", "CA"), "recertified as individual");
        assertEq(uint256(_readBoCount(holder)), 1, "individual is one owner, not unknown");
    }

    // Same recert without voiding the old credential: it stays valid and still answers K_BO_COUNT, so the type
    // must be read first or the stale 5 wins.
    function test_EffectiveBoCount_IndividualOutranksUnvoidedEntityCount() public {
        address holder = makeAddr("bothValid");
        _mint(holder, _entityWithBoCount(5));

        vm.warp(block.timestamp + 1 days);
        _mint(holder, _kyc("US", "CA")); // newer, contradicts the entity classification

        assertEq(uint256(_readInvestorType(holder)), uint256(InvestorType.INDIVIDUAL));
        assertEq(uint256(_readBoCount(holder)), 1, "newer type governs the count");
    }

    // Nothing established stays 0 — the caller, not the badge, decides what an unknown count means.
    function test_EffectiveBoCount_UnestablishedStaysZero() public {
        address entityNoCount = makeAddr("entityNoCount");
        Credential memory c = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION);
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = "KY";
        _mint(entityNoCount, c);

        assertEq(uint256(_readBoCount(entityNoCount)), 0);
        assertEq(uint256(_readBoCount(makeAddr("noCreds"))), 0);
    }

    // ── Validity gating ───────────────────────────────────────────────────────

    // Expired credentials are excluded from selection even when they are the most recent.
    function test_ExpiredCredentialSkipped() public {
        address holder = makeAddr("expired");
        _mint(holder, _kyc("US", "CA")); // long-lived, state CA

        Credential memory shortLived = _kyc("US", "NY");
        shortLived.expiryDate = uint64(block.timestamp + 2 days);
        uint256 ny = _mint(holder, shortLived); // higher tokenId, state NY, expires at +2 days
        assertEq(_readUsState(holder), bytes2("NY")); // NY wins the tie while valid

        vm.warp(block.timestamp + 3 days); // NY expired, CA still valid
        assertFalse(badge.isValid(ny));
        assertEq(_readUsState(holder), bytes2("CA"));
    }

    // Voided credentials are excluded; an older valid credential legitimately governs again.
    function test_VoidedCredentialExcluded() public {
        address holder = makeAddr("voided");
        _mint(holder, _kyc("US", "CA")); // older, CA
        vm.warp(block.timestamp + 1 days);
        uint256 ny = _mint(holder, _kyc("US", "NY")); // newer, NY

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        badge.void(ny, "revoked");

        assertEq(_readUsState(holder), bytes2("CA"));
    }

    // ── Reading horizon: every getter reports when its answer lapses ───────────

    // The expiry belongs to the same credential that supplied the value, so a cache can watch it.
    function test_Horizon_MatchesAuthoritativeCredential() public {
        address holder = makeAddr("until");
        Credential memory c = _kyc("KY", bytes2("NY"));
        c.expiryDate = uint64(block.timestamp + 30 days);
        _mint(holder, c);

        (string memory jurisdiction, uint64 jurisdictionExpiry) = badge.getInvestorJurisdiction(holder);
        assertEq(jurisdiction, "KY");
        assertEq(uint256(jurisdictionExpiry), uint256(c.expiryDate));

        (bytes2 state, uint64 stateExpiry) = badge.getUsState(holder);
        assertEq(state, bytes2("NY"));
        assertEq(uint256(stateExpiry), uint256(c.expiryDate));
    }

    // Two facts from different credentials carry their own expiries, not a shared one.
    function test_Horizon_IsPerFactNotPerHolder() public {
        address holder = makeAddr("perFact");
        Credential memory kyc = _kyc("KY", bytes2(0));
        kyc.expiryDate = uint64(block.timestamp + 300 days);
        _mint(holder, kyc);

        Credential memory lookThrough = _cred(K_LOOKTHROUGH_JURISDICTION);
        lookThrough.expiryDate = uint64(block.timestamp + 30 days);
        lookThrough.lookThroughJurisdiction = "KY";
        _mint(holder, lookThrough);

        (, uint64 jurisdictionExpiry) = badge.getInvestorJurisdiction(holder);
        (, uint64 lookThroughExpiry) = badge.getLookThroughJurisdiction(holder);
        assertEq(uint256(jurisdictionExpiry), uint256(kyc.expiryDate));
        assertEq(uint256(lookThroughExpiry), uint256(lookThrough.expiryDate));
    }

    // Recency governs the expiry too: a newer credential's horizon wins even when it is shorter.
    function test_Horizon_FollowsRecencyNotLongestExpiry() public {
        address holder = makeAddr("untilRecency");
        Credential memory long_ = _kyc("KY", bytes2(0));
        long_.expiryDate = uint64(block.timestamp + 300 days);
        _mint(holder, long_);

        vm.warp(block.timestamp + 1 days);
        Credential memory short_ = _kyc("KY", bytes2(0));
        short_.expiryDate = uint64(block.timestamp + 5 days);
        _mint(holder, short_);

        (, uint64 expiry) = badge.getInvestorJurisdiction(holder);
        assertEq(uint256(expiry), uint256(short_.expiryDate));
    }

    // Once the newer one lapses the older one governs again, and the horizon moves with it.
    function test_Horizon_FallsBackWhenNewerLapses() public {
        address holder = makeAddr("untilFallback");
        Credential memory long_ = _kyc("KY", bytes2(0));
        long_.expiryDate = uint64(block.timestamp + 300 days);
        _mint(holder, long_);

        Credential memory short_ = _kyc("KY", bytes2(0));
        short_.expiryDate = uint64(block.timestamp + 5 days);
        _mint(holder, short_);

        vm.warp(block.timestamp + 6 days);
        (, uint64 expiry) = badge.getInvestorJurisdiction(holder);
        assertEq(uint256(expiry), uint256(long_.expiryDate));
    }

    // An INDIVIDUAL's count of 1 comes off the investor-type credential, so it carries that expiry.
    function test_Horizon_IndividualCountCarriesTypeExpiry() public {
        address holder = makeAddr("individualHorizon");
        Credential memory c = _kyc("US", bytes2(0));
        c.expiryDate = uint64(block.timestamp + 45 days);
        _mint(holder, c);

        (uint32 count, uint64 expiry) = badge.getEffectiveBeneficialOwnerCount(holder);
        assertEq(uint256(count), 1);
        assertEq(uint256(expiry), uint256(c.expiryDate));
    }

    // No credential answering the fact reads 0, matching the empty-value convention of the getters.
    function test_Horizon_UnansweredFactIsZero() public {
        (string memory jurisdiction, uint64 expiry) = badge.getInvestorJurisdiction(makeAddr("nobody"));
        assertEq(jurisdiction, "");
        assertEq(uint256(expiry), 0);
    }

    // A voided credential stops answering, so nothing is left to watch.
    function test_Horizon_VoidedIsZero() public {
        address holder = makeAddr("untilVoided");
        uint256 id = _mint(holder, _kyc("KY", bytes2(0)));

        vm.prank(owner);
        badge.void(id, "revoked");
        (, uint64 expiry) = badge.getInvestorJurisdiction(holder);
        assertEq(uint256(expiry), 0);
    }

    // ── Unknown reads as empty; the look-through is conservatively U.S. ────────────

    function test_NoCredential_ReturnsDefaults() public {
        address nobody = makeAddr("nobody");
        assertEq(uint256(_readInvestorType(nobody)), uint256(InvestorType.UNSET));
        assertEq(_readUsState(nobody), bytes2(0));
        assertEq(uint256(_readBoCount(nobody)), 0);
        assertEq(_readJurisdiction(nobody), "");
        assertEq(_readLookThrough(nobody), "");
    }

    // Immutability: a fact persists until the asserting credential is voided/expires. Minting a newer
    // non-U.S. jurisdiction changes the jurisdiction read, but the old U.S. state only clears when voided.
    function test_Relocation_StateClearsOnlyByVoid() public {
        address holder = makeAddr("relocate");
        uint256 nyId = _mint(holder, _kyc("US", "NY")); // U.S. resident, state NY
        vm.warp(block.timestamp + 1 days);
        _mint(holder, _jurisdiction("KY")); // relocates: newer jurisdiction, no state asserted

        assertEq(_readJurisdiction(holder), "KY");
        assertEq(_readUsState(holder), bytes2("NY")); // still NY: the newer cred didn't assert usState

        vm.prank(owner);
        badge.void(nyId, "relocated");
        assertEq(_readUsState(holder), bytes2(0)); // now cleared: no valid credential asserts usState
    }

    // ── Existence / entitlement reads ─────────────────────────────────────────

    // hasValidCredentialOf resolves a status fact-key: the asserted key admits, another is rejected.
    function test_HasValidCredentialOf_StatusKey() public {
        address holder = makeAddr("acc");
        _mint(holder, _cred(K_ACCREDITED));
        assertTrue(badge.hasValidCredentialOf(holder, K_ACCREDITED));
        assertFalse(badge.hasValidCredentialOf(holder, K_QP));
        assertFalse(badge.hasValidCredentialOf(makeAddr("nobody3"), K_ACCREDITED));
    }

    // Each status key resolves on its own, and a compound query is answered only by a SINGLE credential
    // asserting every requested bit — two single-key credentials never add up to a combined attestation.
    function test_HasValidCredentialOf_AllStatusKeysAndCompound() public {
        address holder = makeAddr("statuses");
        _mint(holder, _cred(K_QP));
        _mint(holder, _cred(K_QIB));
        _mint(holder, _cred(K_BAD_ACTOR_CLEAR));
        assertTrue(badge.hasValidCredentialOf(holder, K_QP));
        assertTrue(badge.hasValidCredentialOf(holder, K_QIB));
        assertTrue(badge.hasValidCredentialOf(holder, K_BAD_ACTOR_CLEAR));
        assertFalse(badge.hasValidCredentialOf(holder, K_ACCREDITED));
        // Both statuses are true of this holder, so both count — it does not matter that they were attested
        // separately. A key the holder has no credential for still fails the ask.
        assertTrue(badge.hasValidCredentialOf(holder, K_QP | K_QIB));
        assertFalse(badge.hasValidCredentialOf(holder, K_QP | K_ACCREDITED));

        address both = makeAddr("qpAndQib");
        _mint(both, _cred(K_QP | K_QIB));
        assertTrue(badge.hasValidCredentialOf(both, K_QP | K_QIB));

        // Seasoning does NOT assemble a combination the same way: no one credential carries both, so there is
        // no single date to report. See earliestValidIssuance.
        assertEq(uint256(badge.earliestValidIssuance(holder, K_QP | K_QIB)), 0);
        assertGt(uint256(badge.earliestValidIssuance(both, K_QP | K_QIB)), 0);
    }

    // A key of nothing with no hook and no issuer list filters nothing, so it would quietly mean "holds any
    // credential at all". That is hasValidLexCheX's job, and asking it this way is a wiring slip — rejected so
    // a blank parameterization cannot fail open.
    function test_HasValidCredentialOf_EmptyQueryIsRejected() public {
        address holder = makeAddr("emptyKey");
        _mint(holder, _cred(K_ACCREDITED));
        assertTrue(badge.hasValidLexCheX(holder)); // the holder does have an active badge

        vm.expectRevert(ILexChexBadge.LexChexBadge_EmptyQuery.selector);
        badge.hasValidCredentialOf(holder, 0);

        vm.expectRevert(ILexChexBadge.LexChexBadge_EmptyQuery.selector);
        badge.earliestValidIssuance(holder, 0);
    }

    // A status gate closes on expiry and on void, the same way a value fact does.
    function test_HasValidCredentialOf_DeniedWhenExpiredOrVoided() public {
        address expired = makeAddr("qpExpired");
        Credential memory shortLived = _cred(K_QP);
        shortLived.expiryDate = uint64(block.timestamp + 1 days);
        _mint(expired, shortLived);
        assertTrue(badge.hasValidCredentialOf(expired, K_QP));
        vm.warp(block.timestamp + 2 days);
        assertFalse(badge.hasValidCredentialOf(expired, K_QP)); // expired, before any sweep

        address voided = makeAddr("qpVoided");
        uint256 id = _mint(voided, _cred(K_QP));
        vm.prank(owner);
        badge.void(id, "revoked");
        assertFalse(badge.hasValidCredentialOf(voided, K_QP));
    }

    // ── Reg S non-U.S. person (K_NON_US) ──────────────────────────────────────
    //
    // | K_NON_US | hasValidCredentialOf |
    // |----------|----------------------|
    // | absent   | false                |
    // | asserted | true                 |

    // The attestation stands alone: it needs no jurisdiction payload, and it is never inferred from one.
    function test_NonUsPerson_AttestedAndNeverInferred() public {
        address attested = makeAddr("nonUsAttested");
        _mint(attested, _cred(K_NON_US));
        assertTrue(badge.hasValidCredentialOf(attested, K_NON_US));

        // A foreign jurisdiction alone does not attest the Reg S fact, and a U.S. one does not refute it.
        address ky = makeAddr("kyOnly");
        Credential memory c = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION);
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = "KY";
        _mint(ky, c);
        assertFalse(badge.hasValidCredentialOf(ky, K_NON_US));

        assertFalse(badge.hasValidCredentialOf(makeAddr("nobodyNonUs"), K_NON_US));
    }

    // The gate closes on expiry and on void, so a lapsed attestation cannot carry a Reg S trade.
    function test_NonUsPerson_DeniedWhenExpiredOrVoided() public {
        address expired = makeAddr("nonUsExpired");
        Credential memory shortLived = _cred(K_NON_US);
        shortLived.expiryDate = uint64(block.timestamp + 1 days);
        _mint(expired, shortLived);
        assertTrue(badge.hasValidCredentialOf(expired, K_NON_US));
        vm.warp(block.timestamp + 2 days);
        assertFalse(badge.hasValidCredentialOf(expired, K_NON_US));

        address voided = makeAddr("nonUsVoided");
        uint256 id = _mint(voided, _cred(K_NON_US));
        vm.prank(owner);
        badge.void(id, "reclassified as U.S. person");
        assertFalse(badge.hasValidCredentialOf(voided, K_NON_US));
    }

    // hasValidWhitelistFor is scoped to a specific SPV and to the holder it was issued to.
    function test_HasValidWhitelistFor_ScopedToSPV() public {
        address spvA = makeAddr("spvA");
        address spvB = makeAddr("spvB");
        address holder = makeAddr("wl");
        Credential memory c = _cred(K_SPV_WHITELIST);
        c.scope = spvA;
        _mint(holder, c);
        assertTrue(badge.hasValidWhitelistFor(holder, spvA));
        assertFalse(badge.hasValidWhitelistFor(holder, spvB)); // scope-specific
        assertFalse(badge.hasValidWhitelistFor(makeAddr("wl2"), spvA)); // holder-specific
    }

    // A whitelist entitlement closes on void and on expiry.
    function test_HasValidWhitelistFor_DeniedWhenExpiredOrVoided() public {
        address spv = makeAddr("spvVE");
        Credential memory c = _cred(K_SPV_WHITELIST);
        c.scope = spv;

        address voided = makeAddr("wlVoid");
        uint256 id = _mint(voided, c);
        vm.prank(owner);
        badge.void(id, "revoked");
        assertFalse(badge.hasValidWhitelistFor(voided, spv));

        address expiring = makeAddr("wlExpire");
        Credential memory shortLived = _cred(K_SPV_WHITELIST);
        shortLived.scope = spv;
        shortLived.expiryDate = uint64(block.timestamp + 1 days);
        _mint(expiring, shortLived);
        assertTrue(badge.hasValidWhitelistFor(expiring, spv));
        vm.warp(block.timestamp + 2 days);
        assertFalse(badge.hasValidWhitelistFor(expiring, spv)); // expired, before any sweep
    }

    // A non-whitelist credential never grants an SPV whitelist entitlement.
    function test_HasValidWhitelistFor_IgnoresNonWhitelist() public {
        address holder = makeAddr("kycOnly");
        _mint(holder, _kyc("US", "CA"));
        assertFalse(badge.hasValidWhitelistFor(holder, makeAddr("spvA")));
    }

    // A syndicate seat reads exactly like a whitelist entitlement: scoped to one SPV and to its holder.
    function test_HasValidSyndicateFor_ScopedToSPV() public {
        address spvA = makeAddr("synSpvA");
        address spvB = makeAddr("synSpvB");
        address holder = makeAddr("syn");
        Credential memory c = _cred(K_SYNDICATE);
        c.scope = spvA;
        _mint(holder, c);
        assertTrue(badge.hasValidSyndicateFor(holder, spvA));
        assertFalse(badge.hasValidSyndicateFor(holder, spvB)); // scope-specific
        assertFalse(badge.hasValidSyndicateFor(makeAddr("syn2"), spvA)); // holder-specific
    }

    // The point of splitting the two: admission to an SPV is not a seat in its issuer's circle, and a seat
    // is not admission. Each grant has to be issued on its own.
    function test_ScopedKeys_WhitelistAndSyndicateNeverSubstitute() public {
        address spv = makeAddr("spvBoth");
        address listed = makeAddr("listedOnly");
        Credential memory wl = _cred(K_SPV_WHITELIST);
        wl.scope = spv;
        _mint(listed, wl);
        assertTrue(badge.hasValidWhitelistFor(listed, spv));
        assertFalse(badge.hasValidSyndicateFor(listed, spv));

        address seated = makeAddr("seatedOnly");
        Credential memory syn = _cred(K_SYNDICATE);
        syn.scope = spv;
        _mint(seated, syn);
        assertTrue(badge.hasValidSyndicateFor(seated, spv));
        assertFalse(badge.hasValidWhitelistFor(seated, spv));

        // One credential may carry both grants for the same SPV.
        address full = makeAddr("listedAndSeated");
        Credential memory both = _cred(K_SPV_WHITELIST | K_SYNDICATE);
        both.scope = spv;
        _mint(full, both);
        assertTrue(badge.hasValidWhitelistFor(full, spv));
        assertTrue(badge.hasValidSyndicateFor(full, spv));
    }

    // A seat closes on void and on expiry, like every other entitlement.
    function test_HasValidSyndicateFor_DeniedWhenExpiredOrVoided() public {
        address spv = makeAddr("synSpvVE");

        address voided = makeAddr("synVoid");
        Credential memory c = _cred(K_SYNDICATE);
        c.scope = spv;
        uint256 id = _mint(voided, c);
        vm.prank(owner);
        badge.void(id, "left the circle");
        assertFalse(badge.hasValidSyndicateFor(voided, spv));

        address expiring = makeAddr("synExpire");
        Credential memory shortLived = _cred(K_SYNDICATE);
        shortLived.scope = spv;
        shortLived.expiryDate = uint64(block.timestamp + 1 days);
        _mint(expiring, shortLived);
        assertTrue(badge.hasValidSyndicateFor(expiring, spv));
        vm.warp(block.timestamp + 2 days);
        assertFalse(badge.hasValidSyndicateFor(expiring, spv)); // expired, before any sweep
    }

    // K_DATA: a generic programmable bytes payload, resolved most-recent-valid like any value fact.
    function test_Data_ProgrammablePayload() public {
        address holder = makeAddr("data");
        assertEq(_readData(holder), ""); // unknown → empty
        Credential memory c = _cred(K_DATA);
        c.data = abi.encode(uint256(42), "hello");
        _mint(holder, c);
        assertEq(_readData(holder), abi.encode(uint256(42), "hello"));
    }

    // Active set: void evicts at once; expiry needs a sweep; reads stay correct throughout.
    function test_ActiveSet_VoidAndSweepEvict() public {
        address holder = makeAddr("active");
        uint256 id1 = _mint(holder, _kyc("US", "CA")); // long-lived
        Credential memory shortC = _kyc("US", "NY");
        shortC.expiryDate = uint64(block.timestamp + 2 days);
        _mint(holder, shortC); // expires soon
        uint256 id3 = _mint(holder, _cred(K_ACCREDITED));
        assertEq(badge.getActiveTokenIds(holder).length, 3);

        vm.prank(owner);
        badge.void(id3, "revoked"); // evicted immediately
        assertEq(badge.getActiveTokenIds(holder).length, 2);

        vm.warp(block.timestamp + 3 days); // the short-lived cred expired
        assertEq(badge.getActiveTokenIds(holder).length, 2); // not yet swept
        badge.sweep(holder); // permissionless
        uint256[] memory active = badge.getActiveTokenIds(holder);
        assertEq(active.length, 1);
        assertEq(active[0], id1); // only the long-lived one remains

        assertEq(_readUsState(holder), bytes2("CA")); // read still correct after eviction
        assertFalse(badge.hasValidCredentialOf(holder, K_ACCREDITED)); // voided status gone
    }

    // Eviction is a swap-pop, so the position index has to survive removals from the front, the middle and
    // the tail: every surviving credential must stay addressable and evictable in turn.
    function test_ActiveSet_SwapPopKeepsRemainingAddressable() public {
        address holder = makeAddr("swapPop");
        uint256 accredited = _mint(holder, _cred(K_ACCREDITED));
        uint256 qp = _mint(holder, _cred(K_QP));
        uint256 qib = _mint(holder, _cred(K_QIB));
        uint256 badActorClear = _mint(holder, _cred(K_BAD_ACTOR_CLEAR));
        assertEq(badge.getActiveTokenIds(holder).length, 4);

        vm.startPrank(owner);
        badge.void(accredited, "front"); // head slot; the tail entry swaps into it
        badge.void(badActorClear, "swapped-in"); // that swapped-in entry, at its new position
        badge.void(qib, "tail");
        vm.stopPrank();

        uint256[] memory active = badge.getActiveTokenIds(holder);
        assertEq(active.length, 1);
        assertEq(active[0], qp);
        assertTrue(badge.hasValidCredentialOf(holder, K_QP));
        assertFalse(badge.hasValidCredentialOf(holder, K_ACCREDITED));
        assertFalse(badge.hasValidCredentialOf(holder, K_QIB));
        assertFalse(badge.hasValidCredentialOf(holder, K_BAD_ACTOR_CLEAR));
    }

    // sweep evicts only what has expired, is safe to repeat, and is a no-op for an uncredentialed holder.
    function test_Sweep_EvictsOnlyExpired_AndIsIdempotent() public {
        address holder = makeAddr("sweeper");
        Credential memory shortA = _cred(K_ACCREDITED);
        shortA.expiryDate = uint64(block.timestamp + 1 days);
        Credential memory shortB = _cred(K_QP);
        shortB.expiryDate = uint64(block.timestamp + 1 days);
        _mint(holder, shortA);
        _mint(holder, shortB);
        uint256 live = _mint(holder, _kyc("US", "CA"));

        badge.sweep(holder); // nothing expired yet
        assertEq(badge.getActiveTokenIds(holder).length, 3);

        vm.warp(block.timestamp + 2 days);
        badge.sweep(holder); // both short-lived ones evicted in a single pass
        uint256[] memory active = badge.getActiveTokenIds(holder);
        assertEq(active.length, 1);
        assertEq(active[0], live);

        badge.sweep(holder); // repeat: no further change
        assertEq(badge.getActiveTokenIds(holder).length, 1);

        badge.sweep(makeAddr("neverCredentialed")); // no-op, must not revert
    }

    function test_SweepHolders_BatchesAcrossHolders() public {
        address[] memory holders = new address[](3);
        for (uint256 i = 0; i < holders.length; i++) {
            holders[i] = makeAddr(string.concat("batch", vm.toString(i)));
            Credential memory short = _cred(K_ACCREDITED);
            short.expiryDate = uint64(block.timestamp + 1 days);
            _mint(holders[i], short);
            _mint(holders[i], _kyc("US", "CA"));
        }

        vm.warp(block.timestamp + 2 days);
        badge.sweepHolders(holders);
        for (uint256 i = 0; i < holders.length; i++) {
            assertEq(badge.getActiveTokenIds(holders[i]).length, 1);
        }
    }

    // sweepTokens evicts exactly the named expired ids and reports the count.
    function test_SweepTokens_EvictsNamedExpiredIds() public {
        address holder = makeAddr("named");
        Credential memory shortA = _cred(K_ACCREDITED);
        shortA.expiryDate = uint64(block.timestamp + 1 days);
        Credential memory shortB = _cred(K_QP);
        shortB.expiryDate = uint64(block.timestamp + 1 days);
        uint256 a = _mint(holder, shortA);
        uint256 b = _mint(holder, shortB);
        uint256 live = _mint(holder, _kyc("US", "CA"));

        vm.warp(block.timestamp + 2 days);
        uint256[] memory batch = new uint256[](1);
        batch[0] = a;
        assertEq(badge.sweepTokens(batch), 1); // only the id we named
        assertEq(badge.getActiveTokenIds(holder).length, 2);

        batch[0] = b;
        assertEq(badge.sweepTokens(batch), 1);
        uint256[] memory active = badge.getActiveTokenIds(holder);
        assertEq(active.length, 1);
        assertEq(active[0], live);
    }

    // The point of sweepTokens: an active set larger than one sweep can scan still drains, batch by batch,
    // because each call is bounded by its own calldata and its progress persists.
    function test_SweepTokens_DrainsASetTooLargeToSweepAtOnce() public {
        address holder = makeAddr("oversized");
        uint256 total = 60;
        for (uint256 i = 0; i < total; i++) {
            Credential memory short = _cred(K_ACCREDITED);
            short.expiryDate = uint64(block.timestamp + 1 days);
            _mint(holder, short);
        }
        uint256 live = _mint(holder, _kyc("US", "CA"));
        vm.warp(block.timestamp + 2 days);

        // Drain in fixed-size batches, re-reading the set each round: no single call scans the whole set.
        uint256 evicted;
        while (badge.getActiveTokenIds(holder).length > 1) {
            uint256[] memory active = badge.getActiveTokenIds(holder);
            uint256 size = active.length > 10 ? 10 : active.length;
            uint256[] memory batch = new uint256[](size);
            for (uint256 i = 0; i < size; i++) {
                batch[i] = active[i];
            }
            evicted += badge.sweepTokens(batch);
        }

        assertEq(evicted, total);
        uint256[] memory remaining = badge.getActiveTokenIds(holder);
        assertEq(remaining.length, 1);
        assertEq(remaining[0], live); // the valid credential survived every batch
        assertTrue(badge.hasValidLexCheX(holder));
    }

    // An untrusted caller must not be able to drop a VALID credential and suppress a compliance fact.
    function test_SweepTokens_CannotEvictValidCredential() public {
        address holder = makeAddr("protected");
        uint256 live = _mint(holder, _kyc("US", "CA"));

        uint256[] memory batch = new uint256[](1);
        batch[0] = live;
        vm.prank(makeAddr("stranger"));
        assertEq(badge.sweepTokens(batch), 0);

        uint256[] memory active = badge.getActiveTokenIds(holder);
        assertEq(active.length, 1);
        assertEq(active[0], live);
        assertEq(_readUsState(holder), bytes2("CA")); // the fact still answers
    }

    // sweepTokens derives each holder from its token, so one batch spanning two holders evicts from each
    // holder's own set and leaves the other's intact.
    function test_SweepTokens_MixedHoldersStayIsolated() public {
        address first = makeAddr("mixedFirst");
        address second = makeAddr("mixedSecond");
        Credential memory short = _cred(K_ACCREDITED);
        short.expiryDate = uint64(block.timestamp + 1 days);

        uint256 firstExpired = _mint(first, short);
        uint256 firstLive = _mint(first, _kyc("US", "CA"));
        uint256 secondExpired = _mint(second, short);
        uint256 secondLive = _mint(second, _kyc("KY", bytes2(0)));

        vm.warp(block.timestamp + 2 days);
        uint256[] memory batch = new uint256[](2);
        batch[0] = secondExpired; // deliberately out of holder order
        batch[1] = firstExpired;
        assertEq(badge.sweepTokens(batch), 2);

        uint256[] memory firstActive = badge.getActiveTokenIds(first);
        assertEq(firstActive.length, 1);
        assertEq(firstActive[0], firstLive);
        uint256[] memory secondActive = badge.getActiveTokenIds(second);
        assertEq(secondActive.length, 1);
        assertEq(secondActive[0], secondLive);
    }

    // A stale or malformed batch is harmless: unknown ids, unexpired ids and ids already evicted by void()
    // or an earlier sweep are all skipped, and the count reports only real evictions.
    function test_SweepTokens_SkipsUnknownAndAlreadyEvicted() public {
        address holder = makeAddr("stale");
        Credential memory short = _cred(K_ACCREDITED);
        short.expiryDate = uint64(block.timestamp + 1 days);
        uint256 expired = _mint(holder, short);
        Credential memory shortVoided = _cred(K_QP);
        shortVoided.expiryDate = uint64(block.timestamp + 1 days);
        uint256 voided = _mint(holder, shortVoided);
        uint256 live = _mint(holder, _kyc("US", "CA"));

        vm.prank(owner);
        badge.void(voided, "revoked"); // already evicted at void time
        vm.warp(block.timestamp + 2 days);

        uint256[] memory batch = new uint256[](4);
        batch[0] = 9999; // never minted
        batch[1] = voided; // expired but already evicted
        batch[2] = live; // still valid
        batch[3] = expired; // the only real eviction
        assertEq(badge.sweepTokens(batch), 1);
        assertEq(badge.getActiveTokenIds(holder).length, 1);

        assertEq(badge.sweepTokens(batch), 0); // replaying the batch changes nothing
        assertEq(badge.getActiveTokenIds(holder).length, 1);
        assertTrue(badge.isValid(live)); // records survive: nothing was burned
        assertFalse(badge.isValid(expired));
    }

    function test_HasValidLexCheX_AnyValidCredential() public {
        address holder = makeAddr("v1");
        assertFalse(badge.hasValidLexCheX(holder));
        _mint(holder, _kyc("US", "CA"));
        assertTrue(badge.hasValidLexCheX(holder));
    }

    // Seasoning: earliest valid issuance asserting a key (0 when none).
    function test_EarliestValidIssuance() public {
        address holder = makeAddr("season");
        assertEq(uint256(badge.earliestValidIssuance(holder, K_ACCREDITED)), 0);
        uint256 firstId = _mint(holder, _cred(K_ACCREDITED));
        uint64 t0 = badge.getCredential(firstId).issuanceDate;
        vm.warp(block.timestamp + 10 days);
        _mint(holder, _cred(K_ACCREDITED)); // later issuance; earliest must stay the first
        assertEq(uint256(badge.earliestValidIssuance(holder, K_ACCREDITED)), uint256(t0));
    }

    // ── Issuing authority ─────────────────────────────────────────────────────
    // One badge can host more than one credentialing operator. Mint rights alone are not authority: each
    // delegate is granted a set of facts it may assert, every credential records who issued it, and a reader
    // can insist on the issuer it trusts. Without this, letting a second operator issue anything would mean
    // trusting it for everything.

    // A delegate writes only what it was granted. It holds mint rights, so nothing but the mask stops it
    // asserting a fact that belongs to another operator.
    function test_IssuerKeys_DelegateLimitedToGrantedKeys() public {
        address legion = _delegateIssuer("legion", K_SYNDICATE);
        address holder = makeAddr("member");

        Credential memory seat = _cred(K_SYNDICATE);
        seat.scope = makeAddr("spvA");
        _mintAs(legion, holder, seat);
        assertTrue(badge.hasValidCredentialOf(holder, K_SYNDICATE, seat.scope));

        Credential memory accredited = _cred(K_ACCREDITED);
        vm.prank(legion);
        vm.expectRevert(
            abi.encodeWithSelector(ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, legion, K_ACCREDITED)
        );
        badge.mint(holder, accredited);
    }

    function test_IssuerKeys_GrantAloneAuthorizesIssuing() public {
        address legion = _delegateIssuer("legionNoRole", K_ACCREDITED);
        assertEq(auth.userRoles(legion), 0, "issues with no BorgAuth role at all");
        _mintAs(legion, makeAddr("granted"), _cred(K_ACCREDITED));

        address nobody = makeAddr("ungranted");
        Credential memory c = _cred(K_ACCREDITED);
        address holder = makeAddr("wouldBeAccredited");
        vm.prank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, nobody, K_ACCREDITED)
        );
        badge.mint(holder, c);
    }

    // mint records the issuer; that record is what a filtered read later consults.
    function test_Mint_RecordsIssuer() public {
        address legion = _delegateIssuer("legionRec", K_ACCREDITED);
        uint256 id = _mintAs(legion, makeAddr("recorded"), _cred(K_ACCREDITED));
        assertEq(badge.getCredential(id).issuer, legion);
    }

    // Admins run the deployment, so they issue anything without a grant.
    function test_Mint_AdminNeedsNoGrant() public {
        address operator = makeAddr("operator");
        vm.prank(owner);
        auth.updateRole(operator, 98);

        assertEq(badge.issuerKeys(operator), 0);
        uint256 id = _mintAs(operator, makeAddr("byAdmin"), _cred(K_ACCREDITED));
        assertEq(badge.getCredential(id).issuer, operator);
    }

    // An operator whose admin authority comes from a BorgAuth role adapter (a Safe, a Hats tree) is an admin
    // everywhere else on this badge, so it issues without a grant like any other. Reading userRoles directly
    // would miss it and demote it to an ungranted issuer.
    function test_Mint_AdapterBackedAdminNeedsNoGrant() public {
        address operator = makeAddr("adapterOperator");
        AdminAdapter adapter = new AdminAdapter(operator);
        uint256 adminRole = auth.ADMIN_ROLE();
        vm.prank(owner);
        auth.setRoleAdapter(adminRole, address(adapter));

        assertEq(auth.userRoles(operator), 0, "authority is the adapter's, not a stored role");
        assertEq(badge.issuerKeys(operator), 0);

        uint256 id = _mintAs(operator, makeAddr("byAdapterAdmin"), _cred(K_ACCREDITED));
        assertEq(badge.getCredential(id).issuer, operator);
    }

    // A delegate revokes only its own work. Otherwise the mask would bound what it can write but not what it
    // can destroy, and one operator could wipe another's credentials.
    function test_Void_DelegateCannotVoidAnotherIssuersCredential() public {
        address legion = _delegateIssuer("legionVoid", K_SYNDICATE);
        address holder = makeAddr("crossVoid");
        uint256 ownerIssued = _mint(holder, _cred(K_ACCREDITED));

        vm.prank(legion);
        vm.expectRevert(abi.encodeWithSignature("BorgAuth_NotAuthorized(uint256,address)", uint256(98), legion));
        badge.void(ownerIssued, "not yours");
        assertTrue(badge.isValid(ownerIssued));

        Credential memory seat = _cred(K_SYNDICATE);
        seat.scope = makeAddr("spvB");
        uint256 own = _mintAs(legion, holder, seat);
        vm.prank(legion);
        badge.void(own, "left the circle");
        assertFalse(badge.isValid(own));
    }

    // The owner can still void a delegate's credential — the lever for an issuer that goes rogue.
    function test_Void_OwnerCanVoidDelegatesCredential() public {
        address legion = _delegateIssuer("legionRogue", K_SYNDICATE);
        Credential memory seat = _cred(K_SYNDICATE);
        seat.scope = makeAddr("spvC");
        uint256 id = _mintAs(legion, makeAddr("ownerVoid"), seat);

        vm.prank(owner);
        badge.void(id, "issuer compromised");
        assertFalse(badge.isValid(id));
    }

    // A filtered read takes only the issuer it names; the unfiltered read still takes either.
    function test_IssuerFilter_NarrowsAStatusFact() public {
        address legion = _delegateIssuer("legionFilter", K_ACCREDITED);
        address holder = makeAddr("filtered");
        _mintAs(legion, holder, _cred(K_ACCREDITED));

        assertTrue(badge.hasValidCredentialOf(holder, K_ACCREDITED));
        assertTrue(badge.hasValidCredentialOf(holder, K_ACCREDITED, _issuers(legion)));
        assertFalse(badge.hasValidCredentialOf(holder, K_ACCREDITED, _issuers(owner)));
    }

    // An entitlement answers for the SPV it names AND the operator who granted it, so one operator's seat in
    // an SPV does not clear a gate that takes another operator's word for that same SPV.
    function test_IssuerFilter_NarrowsAScopedSeat() public {
        address legion = _delegateIssuer("legionScoped", K_SYNDICATE);
        address spv = makeAddr("spvShared");
        address holder = makeAddr("twoCircles");

        Credential memory ownerSeat = _cred(K_SYNDICATE);
        ownerSeat.scope = spv;
        _mint(holder, ownerSeat);
        assertTrue(badge.hasValidCredentialOf(holder, K_SYNDICATE, spv));
        assertFalse(badge.hasValidCredentialOf(holder, K_SYNDICATE, _issuers(legion), spv, address(0), ""));

        Credential memory legionSeat = _cred(K_SYNDICATE);
        legionSeat.scope = spv;
        _mintAs(legion, holder, legionSeat);
        assertTrue(badge.hasValidCredentialOf(holder, K_SYNDICATE, _issuers(legion), spv, address(0), ""));
    }

    // ── Query hooks: questions the fact-key vocabulary cannot ask ─────────────
    // The badge picks the eligible credentials (valid, in the active set) and the resolution; a caller-supplied
    // hook decides what counts as a match. That is how `data` becomes queryable without the badge learning any
    // issuer's schema.

    // The case that broke the earlier design: Alice holds tier1 AND tier2 at the same time and both are true,
    // so both queries must say yes. Any read that picked one credential would have thrown a true answer away.
    function test_Hook_ConcurrentTiersBothMatch() public {
        address legion = _delegateIssuer("legionTiers", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvTiers");
        address alice = makeAddr("alice");

        _seat(legion, alice, spv, abi.encode(TIER1));
        vm.warp(block.timestamp + 30 days);
        _seat(legion, alice, spv, abi.encode(TIER2));

        assertTrue(
            badge.hasValidCredentialOf(alice, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER1)),
            "older tier still true"
        );
        assertTrue(
            badge.hasValidCredentialOf(alice, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER2)),
            "newer tier true too"
        );
        assertFalse(
            badge.hasValidCredentialOf(alice, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER3)),
            "a tier she was never given"
        );
    }

    // The hook sees the whole credential, so the SPV and the issuer are part of its test — a seat in another
    // SPV, or the same tier from a rival operator, is not a match.
    function test_Hook_TierIsScopedAndIssuerBound() public {
        address legion = _delegateIssuer("legionBound", K_SYNDICATE | K_DATA);
        address rival = _delegateIssuer("rivalBound", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvBound");
        address holder = makeAddr("boundHolder");

        _seat(legion, holder, makeAddr("otherSpv"), abi.encode(TIER2)); // right tier, wrong SPV
        _seat(rival, holder, spv, abi.encode(TIER2)); // right tier and SPV, wrong issuer

        assertFalse(badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER2)));
        assertTrue(
            badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), _tierHook(), _tier(spv, rival, TIER2)),
            "it is the rival's tier"
        );
    }

    // Validity stays the badge's decision: a voided credential never reaches the hook, so even a hook that
    // accepts everything cannot resurrect it.
    function test_Hook_NeverSeesVoidedOrExpired() public {
        address legion = _delegateIssuer("legionVoided", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvVoided");
        address holder = makeAddr("revoked");
        uint256 id = _seat(legion, holder, spv, abi.encode(TIER1));

        address anything = address(new AlwaysMatchHook());
        assertTrue(badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), anything, ""));

        vm.prank(legion);
        badge.void(id, "left the circle");
        assertFalse(
            badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), anything, ""),
            "voided is not eligible, whatever the hook says"
        );
    }

    // The two resolutions answer differently on the same data, on purpose. Membership wants every match;
    // recency wants the one that supersedes.
    function test_Hook_AnyMatchVersusMostRecent() public {
        address legion = _delegateIssuer("legionBoth", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvBoth");
        address holder = makeAddr("bothWays");

        uint256 older = _seat(legion, holder, spv, abi.encode(TIER1));
        vm.warp(block.timestamp + 30 days);
        uint256 newer = _seat(legion, holder, spv, abi.encode(TIER2));

        address anySeat = address(new AlwaysMatchHook());
        (uint256 id, bool found) = badge.getMostRecentValidWith(holder, 0, new address[](0), address(0), anySeat, "");
        assertTrue(found);
        assertEq(id, newer, "recency picks the latest");
        assertTrue(
            badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER1)),
            "which the older one still is"
        );
        assertTrue(badge.isValid(older));
    }

    // The fact-key resolution, exposed. Same answer the value getters resolve to, so a caller can reach the
    // credential instead of just the field.
    function test_GetMostRecentValidWith_MatchesTheValueGetter() public {
        address holder = makeAddr("relocating");
        _mint(holder, _kyc("US", "NY"));
        vm.warp(block.timestamp + 30 days);
        uint256 tx_ = _mint(holder, _kyc("US", "TX"));

        (uint256 id, bool found) = badge.getMostRecentValidWith(holder, K_US_STATE);
        assertTrue(found);
        assertEq(id, tx_);
        assertEq(_readUsState(holder), bytes2("TX"));
    }

    // Either filter on its own is a real question; neither is a wiring slip. A hook with no key is the whole
    // point of the hook, so it must not be caught by the empty-query guard.
    function test_Hook_AloneIsAValidQueryButNeitherIsNot() public {
        address legion = _delegateIssuer("legionAlone", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvAlone");
        address holder = makeAddr("hookOnly");
        _seat(legion, holder, spv, abi.encode(TIER1));

        assertTrue(
            badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER1)),
            "key 0 + hook is fine"
        );
        assertTrue(badge.hasValidCredentialOf(holder, K_SYNDICATE), "key alone is fine");

        vm.expectRevert(ILexChexBadge.LexChexBadge_EmptyQuery.selector);
        badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), address(0), "");

        vm.expectRevert(ILexChexBadge.LexChexBadge_EmptyQuery.selector);
        badge.getMostRecentValidWith(holder, 0, new address[](0), address(0), address(0), "");
    }

    // Seasoning asked the same way membership is: how long has she been tier1, not how long she has been in
    // the circle. The later tier2 seat is a different fact and must not move the tier1 clock.
    function test_Hook_SeasoningIsPerTier() public {
        address legion = _delegateIssuer("legionSeason", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvSeason");
        address alice = makeAddr("aliceSeason");

        uint256 seat1 = _seat(legion, alice, spv, abi.encode(TIER1));
        vm.warp(block.timestamp + 90 days);
        uint256 seat2 = _seat(legion, alice, spv, abi.encode(TIER2));

        // Read the dates off the credentials rather than the test's own clock, which vm.warp does not move.
        uint256 tier1At = uint256(badge.getCredential(seat1).issuanceDate);
        uint256 tier2At = uint256(badge.getCredential(seat2).issuanceDate);
        assertGt(tier2At, tier1At, "the second seat is the later one");

        assertEq(
            uint256(badge.earliestValidIssuance(alice, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER1))),
            tier1At,
            "tier1"
        );
        assertEq(
            uint256(badge.earliestValidIssuance(alice, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER2))),
            tier2At,
            "tier2"
        );
        // Without the hook the question is just "in the circle", which she has been since the first seat.
        assertEq(uint256(badge.earliestValidIssuance(alice, K_SYNDICATE)), tier1At, "circle since tier1");
        assertEq(
            uint256(badge.earliestValidIssuance(alice, 0, new address[](0), address(0), _tierHook(), _tier(spv, legion, TIER3))),
            0,
            "never held"
        );
    }

    // All four filters on one call, which is the point of the combined form: the right fact, from the right
    // operator, for the right SPV, at the right tier. Dropping any one of them lets a near-miss through.
    function test_AllFiltersCompose() public {
        address legion = _delegateIssuer("legionAll", K_SYNDICATE | K_DATA);
        address rival = _delegateIssuer("rivalAll", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvAll");
        address other = makeAddr("spvOther");
        address holder = makeAddr("nearMisses");

        _seat(rival, holder, spv, abi.encode(TIER2)); // wrong issuer
        _seat(legion, holder, other, abi.encode(TIER2)); // wrong SPV
        _seat(legion, holder, spv, abi.encode(TIER1)); // wrong tier
        assertFalse(
            badge.hasValidCredentialOf(holder, K_SYNDICATE, _issuers(legion), spv, _tierHook(), _tier(spv, legion, TIER2)),
            "three near misses, no match"
        );

        _seat(legion, holder, spv, abi.encode(TIER2)); // all four line up
        assertTrue(
            badge.hasValidCredentialOf(holder, K_SYNDICATE, _issuers(legion), spv, _tierHook(), _tier(spv, legion, TIER2))
        );
    }

    // The two filters compose: the key narrows to credentials carrying the fact, the hook to those its schema
    // accepts, and a credential has to clear both.
    function test_Hook_KeyAndHookBothApply() public {
        address legion = _delegateIssuer("legionBoth2", K_SYNDICATE | K_DATA | K_ACCREDITED);
        address spv = makeAddr("spvCompose");
        address holder = makeAddr("composed");
        _seat(legion, holder, spv, abi.encode(TIER1));

        bytes memory tier1 = _tier(spv, legion, TIER1);
        assertTrue(badge.hasValidCredentialOf(holder, K_SYNDICATE, new address[](0), address(0), _tierHook(), tier1));
        // The seat clears the hook but does not carry K_ACCREDITED, and no other credential does either.
        assertFalse(badge.hasValidCredentialOf(holder, K_ACCREDITED, new address[](0), address(0), _tierHook(), tier1));
    }

    // A multi-bit scoped ask needs every bit covered, and the credentials scoped to that SPV add up to cover
    // them. One seat alone does not answer for both.
    function test_ScopedFilter_MultiKeyAddsUpWithinOneSpv() public {
        address spv = makeAddr("spvMultiKey");
        address holder = makeAddr("bothSeats");
        uint256 both = K_SPV_WHITELIST | K_SYNDICATE;

        _mint(holder, _scoped(K_SPV_WHITELIST, spv));
        assertFalse(badge.hasValidCredentialOf(holder, both, spv), "whitelist alone does not cover both");

        _mint(holder, _scoped(K_SYNDICATE, spv));
        assertTrue(badge.hasValidCredentialOf(holder, both, spv), "the two seats together do");
    }

    // Keys only add up within the scope asked for: a seat in another SPV contributes nothing.
    function test_ScopedFilter_MultiKeyDoesNotAddUpAcrossSpvs() public {
        address spvA = makeAddr("spvSplitA");
        address spvB = makeAddr("spvSplitB");
        address holder = makeAddr("splitSeats");

        _mint(holder, _scoped(K_SPV_WHITELIST, spvA));
        _mint(holder, _scoped(K_SYNDICATE, spvB));
        assertFalse(badge.hasValidCredentialOf(holder, K_SPV_WHITELIST | K_SYNDICATE, spvA));
        assertFalse(badge.hasValidCredentialOf(holder, K_SPV_WHITELIST | K_SYNDICATE, spvB));
    }

    // The recency read takes the issuer filter too: the newest credential overall is skipped when a rival
    // issued it.
    function test_GetMostRecentValidWith_RespectsIssuerFilter() public {
        address legion = _delegateIssuer("legionRecent", K_ACCREDITED);
        address rival = _delegateIssuer("rivalRecent", K_ACCREDITED);
        address holder = makeAddr("recentFiltered");

        uint256 legionId = _mintAs(legion, holder, _cred(K_ACCREDITED));
        vm.warp(block.timestamp + 30 days);
        uint256 rivalId = _mintAs(rival, holder, _cred(K_ACCREDITED));

        (uint256 anyIssuer,) = badge.getMostRecentValidWith(holder, K_ACCREDITED);
        assertEq(anyIssuer, rivalId, "newest overall");
        (uint256 fromLegion, bool found) = badge.getMostRecentValidWith(holder, K_ACCREDITED, _issuers(legion));
        assertTrue(found);
        assertEq(fromLegion, legionId, "newest of Legion's");
    }

    // And the scope filter: the newest seat in another SPV does not answer for this one.
    function test_GetMostRecentValidWith_RespectsScopeFilter() public {
        address spvA = makeAddr("spvRecentA");
        address spvB = makeAddr("spvRecentB");
        address holder = makeAddr("recentScoped");

        uint256 seatA = _mint(holder, _scoped(K_SYNDICATE, spvA));
        vm.warp(block.timestamp + 30 days);
        _mint(holder, _scoped(K_SYNDICATE, spvB));

        (uint256 id, bool found) = badge.getMostRecentValidWith(holder, K_SYNDICATE, spvA);
        assertTrue(found);
        assertEq(id, seatA);
    }

    // Seasoning takes the same filters: how long in THIS SPV's circle, on THIS issuer's word.
    function test_EarliestValidIssuance_RespectsIssuerAndScope() public {
        address legion = _delegateIssuer("legionSeason2", K_SYNDICATE);
        address spvA = makeAddr("spvSeasonA");
        address spvB = makeAddr("spvSeasonB");
        address holder = makeAddr("seasonFiltered");

        Credential memory early = _scoped(K_SYNDICATE, spvB); // earlier, but another SPV
        uint256 earlyId = _mintAs(legion, holder, early);
        vm.warp(block.timestamp + 60 days);
        uint256 lateId = _mintAs(legion, holder, _scoped(K_SYNDICATE, spvA));

        uint256 earlyAt = uint256(badge.getCredential(earlyId).issuanceDate);
        uint256 lateAt = uint256(badge.getCredential(lateId).issuanceDate);
        assertGt(lateAt, earlyAt);

        assertEq(uint256(badge.earliestValidIssuance(holder, K_SYNDICATE)), earlyAt, "unfiltered takes the earliest");
        assertEq(
            uint256(badge.earliestValidIssuance(holder, K_SYNDICATE, new address[](0), spvA, address(0), "")),
            lateAt,
            "spvA's circle started later"
        );
        assertEq(
            uint256(
                badge.earliestValidIssuance(holder, K_SYNDICATE, _issuers(makeAddr("nobody")), address(0), address(0), "")
            ),
            0,
            "no seat from that issuer"
        );
    }

    // An expired credential is out of the query before the hook runs, the same as a voided one.
    function test_Hook_NeverSeesExpired() public {
        address legion = _delegateIssuer("legionExpiring", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvExpiring");
        address holder = makeAddr("lapsed");

        Credential memory c = _cred(K_SYNDICATE | K_DATA);
        c.scope = spv;
        c.data = abi.encode(TIER1);
        c.expiryDate = uint64(block.timestamp + 1 days);
        _mintAs(legion, holder, c);

        address anything = address(new AlwaysMatchHook());
        assertTrue(badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), anything, ""));

        vm.warp(block.timestamp + 2 days);
        assertFalse(badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), anything, ""));
    }

    // The badge hands the hook the holder, the token id, that token's record, and the caller's payload
    // verbatim — the payload is what the hook is told, so it has to arrive byte for byte.
    function test_Hook_ReceivesOwnerTokenIdCredentialAndPayload() public {
        address legion = _delegateIssuer("legionArgs", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvArgs");
        address holder = makeAddr("argsHolder");
        uint256 id = _seat(legion, holder, spv, abi.encode(TIER1));

        address checker = address(new ArgCheckHook());
        bytes memory right = abi.encode(holder, id, "carried through untouched");
        assertTrue(badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), checker, right));

        bytes memory wrongToken = abi.encode(holder, id + 1, "carried through untouched");
        assertFalse(badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), checker, wrongToken));

        bytes memory wrongNote = abi.encode(holder, id, "mangled");
        assertFalse(badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), checker, wrongNote));
    }

    // The hook is code the caller chose, so its revert is the caller's problem: the read reverts with it
    // rather than reading false.
    function test_Hook_RevertPropagates() public {
        address legion = _delegateIssuer("legionReverting", K_SYNDICATE | K_DATA);
        address spv = makeAddr("spvReverting");
        address holder = makeAddr("revertHolder");
        _seat(legion, holder, spv, abi.encode(TIER1));

        address boom = address(new RevertingHook());
        vm.expectRevert(RevertingHook.HookFailed.selector);
        badge.hasValidCredentialOf(holder, 0, new address[](0), address(0), boom, "");
    }

    // An empty list accepts any issuer, so a caller that does not care reads exactly as before.
    function test_IssuerFilter_EmptyListAcceptsAnyIssuer() public {
        address legion = _delegateIssuer("legionAny", K_ACCREDITED);
        address holder = makeAddr("anyIssuer");
        _mintAs(legion, holder, _cred(K_ACCREDITED));
        assertTrue(badge.hasValidCredentialOf(holder, K_ACCREDITED, new address[](0)));
    }

    // Admins hand out authority — they already assert everything themselves, so delegating gives away nothing
    // they lack. A delegate holds no role, so it cannot pass its own grant on to anyone else.
    function test_SetIssuerKeys_AdminGrantsButDelegateCannotReDelegate() public {
        address operator = makeAddr("operatorGrant");
        vm.prank(owner);
        auth.updateRole(operator, 98);

        address legion = makeAddr("legionGrantee");
        vm.prank(operator);
        badge.setIssuerKeys(legion, K_SYNDICATE);
        assertEq(badge.issuerKeys(legion), K_SYNDICATE);

        address downstream = makeAddr("downstream");
        vm.prank(legion);
        vm.expectRevert(abi.encodeWithSignature("BorgAuth_NotAuthorized(uint256,address)", uint256(98), legion));
        badge.setIssuerKeys(downstream, K_SYNDICATE);
    }

    // A grant is not tied to the admin that made it: revoking that admin leaves the delegate issuing, so
    // offboarding an admin means clearing what it delegated too.
    function test_SetIssuerKeys_GrantOutlivesTheGrantingAdmin() public {
        address operator = makeAddr("operatorLeaving");
        vm.prank(owner);
        auth.updateRole(operator, 98);
        vm.prank(operator);
        badge.setIssuerKeys(makeAddr("legionSurvivor"), K_ACCREDITED);

        vm.prank(owner);
        auth.updateRole(operator, 0); // admin offboarded

        address legion = makeAddr("legionSurvivor");
        assertEq(badge.issuerKeys(legion), K_ACCREDITED, "the grant did not lapse with its granter");
        _mintAs(legion, makeAddr("stillCredentialed"), _cred(K_ACCREDITED));
    }

    // An undefined bit is a wiring slip, not a new fact to grant.
    function test_SetIssuerKeys_RejectsUnknownBits() public {
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_BadAsserts.selector);
        badge.setIssuerKeys(makeAddr("badGrant"), 1 << 60);
    }

    // ── Mint validation & lifecycle ───────────────────────────────────────────

    // Issuing is gated on the grant, so a caller with neither grant nor role gets nowhere.
    function test_Mint_UngrantedCallerRejected() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        badge.mint(makeAddr("to"), _kyc("US", "CA"));
    }

    function test_Mint_EmptyAsserts_Reverts() public {
        Credential memory c;
        c.expiryDate = uint64(block.timestamp + 1 days);
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_BadAsserts.selector);
        badge.mint(makeAddr("to"), c);
    }

    // Every VALUE key must carry its payload: asserting one while leaving its field empty is a hollow
    // attestation and is rejected at mint. One case per value key.
    function test_Mint_MissingValue_EachValueKeyReverts() public {
        _expectMissingValue(K_INVESTOR_TYPE);
        _expectMissingValue(K_INVESTOR_JURISDICTION);
        _expectMissingValue(K_LOOKTHROUGH_JURISDICTION);
        _expectMissingValue(K_US_STATE);
        _expectMissingValue(K_BO_COUNT);
        _expectMissingValue(K_DATA);
        _expectMissingValue(K_NATIONALITY_OUT);
    }

    // `asserts` admits only defined K_* bits — an undefined bit would be an uninterpretable claim.
    function test_Mint_UnknownAssertBit_Reverts() public {
        address to = makeAddr("unknownBit");
        Credential memory gapBit = _cred(1 << 7); // free bit reserved inside the VALUE block
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_BadAsserts.selector);
        badge.mint(to, gapBit);

        Credential memory aboveTop = _cred(K_SYNDICATE << 1); // above the highest defined key
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_BadAsserts.selector);
        badge.mint(to, aboveTop);

        Credential memory mixed = _kyc("US", "CA"); // otherwise-valid credential plus one unknown bit
        mixed.asserts |= (1 << 7);
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_BadAsserts.selector);
        badge.mint(to, mixed);
    }

    // Presets are issuer guidance, not a schema: a preset mints, and so does a bespoke composition that
    // matches no preset.
    function test_Presets_UsableAndNotMandatory() public {
        address individual = makeAddr("presetKyc");
        Credential memory kyc = _cred(PRESET_KYC_AML);
        kyc.investorType = InvestorType.INDIVIDUAL;
        kyc.investorJurisdiction = "US";
        _mint(individual, kyc);
        assertEq(_readJurisdiction(individual), "US");

        address feeder = makeAddr("presetLookthrough");
        Credential memory lookThrough = _cred(PRESET_ENTITY_LOOKTHROUGH);
        lookThrough.investorType = InvestorType.ENTITY;
        lookThrough.lookThroughJurisdiction = "US";
        lookThrough.beneficialOwnerCount = 3;
        _mint(feeder, lookThrough);
        assertEq(_readLookThrough(feeder), "US");
        assertEq(uint256(_readBoCount(feeder)), 3);

        address bespoke = makeAddr("bespoke");
        address spv = makeAddr("spvBespoke");
        Credential memory composed = _cred(K_QIB | K_SPV_WHITELIST | K_DATA); // matches no preset
        composed.scope = spv;
        composed.data = hex"01";
        _mint(bespoke, composed);
        assertTrue(badge.hasValidCredentialOf(bespoke, K_QIB));
        assertTrue(badge.hasValidWhitelistFor(bespoke, spv));
        assertEq(_readData(bespoke), hex"01");
    }

    // Every scoped key names the SPV it entitles; asserting one without a scope is a hollow entitlement.
    function test_Mint_MissingScope_Reverts() public {
        _expectMissingScope(K_SPV_WHITELIST);
        _expectMissingScope(K_SYNDICATE);
        _expectMissingScope(K_SPV_WHITELIST | K_SYNDICATE);
    }

    function test_Mint_InvalidExpiry_Reverts() public {
        Credential memory c = _jurisdiction("US");
        c.expiryDate = uint64(block.timestamp); // not in the future
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_InvalidExpiry.selector);
        badge.mint(makeAddr("to"), c);
    }

    function test_Void_OnlyOwner_RecordRetained() public {
        address holder = makeAddr("retain");
        uint256 id = _mint(holder, _kyc("US", "CA"));

        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        badge.void(id, "x");

        vm.prank(owner);
        badge.void(id, "revoked");

        assertFalse(badge.isValid(id));
        Credential memory stored = badge.getCredential(id); // record survives for audit
        assertEq(stored.usState, bytes2("CA"));
        assertEq(stored.voided, "revoked");
    }

    // Voiding records the reason and nothing else — every attested field is frozen at issuance.
    function test_Void_LeavesAttestedFieldsUnchanged() public {
        address holder = makeAddr("frozen");
        Credential memory c = _cred(
            K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_US_STATE | K_BO_COUNT | K_DATA
                | K_SPV_WHITELIST
        );
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = "KY";
        c.lookThroughJurisdiction = "US";
        c.usState = "DE";
        c.beneficialOwnerCount = 9;
        c.data = abi.encode("payload");
        c.scope = makeAddr("spvFrozen");
        c.agreementId = keccak256("agreement");
        c.evidenceHash = keccak256("evidence");
        uint256 id = _mint(holder, c);
        Credential memory beforeVoid = badge.getCredential(id);
        assertEq(beforeVoid.voided, "");

        vm.prank(owner);
        badge.void(id, "revoked");
        Credential memory afterVoid = badge.getCredential(id);

        assertEq(afterVoid.voided, "revoked"); // the only field that changes
        assertEq(afterVoid.asserts, beforeVoid.asserts);
        assertEq(uint256(afterVoid.investorType), uint256(beforeVoid.investorType));
        assertEq(afterVoid.investorJurisdiction, beforeVoid.investorJurisdiction);
        assertEq(afterVoid.lookThroughJurisdiction, beforeVoid.lookThroughJurisdiction);
        assertEq(afterVoid.usState, beforeVoid.usState);
        assertEq(uint256(afterVoid.beneficialOwnerCount), uint256(beforeVoid.beneficialOwnerCount));
        assertEq(afterVoid.data, beforeVoid.data);
        assertEq(afterVoid.scope, beforeVoid.scope);
        assertEq(afterVoid.issuer, beforeVoid.issuer);
        assertEq(afterVoid.agreementId, beforeVoid.agreementId);
        assertEq(afterVoid.evidenceHash, beforeVoid.evidenceHash);
        assertEq(uint256(afterVoid.issuanceDate), uint256(beforeVoid.issuanceDate));
        assertEq(uint256(afterVoid.expiryDate), uint256(beforeVoid.expiryDate));
    }

    // Revocation is one-way: there is no un-void path, and a repeated void is a harmless no-op that can
    // neither resurface the credential nor corrupt the active set.
    function test_Void_TwiceIsNoop_NeverResurfaces() public {
        address holder = makeAddr("oneWay");
        _mint(holder, _kyc("US", "CA")); // older, CA
        uint256 ny = _mint(holder, _kyc("US", "NY")); // newer, NY

        vm.startPrank(owner);
        badge.void(ny, "revoked");
        badge.void(ny, "revoked again");
        vm.stopPrank();

        assertFalse(badge.isValid(ny));
        assertEq(badge.getActiveTokenIds(holder).length, 1);
        assertEq(_readUsState(holder), bytes2("CA")); // the older valid credential governs again
    }

    // An empty reason is what marks a credential as NOT voided, so it cannot be used as one: it would evict the
    // token from the active set while isValid() kept reporting it valid, and a second empty void would flip a
    // recorded revocation back to valid.
    function test_Void_EmptyReason_Reverts() public {
        address holder = makeAddr("emptyReason");
        uint256 id = _mint(holder, _kyc("US", "CA"));

        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_MissingVoidReason.selector);
        badge.void(id, "");

        assertTrue(badge.isValid(id));
        assertEq(badge.getActiveTokenIds(holder).length, 1);
    }

    function test_Supersede_EmptyReason_Reverts() public {
        address holder = makeAddr("emptySupersede");
        uint256 stale = _mint(holder, _kyc("US", "NY"));
        Credential memory replacement = _kyc("US", "CA");

        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_MissingVoidReason.selector);
        badge.supersede(stale, replacement, "");

        assertTrue(badge.isValid(stale));
        assertEq(_readUsState(holder), bytes2("NY")); // neither half of the swap happened
    }

    function test_Void_NonexistentToken_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_TokenDoesNotExist.selector);
        badge.void(999, "nope");
    }

    // Nothing is ever burned: an expired credential stops answering reads immediately (before any sweep) and,
    // once swept out of the active set, still keeps its record and its place in the ERC-721 enumeration.
    function test_AuditRecordSurvivesExpiryAndSweep() public {
        address holder = makeAddr("audit");
        Credential memory shortLived = _kyc("US", "CA");
        shortLived.expiryDate = uint64(block.timestamp + 1 days);
        uint256 id = _mint(holder, shortLived);

        vm.warp(block.timestamp + 2 days);
        assertFalse(badge.isValid(id));
        assertEq(_readUsState(holder), bytes2(0)); // fact no longer answered, still unswept
        assertFalse(badge.hasValidLexCheX(holder));
        assertEq(badge.getActiveTokenIds(holder).length, 1);

        badge.sweep(holder);
        assertEq(badge.getActiveTokenIds(holder).length, 0);

        assertEq(badge.balanceOf(holder), 1); // never burned
        uint256[] memory owned = badge.getTokenIdsByOwner(holder); // full enumeration, incl. expired
        assertEq(owned.length, 1);
        assertEq(owned[0], id);
        assertEq(badge.getCredential(id).usState, bytes2("CA")); // record intact despite eviction
    }

    // Issuance emits the indexer surface: the credential record plus the EIP-5484 Issued event, whose burn
    // authority is always Neither.
    function test_Mint_EmitsCredentialIssuedAndIssued() public {
        address holder = makeAddr("mintEvent");
        Credential memory c = _kyc("US", "CA");
        uint256 expectedId = badge.totalSupply();
        // stamped by mint; mirrored here for the record comparison
        c.issuanceDate = uint64(block.timestamp);
        c.issuer = owner;

        vm.expectEmit(true, true, false, true, address(badge));
        emit CredentialIssued(holder, expectedId, c);
        vm.expectEmit(true, true, true, true, address(badge));
        emit Issued(address(0), holder, expectedId, IERC5484.BurnAuth.Neither);
        vm.prank(owner);
        assertEq(badge.mint(holder, c), expectedId);
    }

    function test_Void_EmitsCredentialVoided() public {
        address holder = makeAddr("voidEvent");
        uint256 id = _mint(holder, _kyc("US", "CA"));

        vm.expectEmit(true, true, false, true, address(badge));
        emit CredentialVoided(holder, id, "sanctions hit");
        vm.prank(owner);
        badge.void(id, "sanctions hit");
    }

    // A sweep is the keeper's receipt: one log per credential it actually drops, and silence when it drops
    // nothing. A transaction receipt can't carry sweepTokens' return value, so the logs are how a keeper
    // confirms its own run did work.
    function test_Sweep_EmitsCredentialSwept() public {
        address holder = makeAddr("sweepEvent");
        Credential memory short = _cred(K_ACCREDITED);
        short.expiryDate = uint64(block.timestamp + 1 days);
        uint256 expiring = _mint(holder, short);
        _mint(holder, _kyc("US", "CA"));

        // Nothing has expired, so there is nothing to report.
        vm.recordLogs();
        badge.sweep(holder);
        assertEq(vm.getRecordedLogs().length, 0, "a sweep that drops nothing says nothing");

        vm.warp(block.timestamp + 2 days);
        vm.expectEmit(true, true, false, false, address(badge));
        emit CredentialSwept(holder, expiring);
        badge.sweep(holder);

        // Repeating the sweep drops nothing, so it stays silent too.
        vm.recordLogs();
        badge.sweep(holder);
        assertEq(vm.getRecordedLogs().length, 0, "already-dropped credentials are not re-reported");
    }

    function test_SweepTokens_EmitsCredentialSwept() public {
        address holder = makeAddr("sweepTokensEvent");
        Credential memory short = _cred(K_ACCREDITED);
        short.expiryDate = uint64(block.timestamp + 1 days);
        uint256 expiring = _mint(holder, short);
        uint256 live = _mint(holder, _kyc("US", "CA"));

        vm.warp(block.timestamp + 2 days);
        uint256[] memory batch = new uint256[](2);
        batch[0] = expiring;
        batch[1] = live; // still good, so it is skipped and never reported

        vm.recordLogs();
        assertEq(badge.sweepTokens(batch), 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one log for the one credential dropped");
        assertEq(logs[0].topics[0], ILexChexBadge.CredentialSwept.selector, "CredentialSwept");
        assertEq(address(uint160(uint256(logs[0].topics[1]))), holder, "holder");
        assertEq(uint256(logs[0].topics[2]), expiring, "the expired id");
    }

    function test_BurnAuth_AlwaysNeither() public {
        address holder = makeAddr("ba");
        uint256 id = _mint(holder, _kyc("US", "CA"));
        assertEq(uint256(badge.burnAuth(id)), uint256(IERC5484.BurnAuth.Neither));
    }

    // Upgrade authority is the badge owner: nobody else can swap the implementation out from under the
    // credential registry, and the credentials themselves survive an upgrade.
    function test_AuthorizeUpgrade_OnlyOwner() public {
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc; // ERC-1967
        address holder = makeAddr("upgrade");
        uint256 id = _mint(holder, _kyc("US", "CA"));
        address newImpl = address(new LeXcheXBadge());

        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        badge.upgradeToAndCall(newImpl, "");

        vm.prank(owner);
        badge.upgradeToAndCall(newImpl, "");

        assertEq(address(uint160(uint256(vm.load(address(badge), implSlot)))), newImpl);
        assertTrue(badge.isValid(id)); // credential state survives
        assertEq(_readUsState(holder), bytes2("CA"));
    }

    function test_Soulbound_TransferReverts() public {
        address holder = makeAddr("soul");
        address other = makeAddr("other");
        uint256 id = _mint(holder, _kyc("US", "CA"));
        vm.prank(holder);
        vm.expectRevert(ILexChexBadge.LexChexBadge_SoulBound.selector);
        badge.transferFrom(holder, other, id);
    }

    // L9 — nothing burns a credential today, but the rule is checked rather than assumed: the record must
    // survive revocation, and the sweeps read the holder from ownership.
    function test_Audit_L9_BurnIsRejectedEvenWithAnEntryPoint() public {
        BurnableBadgeHarness harness = BurnableBadgeHarness(
            address(
                new ERC1967Proxy(
                    address(new BurnableBadgeHarness()),
                    abi.encodeCall(LeXcheXBadge.initialize, (address(new BorgAuth(owner))))
                )
            )
        );
        address holder = makeAddr("burnMe");
        Credential memory c;
        c.asserts = K_ACCREDITED;
        c.expiryDate = uint64(block.timestamp + 3650 days);
        vm.prank(owner);
        uint256 id = harness.mint(holder, c);

        vm.expectRevert(ILexChexBadge.LexChexBadge_SoulBound.selector);
        harness.burn(id);
        assertEq(harness.ownerOf(id), holder);
    }

    // ── Audit findings ────────────────────────────────────────────────────────

    // L4 — only an entity has beneficial owners, so a count on a person would inflate the §3(c)(1)(A) tally.
    // The type must be asserted on the same credential; setting the field alone does not make it official.
    function test_Audit_L4_BeneficialOwnerCountRequiresAnAttestedEntity() public {
        address to = makeAddr("boCountEntity");

        Credential memory individual = _cred(K_INVESTOR_TYPE | K_BO_COUNT);
        individual.investorType = InvestorType.INDIVIDUAL;
        individual.beneficialOwnerCount = 5;
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_BoCountRequiresEntity.selector);
        badge.mint(to, individual);

        Credential memory unattested = _cred(K_BO_COUNT); // ENTITY in the field, key not asserted
        unattested.investorType = InvestorType.ENTITY;
        unattested.beneficialOwnerCount = 5;
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_BoCountRequiresEntity.selector);
        badge.mint(to, unattested);

        Credential memory entity = _cred(K_INVESTOR_TYPE | K_BO_COUNT);
        entity.investorType = InvestorType.ENTITY;
        entity.beneficialOwnerCount = 5;
        _mint(to, entity);
        assertEq(uint256(_readBoCount(to)), 5);
    }

    // L7 — voided and expired records are kept for audit but are not credentials, so the read skips them and
    // reports none when only those are left.
    function test_Audit_L7_GetCredentialByOwnerSkipsRetiredRecords() public {
        address holder = makeAddr("firstIsVoided");
        uint256 revoked = _mint(holder, _kyc("US", "NY"));
        uint256 live = _mint(holder, _kyc("US", "CA"));
        vm.prank(owner);
        badge.void(revoked, "revoked");

        assertEq(badge.getCredentialByOwner(holder), live);
        assertEq(badge.getTokenIdsByOwner(holder).length, 2); // both retained for audit

        vm.prank(owner);
        badge.void(live, "revoked too");
        vm.expectRevert(ILexChexBadge.LexChexBadge_NoValidCredential.selector);
        badge.getCredentialByOwner(holder);

        vm.expectRevert(ILexChexBadge.LexChexBadge_NoValidCredential.selector);
        badge.getCredentialByOwner(makeAddr("neverCredentialed"));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Value-only reads. Every getter returns (value, expiry); the expiry half is asserted on its own in the
    // "reading horizon" section, so the rest of the suite reads through these.

    function _readInvestorType(address o) internal view returns (InvestorType v) {
        (v,) = badge.getInvestorType(o);
    }

    function _readUsState(address o) internal view returns (bytes2 v) {
        (v,) = badge.getUsState(o);
    }

    function _readBoCount(address o) internal view returns (uint32 v) {
        (v,) = badge.getEffectiveBeneficialOwnerCount(o);
    }

    function _readData(address o) internal view returns (bytes memory v) {
        (v,) = badge.getData(o);
    }

    function _readJurisdiction(address o) internal view returns (string memory v) {
        (v,) = badge.getInvestorJurisdiction(o);
    }

    function _readLookThrough(address o) internal view returns (string memory v) {
        (v,) = badge.getLookThroughJurisdiction(o);
    }

    function _cred(uint256 asserts) internal view returns (Credential memory c) {
        c.asserts = asserts;
        c.expiryDate = uint64(block.timestamp + 3650 days);
    }

    /// @dev Individual with a physical jurisdiction (and U.S. state when non-empty).
    function _kyc(string memory jurisdiction, bytes2 state) internal view returns (Credential memory c) {
        uint256 asserts = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
        if (state != bytes2(0)) asserts |= K_US_STATE;
        c = _cred(asserts);
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = jurisdiction;
        c.usState = state;
    }

    /// @dev Entity asserting a §3(c)(1)(A) look-through count.
    function _entityWithBoCount(uint32 count) internal view returns (Credential memory c) {
        c = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_BO_COUNT);
        c.investorType = InvestorType.ENTITY;
        c.investorJurisdiction = "US";
        c.beneficialOwnerCount = count;
    }

    function _jurisdiction(string memory j) internal view returns (Credential memory c) {
        c = _cred(K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION);
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = j;
    }

    function _mint(address to, Credential memory c) internal returns (uint256) {
        vm.prank(owner);
        return badge.mint(to, c);
    }

    /// @dev A second operator on the same badge. The grant is all it gets — deliberately no BorgAuth role, so
    /// these tests also pin that issuing needs none.
    function _delegateIssuer(string memory name, uint256 keys) internal returns (address issuer) {
        issuer = makeAddr(name);
        vm.prank(owner);
        badge.setIssuerKeys(issuer, keys);
    }

    function _mintAs(address issuer, address to, Credential memory c) internal returns (uint256) {
        vm.prank(issuer);
        return badge.mint(to, c);
    }

    /// @dev The one tier hook every query in this suite goes through; the question travels in the payload.
    function _tierHook() internal returns (address) {
        if (address(tierHook) == address(0)) tierHook = new TierQueryHook();
        return address(tierHook);
    }

    /// @dev The question `_tierHook` answers: whose seats, in which SPV, at which tier.
    function _tier(address spv, address issuer, bytes32 tierId) internal pure returns (bytes memory) {
        return abi.encode(spv, issuer, tierId);
    }

    /// @dev A scoped entitlement naming `spv`.
    function _scoped(uint256 scopeKey, address spv) internal view returns (Credential memory c) {
        c = _cred(scopeKey);
        c.scope = spv;
    }

    /// @dev A seat in `issuer`'s circle for `spv`, carrying `tier` as its programmable payload.
    function _seat(address issuer, address holder, address spv, bytes memory tier) internal returns (uint256) {
        Credential memory c = _cred(K_SYNDICATE | K_DATA);
        c.scope = spv;
        c.data = tier;
        return _mintAs(issuer, holder, c);
    }

    function _issuers(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    /// @dev Asserts `key` alone, leaving every value field empty, and expects the mint to be rejected.
    function _expectMissingValue(uint256 key) internal {
        address to = makeAddr("missingValue");
        Credential memory c = _cred(key);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ILexChexBadge.LexChexBadge_MissingValue.selector, key));
        badge.mint(to, c);
    }

    /// @dev Asserts scoped `keys` with no scope named, and expects the mint to be rejected.
    function _expectMissingScope(uint256 keys) internal {
        address to = makeAddr("missingScope");
        Credential memory c = _cred(keys);
        vm.prank(owner);
        vm.expectRevert(ILexChexBadge.LexChexBadge_MissingScope.selector);
        badge.mint(to, c);
    }
}

/// @notice Legion's tier schema, which lives here rather than in the badge: `Credential.data` is
/// abi.encode(bytes32 tierId). The hook owns the encoding, so the badge never learns what a tier is.
contract TierQueryHook is ICredentialQueryHook {
    function matchesCredential(address, uint256, Credential calldata cred, bytes calldata hookData)
        external
        pure
        returns (bool)
    {
        (address spv, address issuer, bytes32 tierId) = abi.decode(hookData, (address, address, bytes32));
        if ((cred.asserts & K_SYNDICATE) == 0 || cred.scope != spv || cred.issuer != issuer) return false;
        // The badge does not validate the payload's shape, so a malformed blob must read as "no match" rather
        // than revert the whole query.
        if (cred.data.length != 32) return false;
        return abi.decode(cred.data, (bytes32)) == tierId;
    }
}

/// @notice Accepts every credential it is shown, so a test can tell what the BADGE filtered out before the
/// hook ever ran.
contract AlwaysMatchHook is ICredentialQueryHook {
    function matchesCredential(address, uint256, Credential calldata, bytes calldata) external pure returns (bool) {
        return true;
    }
}

/// @notice Matches only if holder, token id and payload all arrived intact.
contract ArgCheckHook is ICredentialQueryHook {
    function matchesCredential(address owner, uint256 tokenId, Credential calldata cred, bytes calldata hookData)
        external
        pure
        returns (bool)
    {
        (address expectedOwner, uint256 expectedTokenId, string memory note) =
            abi.decode(hookData, (address, uint256, string));
        return owner == expectedOwner && tokenId == expectedTokenId && cred.issuanceDate != 0
            && keccak256(bytes(note)) == keccak256("carried through untouched");
    }
}

/// @notice A hook that fails, standing in for one that is buggy or hostile.
contract RevertingHook is ICredentialQueryHook {
    error HookFailed();

    function matchesCredential(address, uint256, Credential calldata, bytes calldata) external pure returns (bool) {
        revert HookFailed();
    }
}

/// @notice A BorgAuth role adapter that grants ADMIN_ROLE to one address, standing in for the external
/// authority (a Safe, a Hats tree) an operator can point BorgAuth at instead of storing the role.
contract AdminAdapter is IAuthAdapter {
    address immutable ADMIN;

    constructor(address admin) {
        ADMIN = admin;
    }

    function isAuthorized(address user) external view returns (uint256) {
        return user == ADMIN ? 98 : 0;
    }
}

/// @notice Stands in for an upgrade that adds a burn function, so the soulbound guard can be tested against
/// a move nothing currently makes.
contract BurnableBadgeHarness is LeXcheXBadge {
    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }
}

/// @notice The gas cliff `sweepTokens` exists to remove, exercised under a real gas cap. Kept in its own
/// contract because the assertions need a low-level call with a gas budget.
contract LeXcheXBadgeSweepGasTest is Test {
    address owner;
    LeXcheXBadge badge;

    function setUp() public {
        owner = makeAddr("owner");
        BorgAuth auth = new BorgAuth(owner);
        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth))))
            )
        );
    }

    // Scanning an oversized set does not fit and rolls back having evicted nothing, while a calldata-bounded
    // batch fits under the same cap and its progress persists — so the set is always drainable.
    function test_SweepTokens_MakesProgressWhereFullSweepRunsOut() public {
        address holder = makeAddr("cliff");
        for (uint256 i = 0; i < 60; i++) {
            Credential memory short;
            short.asserts = K_ACCREDITED;
            short.expiryDate = uint64(block.timestamp + 1 days);
            vm.prank(owner);
            badge.mint(holder, short);
        }
        vm.warp(block.timestamp + 2 days);
        uint256 before = badge.getActiveTokenIds(holder).length;
        assertEq(before, 60);

        uint256 cap = 200_000;
        (bool fullSwept,) = address(badge).call{gas: cap}(abi.encodeWithSelector(badge.sweep.selector, holder));
        assertFalse(fullSwept); // the whole-set scan runs out of gas
        assertEq(badge.getActiveTokenIds(holder).length, before); // all-or-nothing: nothing was evicted

        uint256[] memory active = badge.getActiveTokenIds(holder);
        uint256[] memory batch = new uint256[](5);
        for (uint256 i = 0; i < batch.length; i++) {
            batch[i] = active[i];
        }
        (bool batchSwept,) = address(badge).call{gas: cap}(abi.encodeWithSelector(badge.sweepTokens.selector, batch));
        assertTrue(batchSwept); // the bounded batch fits under the same cap
        assertEq(badge.getActiveTokenIds(holder).length, before - batch.length); // and its progress persisted
    }
}


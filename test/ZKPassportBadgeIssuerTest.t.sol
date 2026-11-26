// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {ZKPassportBadgeIssuer} from "../src/creds/ZKPassportBadgeIssuer.sol";
import {NationalityPolicy} from "../src/libs/policies/NationalityPolicy.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {
    ILexChexBadge,
    ALL_KEYS,
    K_BAD_ACTOR_CLEAR,
    K_INVESTOR_TYPE,
    K_NATIONALITY_OUT,
    K_NON_US,
    K_SPV_WHITELIST
} from "../src/interfaces/ILexChexBadge.sol";
import {
    BoundData,
    IZKPassportHelper,
    IZKPassportVerifier,
    ProofVerificationData,
    ProofVerificationParams,
    ServiceConfig
} from "../src/interfaces/IZKPassportVerifier.sol";

// Mock ZKPassport verifier/helper — the one legitimate mock (external protocol, not in this repo).
// Encoding conventions mirror NonUSNationalityConditionTest and are mock-only.
contract MockZKPassportHelper is IZKPassportHelper {
    bool public shouldRejectNationality;
    bool public shouldRevertSanctions;

    error SanctionsCheckFailed();

    function setShouldRejectNationality(bool _v) external { shouldRejectNationality = _v; }
    function setShouldRevertSanctions(bool _v) external { shouldRevertSanctions = _v; }

    function verifyScopes(bytes32[] calldata publicInputs, string calldata domain, string calldata scope)
        external
        pure
        returns (bool)
    {
        return publicInputs[0] == keccak256(bytes(domain)) && publicInputs[1] == keccak256(bytes(scope));
    }

    function getBoundData(bytes calldata committedInputs) external pure returns (BoundData memory) {
        return abi.decode(committedInputs, (BoundData));
    }

    function getProofTimestamp(bytes32[] calldata publicInputs) external pure returns (uint256) {
        return uint256(publicInputs[2]);
    }

    function isNationalityOut(string[] memory, bytes calldata) external view returns (bool) {
        return !shouldRejectNationality;
    }

    function enforceSanctionsRoot(uint256, bool, bytes calldata) external view {
        if (shouldRevertSanctions) revert SanctionsCheckFailed();
    }
}

contract MockZKPassportVerifier is IZKPassportVerifier {
    bool public shouldVerify = true;
    bool public shouldReturnZeroHelper;
    IZKPassportHelper public helperContract;
    bytes32 public uniqueId = keccak256("passport-A");

    function setHelper(address _h) external { helperContract = IZKPassportHelper(_h); }
    function setShouldVerify(bool _v) external { shouldVerify = _v; }
    function setShouldReturnZeroHelper(bool _v) external { shouldReturnZeroHelper = _v; }
    function setUniqueId(bytes32 _id) external { uniqueId = _id; }

    function verify(ProofVerificationParams calldata) external returns (bool, bytes32, IZKPassportHelper) {
        if (!shouldVerify) return (false, bytes32(0), IZKPassportHelper(address(0)));
        if (shouldReturnZeroHelper) return (true, uniqueId, IZKPassportHelper(address(0)));
        return (true, uniqueId, helperContract);
    }
}

/// @notice Behavioural coverage for proof-gated identity credentialing: turning a ZKPassport proof over a
/// government document into a soulbound LeXcheXBadge credential, instead of an operator vouching by trust. The
/// suite guards the legal / economic intent, not the mechanics:
///
///  A. Self-sovereign onboarding. A real person credentials themselves from their own passport; the credential is
///     time-bounded so standing must be re-attested.
///  B. Identity vests in the person, not the submitter. The credential accrues to the wallet the person proved
///     control of; a relayer may pay gas but can neither capture nor redirect it.
///  C. No personhood notary. A person with several wallets is simply several holders — the issuer never links or
///     collapses wallets to one human, exactly as any non-ZKPassport wallet is treated.
///  D. You receive only what you prove. The contract mints a fact-set only if the check for each fact is correct.
///     The nationality fact records the countries that the proof showed. A new proof replaces the live credential
///     (supersede). A holder can remove their own credential with void().
///  E. A refusal follows the person, not the wallet. Someone sanctioned, or who can't prove their nationality is
///     outside the excluded list, is refused every time — a fresh wallet doesn't help, because the check is against
///     the passport proof, not the address. Nor can a proof made for another app, chain, or moment be reused here.
///  F. The issuer shows who made the attestation. A separate key does not. A ZK proof and an operator attestation
///     of the same fact use one fact-key. A condition that accepts only one of them filters on the issuer. Two
///     limits control what a proof can assert: this contract mints only the facts that it can check, and only the
///     facts that the badge granted to it. Thus a proof never mints an operator attestation.
///  G. Governance owns the wiring. Only admins change verifier/badge; only the owner can evolve the contract.
///     Rewiring never hands one holder's standing to another.
///
/// Scenario matrix (topic → intent it protects → expected):
///
///  Issuance, value-fact & recipient binding (A, B, D)
///   • HappyPath_NationalityOut ........... eligible person gets a credential recording the proven exclusion set .. issue, list readable
///   • RecipientIsBoundSender ............. credential vests in the identity-holder, never the gas-paying relayer .. issue to holder
///   • CombinedFacts_OneCredential ........ one credential can carry several facts, satisfying an AND-check ........ issue, single token
///
///  Membership read (D)
///   • Policy_Excludes .................... NationalityPolicy finds country X in the list that the proof showed ... true / false
///
///  Kinds & wallets (C)
///   • DifferentFacts_SameWallet .......... a wallet may hold distinct facts (nationality-out + bad-actor-clear) .. both issue
///   • DifferentWallet_SamePassport ....... wallets are independent holders; never collapsed to one human ......... both issue, unlinked
///
///  Lifecycle — renewal & revocation (A, D)
///   • Renewal_Supersedes_NoDuplicate ..... re-proving the same fact-set replaces the live credential ............. one live credential
///   • Renewal_ReplacesExclusionList ...... a renewal replaces the proven country set; it never accumulates ....... old country no longer excluded
///   • Renewal_WithDifferentPassport ...... standing is wallet-scoped, so a new document just re-anchors evidence . one live credential
///   • OverlappingFactSets_Independently .. a credential is tracked per fact-SET, so overlapping sets coexist ..... both live
///   • Expired_ThenResubmit_FreshMint ..... nothing live to replace, so a lapsed credential is not superseded ..... new credential
///   • Void_SelfService ................... a holder can drop their own credential without an admin ............... void
///   • Void_ThenReMint .................... a voided credential does not block a later fresh proof ................ new credential
///   • AdminVoid_RevokesAnyHoldersCredential ... an admin revokes anyone's, with a reason, and the floor moves ... void
///   • AdminVoid_ProofMadeAfterwards ...... a revocation is no ban: re-prove on today's facts ................. new credential
///   • AdminVoid_Unauthorized / EmptyReason / NoLiveCredential ... only an admin, always with a reason, and only
///     against something live .................................................................................. refuse
///   • Void_AnotherHoldersCredential / Twice / AfterAdminVoidedOnBadge / UnmintedFactKeySpaceIsEmpty ... only your own
///     live credential is droppable, and liveness is re-checked on the badge, not assumed from bookkeeping ....... refuse
///   • CurrentTokenOf_ReportsIssuance ..... the issuer's tracking is not a liveness answer ....................... exists, not valid
///   • BadgeRotation_SelfVoid / Renewal / TrackingIsPerBadge ... a saved id only means anything on the badge that
///     minted it, so swapping badges never lets one holder touch another's ................. refuse / fresh mint
///   • ValidityPeriod_WithinCap ........... a period inside the cap is honoured as submitted .................... issue
///   • ValidityPeriod_ExceedsCap / AbsurdValues / FutureProofTimestamp ... the submitted validity period is not
///     covered by the proof, so the cap is what keeps a credential re-attestable (see the fork suite) .......... refuse
///   • UpdateMaxValidityPeriod_AdminCanRetune / Unauthorized / Zero / Initialize_Zero ... the cap is admin-tunable
///     and never absent .......................................................................................... issue / refuse
///
///  Proof reuse — a spent proof is never replayable (E)
///   • Replay_AfterSelfVoid ............... a bystander can't undo the holder's own drop with old calldata ..... refuse
///   • Replay_AfterAdminVoidedOnBadge ..... nor undo a compliance revocation ................................... refuse
///   • Replay_CannotExtendLiveCredential .. nor stretch a live credential by re-declaring a longer period ...... refuse
///   • OlderProof_AfterNewerOneUsed ....... standing only moves forward, so an older proof is refused too ...... refuse
///   • ProofMadeBeforeSelfVoid ............ nor undo a drop with a proof made before it but never submitted ... refuse
///   • Void_FloorAppliesToTheWalletsOtherFactSets ... the drop's floor is per wallet, covering every fact-set .. refuse
///   • Void_ProofMadeAfterwards ........... but the floor is no lockout: anything proven after the drop mints .. new credential
///
///  Eligibility gating — a refusal follows the person (E)
///   • NationalityRejected ................ a holder who can't prove the exclusion is refused .................... refuse
///   • SanctionsFail ...................... sanctioned persons refused; upstream reason surfaced verbatim ........ refuse
///   • InvalidProof / InvalidScope / BoundChainIdMismatch / ProofExpired ... only an authentic, in-scope, in-time, on-chain proof qualifies ... refuse
///
///  Provenance, inputs & governance (F, G)
///   • Provenance_IssuerDistinguishesTheBasis ... one fact-key, two types of attestation. A filter on the issuer
///     separates the ZK proof from the operator attestation, for the status fact and the country list ... ZK / operator
///   • Mint_RejectsUncheckedKey / ZeroFactKeys .. the contract never mints a fact that it cannot check .......... refuse
///   • Mint_*SneakedIn (an unchecked key with a checked key, a scope key, a VALUE key, an undefined bit,
///     EveryKeyGrab) ............................ a legitimate key does not let a different key through. The
///     contract refuses the full request, mints no part of it, and keeps no record of it ....................... refuse
///   • Mint_BeyondTheBadgeGrant / WithoutAnyGrant ... the badge grant limits the contract independently of the
///     contract's own checks. A smaller grant, or no grant, stops the mint at the badge ........................ refuse
///   • Mint_ZeroFactKeysScreenedBeforeProof ..... the contract refuses an empty fact-set before the proof ....... refuse
///   • Mint_*ViaNationalityOverload ............. the second function has the same check ........................ refuse
///   • NationalityKey_WithoutList / ListWithoutKey / CombinedFacts_WithoutList ... the country list is required
///     iff the nationality fact is asked, combined fact-sets included ............................................ refuse
///   • UpdateVerifier_Unauthorized / Upgrade_Unauthorized / Initialize_ZeroBadge ... only the right role acts ..... refuse
contract ZKPassportBadgeIssuerTest is Test {
    string internal constant DOMAIN = "app.example";
    string internal constant SCOPE = "identity";
    uint256 internal constant MAX_VALIDITY = 365 days;

    uint256 internal constant FK_NAT_OUT = K_NATIONALITY_OUT;
    uint256 internal constant FK_BAD_ACTOR = K_BAD_ACTOR_CLEAR;
    uint256 internal constant FK_BOTH = K_NATIONALITY_OUT | K_BAD_ACTOR_CLEAR;
    // The facts that the badge lets this contract assert. A ZKPassport proof can show these facts.
    uint256 internal constant GRANT = K_NATIONALITY_OUT | K_BAD_ACTOR_CLEAR;

    BorgAuth internal auth;
    LeXcheXBadge internal badge;
    ZKPassportBadgeIssuer internal issuer;
    MockZKPassportHelper internal helper;
    MockZKPassportVerifier internal verifier;

    address internal alice = address(0xA11CE);
    address internal aliceWallet2 = address(0xA11CE2);
    address internal bob = address(0xB0B);
    address internal relayer = address(0xCAFE);

    function setUp() public {
        auth = new BorgAuth(address(this));

        badge = LeXcheXBadge(
            address(new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth)))))
        );

        helper = new MockZKPassportHelper();
        verifier = new MockZKPassportVerifier();
        verifier.setHelper(address(helper));

        issuer = ZKPassportBadgeIssuer(
            address(
                new ERC1967Proxy(
                    address(new ZKPassportBadgeIssuer()),
                    abi.encodeCall(
                        ZKPassportBadgeIssuer.initialize,
                        (address(auth), address(badge), DOMAIN, SCOPE, address(verifier), MAX_VALIDITY)
                    )
                )
            )
        );

        // The contract mints on the badge with a grant for each key. It has no BorgAuth role. Thus it receives
        // none of the admin control of the deployment that a role gives.
        badge.setIssuerKeys(address(issuer), GRANT);
    }

    // ── Happy path, value-fact & recipient binding ───────────────────────────

    function test_Mint_HappyPath_NationalityOut_RecordsExclusionList() public {
        vm.warp(1000);
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        assertTrue(badge.isValid(tokenId));
        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
        assertFalse(badge.hasValidCredentialOf(alice, K_NON_US), "a fact that was not proved is not established");

        (string[] memory list, uint64 expiry) = badge.getNationalityOut(alice);
        assertEq(list.length, 1);
        assertEq(list[0], "USA");
        assertEq(uint256(expiry), 1000 + 1 days);
        assertEq(badge.getCredential(tokenId).evidenceHash, verifier.uniqueId(), "uid retained only as audit anchor");
    }

    function test_Mint_RecipientIsBoundSender_NotMsgSender() public {
        vm.prank(relayer);
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));
        assertEq(badge.getCredentialByOwner(alice), tokenId);
        assertEq(badge.balanceOf(relayer), 0);
    }

    function test_CombinedFacts_OneCredential_SatisfiesAndCheck() public {
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_BOTH, _excluded("USA"));

        assertEq(badge.getActiveTokenIds(alice).length, 1, "one credential carries both facts");
        assertTrue(badge.hasValidCredentialOf(alice, FK_BOTH));
        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
        assertTrue(badge.hasValidCredentialOf(alice, K_BAD_ACTOR_CLEAR));
    }

    // ── Membership read via the policy library ───────────────────────────────

    function test_Policy_Excludes_MembershipCheck() public {
        string[] memory codes = new string[](2);
        codes[0] = "USA";
        codes[1] = "IRN";
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, codes);

        (bool exUsa,) = NationalityPolicy.excludes(badge, alice, "USA");
        (bool exIrn,) = NationalityPolicy.excludes(badge, alice, "IRN");
        (bool exCan,) = NationalityPolicy.excludes(badge, alice, "CAN");
        assertTrue(exUsa);
        assertTrue(exIrn);
        assertFalse(exCan, "a country not in the proven set is not excluded");

        (bool exOther,) = NationalityPolicy.excludes(badge, aliceWallet2, "USA");
        assertFalse(exOther, "a wallet with no credential excludes nothing");
    }

    // ── Kinds & wallets (no personhood notary) ───────────────────────────────

    // A second fact-set needs a second proof: one proof is good for one mint.
    function test_DifferentFacts_SameWallet_MintsSeparateCredentials() public {
        vm.warp(1000);
        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.warp(1100);
        issuer.submitProofAndMint(_params(alice, 1100, 1 days), FK_BAD_ACTOR);

        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
        assertTrue(badge.hasValidCredentialOf(alice, K_BAD_ACTOR_CLEAR));
        assertEq(badge.getActiveTokenIds(alice).length, 2);
    }

    // Also pins that proof reuse is judged per wallet, not per passport: two proofs made at the same moment from
    // one document both stand, because neither wallet has spent a proof before.
    function test_SamePassport_SameFacts_DifferentWallet_IndependentHolders() public {
        uint256 id1 = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));
        uint256 id2 = issuer.submitProofAndMint(_params(aliceWallet2, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        assertTrue(id1 != id2);
        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
        assertTrue(badge.hasValidCredentialOf(aliceWallet2, K_NATIONALITY_OUT));
    }

    // ── Lifecycle: renewal supersedes, void does not block re-mint ───────────

    function test_Renewal_Supersedes_NoDuplicate() public {
        vm.warp(1000);
        uint256 first = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.warp(1000 + 100);
        uint256 renewed = issuer.submitProofAndMint(_params(alice, 1000 + 100, 1 days), FK_NAT_OUT, _excluded("USA"));

        assertTrue(renewed != first, "supersede issues a new immutable credential");
        assertFalse(badge.isValid(first), "old credential is voided");
        assertTrue(badge.isValid(renewed));
        assertEq(badge.getActiveTokenIds(alice).length, 1, "no stacking of the same fact-set");
        assertEq(uint256(badge.getCredential(renewed).expiryDate), 1000 + 100 + 1 days);
    }

    function test_Void_SelfService_HolderDropsOwnCredential() public {
        vm.warp(1000);
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));
        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));

        vm.prank(alice);
        issuer.void(FK_NAT_OUT);
        assertFalse(badge.isValid(tokenId));
        assertFalse(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));

        // Coming back is the holder's own call, and it takes a new proof.
        vm.warp(1100);
        uint256 fresh = issuer.submitProofAndMint(_params(alice, 1100, 1 days), FK_NAT_OUT, _excluded("USA"));
        assertTrue(fresh != tokenId);
        assertTrue(badge.isValid(fresh));
    }

    function test_Void_ThenReMint_IssuesFresh() public {
        vm.warp(1000);
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        badge.void(tokenId, "compliance review");
        assertFalse(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));

        vm.warp(1100);
        uint256 fresh = issuer.submitProofAndMint(_params(alice, 1100, 1 days), FK_NAT_OUT, _excluded("USA"));
        assertTrue(fresh != tokenId);
        assertTrue(badge.isValid(fresh));
    }

    function test_Revert_Void_NoLiveCredential() public {
        vm.prank(alice);
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(FK_NAT_OUT);
    }

    // void() drops your own standing and nobody else's — otherwise anyone could strip a holder's eligibility.
    function test_Revert_Void_AnotherHoldersCredential() public {
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.prank(aliceWallet2);
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(FK_NAT_OUT);

        assertTrue(badge.isValid(tokenId), "a stranger's call leaves the credential standing");
        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
    }

    function test_Revert_Void_Twice() public {
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.startPrank(alice);
        issuer.void(FK_NAT_OUT);
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(FK_NAT_OUT);
        vm.stopPrank();
    }

    // Already voided on the badge by an admin: the issuer still tracks the id, so void() must re-check liveness
    // rather than trust its own bookkeeping.
    function test_Revert_Void_AfterAdminVoidedOnBadge() public {
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));
        badge.void(tokenId, "compliance review");

        vm.prank(alice);
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(FK_NAT_OUT);
    }

    // Revoking through the issuer is what an admin should reach for: it drops the credential AND sets the floor,
    // so the holder can't put it straight back with a proof made before the revoke.
    function test_AdminVoid_RevokesAnyHoldersCredential_AndSetsFloor() public {
        vm.warp(1000);
        string[] memory list = _excluded("USA");
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, list);
        ProofVerificationParams memory unsubmitted = _params(alice, 1500, 1 days);

        vm.warp(2000);
        issuer.void(FK_NAT_OUT, alice, "sanctions hit");

        assertFalse(badge.isValid(tokenId));
        assertFalse(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
        assertEq(badge.getCredential(tokenId).voided, "sanctions hit", "the admin's reason is what the badge records");
        assertEq(issuer.lastProofTimestampOf(alice), 2000, "the revoke moved the floor to now");

        (, bool exists) = issuer.currentTokenOf(FK_NAT_OUT, alice);
        assertFalse(exists, "no longer tracked");

        vm.prank(relayer);
        vm.expectRevert(ZKPassportBadgeIssuer.StaleProof.selector);
        issuer.submitProofAndMint(unsubmitted, FK_NAT_OUT, list);
    }

    // The floor is not a ban: the holder can prove themselves again on today's facts.
    function test_AdminVoid_ProofMadeAfterwards_StillMints() public {
        vm.warp(1000);
        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.warp(2000);
        issuer.void(FK_NAT_OUT, alice, "compliance review");

        uint256 fresh = issuer.submitProofAndMint(_params(alice, 2001, 1 days), FK_NAT_OUT, _excluded("USA"));
        assertTrue(badge.isValid(fresh));
    }

    // Only an admin revokes someone else's — otherwise anyone could strip a holder's eligibility.
    function test_Revert_AdminVoid_Unauthorized() public {
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(98), bob));
        issuer.void(FK_NAT_OUT, alice, "not yours to revoke");

        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
    }

    // The badge refuses an unexplained void, so a revocation always leaves a reason on the record.
    function test_Revert_AdminVoid_EmptyReason() public {
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.expectRevert(ILexChexBadge.LexChexBadge_MissingVoidReason.selector);
        issuer.void(FK_NAT_OUT, alice, "");
    }

    function test_Revert_AdminVoid_NoLiveCredential() public {
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(FK_NAT_OUT, alice, "nothing to revoke");
    }

    // void() accepts a fact-set and does not examine it. The contract can void nothing in a key space where it
    // minted no credential, because only a mint records a credential in the register.
    function test_Revert_Void_UnmintedFactKeySpaceIsEmpty() public {
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.startPrank(alice);
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(K_NON_US);
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(0);
        vm.stopPrank();
    }

    // A live credential is tracked per FACT-SET, not per fact. Asking for the nationality fact alone and again as
    // part of a combined set yields two credentials that both answer it, and renewing one leaves the other alone.
    function test_OverlappingFactSets_TrackedIndependently() public {
        vm.warp(1000);
        uint256 natOnly = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.warp(1100);
        uint256 both = issuer.submitProofAndMint(_params(alice, 1100, 1 days), FK_BOTH, _excluded("IRN"));

        assertTrue(badge.isValid(natOnly), "the combined set does not supersede the narrower one");
        assertTrue(badge.isValid(both));
        assertEq(badge.getActiveTokenIds(alice).length, 2);

        // Dropping one fact-set leaves the fact standing on the other.
        vm.prank(alice);
        issuer.void(FK_NAT_OUT);
        assertFalse(badge.isValid(natOnly));
        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT), "still answered by the combined credential");
    }

    // Renewal REPLACES the exclusion set; it does not accumulate. A country proven excluded last time stops being
    // excluded unless it is proven again.
    function test_Renewal_ReplacesExclusionList_DoesNotAccumulate() public {
        vm.warp(1000);
        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));
        (bool usaBefore,) = NationalityPolicy.excludes(badge, alice, "USA");
        assertTrue(usaBefore);

        vm.warp(1100);
        issuer.submitProofAndMint(_params(alice, 1100, 1 days), FK_NAT_OUT, _excluded("IRN"));

        (bool usaAfter,) = NationalityPolicy.excludes(badge, alice, "USA");
        (bool irnAfter,) = NationalityPolicy.excludes(badge, alice, "IRN");
        assertFalse(usaAfter, "the superseded list is gone, not merged");
        assertTrue(irnAfter);
    }

    // An expired credential is not superseded — there is nothing live to replace, so the holder simply gets a
    // fresh one and the lapsed record stays on-chain for audit.
    function test_Expired_ThenResubmit_FreshMint() public {
        vm.warp(1000);
        uint256 first = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.warp(1000 + 1 days + 1);
        assertFalse(badge.isValid(first), "lapsed");

        uint256 fresh = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));
        assertTrue(fresh != first);
        assertTrue(badge.isValid(fresh));

        (uint256 tracked, bool exists) = issuer.currentTokenOf(FK_NAT_OUT, alice);
        assertTrue(exists);
        assertEq(tracked, fresh, "tracking moves to the live credential");
    }

    // Standing is wallet-scoped, not passport-scoped: re-proving with a different document renews the same
    // credential slot and re-anchors the audit trail to the new proof.
    function test_Renewal_WithDifferentPassport_SwapsEvidenceAnchor() public {
        vm.warp(1000);
        uint256 first = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        verifier.setUniqueId(keccak256("passport-B"));
        vm.warp(1100);
        uint256 renewed = issuer.submitProofAndMint(_params(alice, 1100, 1 days), FK_NAT_OUT, _excluded("USA"));

        assertFalse(badge.isValid(first));
        assertEq(badge.getCredential(renewed).evidenceHash, keccak256("passport-B"));
        assertEq(badge.getActiveTokenIds(alice).length, 1);
    }

    // `exists` reports only that this issuer minted here — it is not a liveness answer, exactly as documented.
    function test_CurrentTokenOf_ReportsIssuance_NotLiveness() public {
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));
        badge.void(tokenId, "compliance review");

        (uint256 tracked, bool exists) = issuer.currentTokenOf(FK_NAT_OUT, alice);
        assertTrue(exists, "still tracked");
        assertEq(tracked, tokenId);
        assertFalse(badge.isValid(tracked), "but not live: callers must ask the badge");
    }

    // ── Proof reuse ──────────────────────────────────────────────────────────

    // Dropping a credential has to mean something. The proof verifies just as well the second time and anyone may
    // submit, so without a check a bystander could replay the holder's own calldata and put the credential back.
    function test_Revert_Replay_AfterSelfVoid() public {
        vm.warp(1000);
        ProofVerificationParams memory p = _params(alice, 1000, 1 days);
        string[] memory list = _excluded("USA");
        issuer.submitProofAndMint(p, FK_NAT_OUT, list);

        vm.prank(alice);
        issuer.void(FK_NAT_OUT);

        vm.warp(1100);
        vm.prank(relayer);
        vm.expectRevert(ZKPassportBadgeIssuer.StaleProof.selector);
        issuer.submitProofAndMint(p, FK_NAT_OUT, list);

        assertFalse(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT), "the drop stands");
    }

    // The same replay against an admin's revocation, which matters more: the sanctions check is anchored to the
    // proof's own timestamp, so an old proof re-passes it. A fresh proof is what gets judged on today's list.
    function test_Revert_Replay_AfterAdminVoidedOnBadge() public {
        vm.warp(1000);
        ProofVerificationParams memory p = _params(alice, 1000, 1 days);
        string[] memory list = _excluded("USA");
        uint256 tokenId = issuer.submitProofAndMint(p, FK_NAT_OUT, list);

        badge.void(tokenId, "sanctions hit");

        vm.warp(1100);
        vm.prank(relayer);
        vm.expectRevert(ZKPassportBadgeIssuer.StaleProof.selector);
        issuer.submitProofAndMint(p, FK_NAT_OUT, list);

        assertFalse(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT), "the revocation stands");
    }

    // Nothing to undo here — the credential is live. The proof doesn't cover the validity period, so a replayer
    // could otherwise re-submit it at the cap and hand the holder far longer standing than they asked for.
    function test_Revert_Replay_CannotExtendLiveCredential() public {
        vm.warp(1000);
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        ProofVerificationParams memory stretched = _params(alice, 1000, MAX_VALIDITY);
        string[] memory list = _excluded("USA");

        vm.warp(1100);
        vm.prank(relayer);
        vm.expectRevert(ZKPassportBadgeIssuer.StaleProof.selector);
        issuer.submitProofAndMint(stretched, FK_NAT_OUT, list);

        assertEq(uint256(badge.getCredential(tokenId).expiryDate), 1000 + 1 days, "lifetime unchanged");
    }

    // The timestamp check alone only stops proofs older than the last one SUBMITTED. A proof the holder made but
    // never submitted sits above that mark, so without a floor at void time it would still put the credential
    // back — and its checks would be judged at its own older timestamp. void() raises the floor to now.
    function test_Revert_ProofMadeBeforeSelfVoid_CannotUndoIt() public {
        vm.warp(1000);
        string[] memory list = _excluded("USA");
        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, list);

        // Made while the credential stood, never submitted: newer than the spent proof, older than the drop.
        ProofVerificationParams memory unsubmitted = _params(alice, 1500, 1 days);

        vm.warp(2000);
        vm.prank(alice);
        issuer.void(FK_NAT_OUT);
        assertEq(issuer.lastProofTimestampOf(alice), 2000, "the drop moved the floor to now");

        // Not expiry doing the work: 1500 + 1 days is still in the future.
        vm.prank(relayer);
        vm.expectRevert(ZKPassportBadgeIssuer.StaleProof.selector);
        issuer.submitProofAndMint(unsubmitted, FK_NAT_OUT, list);

        assertFalse(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT), "the drop stands");
    }

    // The floor is not a lockout — anything proven after the drop is fine.
    function test_Void_ProofMadeAfterwards_StillMints() public {
        vm.warp(1000);
        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));

        vm.warp(2000);
        vm.prank(alice);
        issuer.void(FK_NAT_OUT);

        uint256 fresh = issuer.submitProofAndMint(_params(alice, 2001, 1 days), FK_NAT_OUT, _excluded("USA"));
        assertTrue(badge.isValid(fresh));
        assertTrue(badge.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
    }

    // The floor is per WALLET, not per fact-set: dropping one fact-set also refuses older proofs for the others.
    // Coarser than it needs to be, but it reuses the one mark a wallet already has.
    function test_Void_FloorAppliesToTheWalletsOtherFactSets() public {
        vm.warp(1000);
        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, _excluded("USA"));
        ProofVerificationParams memory unsubmitted = _params(alice, 1500, 1 days);

        vm.warp(2000);
        vm.prank(alice);
        issuer.void(FK_NAT_OUT);

        vm.expectRevert(ZKPassportBadgeIssuer.StaleProof.selector);
        issuer.submitProofAndMint(unsubmitted, FK_BAD_ACTOR);
    }

    // Not only the identical call: a wallet's proofs move forward, so any proof older than the one already spent
    // is refused — including a genuine one that was never submitted.
    function test_Revert_OlderProof_AfterNewerOneUsed() public {
        vm.warp(1000);
        ProofVerificationParams memory older = _params(alice, 900, 1 days);
        string[] memory list = _excluded("USA");

        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_NAT_OUT, list);
        assertEq(issuer.lastProofTimestampOf(alice), 1000);

        vm.expectRevert(ZKPassportBadgeIssuer.StaleProof.selector);
        issuer.submitProofAndMint(older, FK_NAT_OUT, list);
    }

    // ── Badge rotation: tracked ids belong to the badge that issued them ─────

    // Ids restart at 0 on each badge, so alice's saved id is bob's credential on the new one. She can't void it.
    function test_BadgeRotation_SelfVoid_CannotReachAnotherHoldersCredential() public {
        (LeXcheXBadge other, uint256 collidingId) = _rotateOntoCollidingBadge();

        vm.prank(alice);
        vm.expectRevert(ZKPassportBadgeIssuer.NoLiveCredential.selector);
        issuer.void(FK_NAT_OUT);

        assertTrue(other.isValid(collidingId), "the stranger's credential is untouched");
    }

    // Same collision on the renewal path: nothing is tracked on the new badge, so it mints alice a fresh one
    // instead of taking over bob's token.
    function test_BadgeRotation_Renewal_FreshMintsToTheProvenWallet() public {
        (LeXcheXBadge other, uint256 collidingId) = _rotateOntoCollidingBadge();

        // Rotating badges is no excuse to reuse the proof spent on the old one.
        vm.warp(block.timestamp + 100);
        uint256 minted = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        assertTrue(other.isValid(collidingId), "the stranger's credential is untouched");
        assertEq(other.ownerOf(minted), alice, "the credential vests in the proven wallet");
        assertTrue(other.hasValidCredentialOf(alice, K_NATIONALITY_OUT));
    }

    // Rotating away doesn't wipe the old badge's records, so rotating back finds them intact.
    function test_BadgeRotation_TrackingIsPerBadge_AndSurvivesRotatingBack() public {
        (, uint256 collidingId) = _rotateOntoCollidingBadge();

        (, bool existsOnOther) = issuer.currentTokenOf(FK_NAT_OUT, alice);
        assertFalse(existsOnOther, "nothing was issued to alice on the new badge");

        issuer.updateBadge(address(badge));
        (uint256 tracked, bool exists) = issuer.currentTokenOf(FK_NAT_OUT, alice);
        assertTrue(exists);
        assertEq(tracked, collidingId, "the original badge's record is intact");
    }

    /// @dev Give alice a credential, then point the issuer at a new badge where bob already holds that same id.
    function _rotateOntoCollidingBadge() internal returns (LeXcheXBadge other, uint256 collidingId) {
        uint256 aliceId = issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));

        other = LeXcheXBadge(
            address(new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth)))))
        );

        Credential memory cred;
        cred.asserts = K_NON_US; // a different credential from an operator. It has no relation to ZKPassport.
        cred.expiryDate = uint64(block.timestamp + 30 days);
        collidingId = other.mint(bob, cred);
        assertEq(collidingId, aliceId, "the ids collide, which is the whole hazard");

        other.setIssuerKeys(address(issuer), GRANT); // the new badge gives the same grant as the first badge
        issuer.updateBadge(address(other));
    }

    // ── Eligibility gating ───────────────────────────────────────────────────

    function test_Revert_NationalityRejected() public {
        helper.setShouldRejectNationality(true);
        vm.expectRevert(ZKPassportBadgeIssuer.NationalityNotExcluded.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));
    }

    function test_Revert_SanctionsFail_SurfacedVerbatim() public {
        helper.setShouldRevertSanctions(true);
        vm.expectRevert(MockZKPassportHelper.SanctionsCheckFailed.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_BAD_ACTOR);
    }

    function test_Revert_InvalidProof_VerificationFailed() public {
        verifier.setShouldVerify(false);
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidProof.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_BAD_ACTOR);
    }

    function test_Revert_InvalidProof_ZeroHelper() public {
        verifier.setShouldReturnZeroHelper(true);
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidProof.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_BAD_ACTOR);
    }

    function test_Revert_InvalidScope() public {
        ProofVerificationParams memory p = _params(alice, block.timestamp, 1 days);
        p.proofVerificationData.publicInputs[1] = keccak256("wrong-scope");
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidScope.selector);
        issuer.submitProofAndMint(p, FK_BAD_ACTOR);
    }

    function test_Revert_BoundChainIdMismatch() public {
        ProofVerificationParams memory p = _params(alice, block.timestamp, 1 days);
        p.committedInputs = abi.encode(BoundData({senderAddress: alice, chainId: block.chainid + 1, customData: ""}));
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidBoundChainId.selector);
        issuer.submitProofAndMint(p, FK_BAD_ACTOR);
    }

    function test_Revert_ProofExpired() public {
        vm.warp(3 days);
        vm.expectRevert(ZKPassportBadgeIssuer.ProofExpired.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp - 2 days, 1 days), FK_BAD_ACTOR);
    }

    // The submitter names the validity period and the proof does not cover it, so the cap is what keeps a
    // credential re-attestable. A period within the cap is honoured as asked.
    function test_ValidityPeriod_WithinCap_SetsLifetime() public {
        vm.warp(1000);
        uint256 tokenId = issuer.submitProofAndMint(_params(alice, 1000, MAX_VALIDITY), FK_BAD_ACTOR);
        assertEq(uint256(badge.getCredential(tokenId).expiryDate), 1000 + MAX_VALIDITY);
    }

    function test_Revert_ValidityPeriod_ExceedsCap() public {
        vm.warp(1000);
        vm.expectRevert(ZKPassportBadgeIssuer.MaxValidityPeriodExceeded.selector);
        issuer.submitProofAndMint(_params(alice, 1000, MAX_VALIDITY + 1), FK_BAD_ACTOR);
    }

    // A period large enough to overflow the addition, or to wrap the badge's uint64 expiry, is refused by the cap
    // before the arithmetic runs — so it fails as an over-long request, not as a panic.
    function test_Revert_ValidityPeriod_AbsurdValuesHitTheCapFirst() public {
        vm.warp(1000);
        ProofVerificationParams memory wraps = _params(alice, 1000, 1 << 64);
        vm.expectRevert(ZKPassportBadgeIssuer.MaxValidityPeriodExceeded.selector);
        issuer.submitProofAndMint(wraps, FK_BAD_ACTOR);

        ProofVerificationParams memory overflows = _params(alice, 1000, type(uint256).max);
        vm.expectRevert(ZKPassportBadgeIssuer.MaxValidityPeriodExceeded.selector);
        issuer.submitProofAndMint(overflows, FK_BAD_ACTOR);
    }

    // A proof timestamp in the future would push the expiry past the cap even with an in-range period, so the
    // resulting date is bounded too.
    function test_Revert_FutureProofTimestamp_PushesExpiryPastCap() public {
        vm.warp(1000);
        vm.expectRevert(ZKPassportBadgeIssuer.MaxValidityPeriodExceeded.selector);
        issuer.submitProofAndMint(_params(alice, 1000 + 10 days, MAX_VALIDITY), FK_BAD_ACTOR);
    }

    function test_UpdateMaxValidityPeriod_AdminCanRetune() public {
        vm.warp(1000);
        issuer.updateMaxValidityPeriod(2 days);

        vm.expectRevert(ZKPassportBadgeIssuer.MaxValidityPeriodExceeded.selector);
        issuer.submitProofAndMint(_params(alice, 1000, 3 days), FK_BAD_ACTOR);

        uint256 tokenId = issuer.submitProofAndMint(_params(alice, 1000, 2 days), FK_BAD_ACTOR);
        assertEq(uint256(badge.getCredential(tokenId).expiryDate), 1000 + 2 days);
    }

    function test_Revert_UpdateMaxValidityPeriod_Unauthorized() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(98), address(0xBEEF)));
        issuer.updateMaxValidityPeriod(1 days);
    }

    function test_Revert_UpdateMaxValidityPeriod_Zero() public {
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidMaxValidityPeriod.selector);
        issuer.updateMaxValidityPeriod(0);
    }

    function test_Revert_Initialize_ZeroMaxValidityPeriod() public {
        address impl = address(new ZKPassportBadgeIssuer());
        bytes memory initData = abi.encodeCall(
            ZKPassportBadgeIssuer.initialize,
            (address(auth), address(badge), DOMAIN, SCOPE, address(verifier), 0)
        );
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidMaxValidityPeriod.selector);
        new ERC1967Proxy(impl, initData);
    }

    // ── Provenance, inputs & governance ──────────────────────────────────────

    // Bad-actor-clear asks one question: is this person disqualified? The answer is the same fact for all parties.
    // Therefore the operator attestation and the ZK proof use the SAME fact-key. Only the recorded issuer
    // separates them. A condition that accepts only a passport proof filters on the issuer, and it does not see
    // the operator attestation. A condition that accepts both does not filter. The country list is the same, and
    // the policy library reads it in the two conditions.
    function test_Provenance_IssuerDistinguishesTheBasis_NotTheFactKey() public {
        vm.warp(1000);
        issuer.submitProofAndMint(_params(alice, 1000, 1 days), FK_BOTH, _excluded("USA"));

        // The operator asserts the same facts for bob, but from its own examination.
        Credential memory operatorCred;
        operatorCred.asserts = FK_BOTH;
        operatorCred.nationalityOut = _excluded("USA");
        operatorCred.expiryDate = uint64(block.timestamp + 1 days);
        badge.mint(bob, operatorCred);

        assertTrue(badge.hasValidCredentialOf(alice, K_BAD_ACTOR_CLEAR), "no filter: the two types answer");
        assertTrue(badge.hasValidCredentialOf(bob, K_BAD_ACTOR_CLEAR));

        address[] memory zkOnly = new address[](1);
        zkOnly[0] = address(issuer);
        assertTrue(badge.hasValidCredentialOf(alice, K_BAD_ACTOR_CLEAR, zkOnly), "a proof shows the fact");
        assertFalse(badge.hasValidCredentialOf(bob, K_BAD_ACTOR_CLEAR, zkOnly), "an operator attestation, not a proof");

        (bool aliceProved,) = NationalityPolicy.excludes(badge, alice, "USA", zkOnly);
        (bool bobProved,) = NationalityPolicy.excludes(badge, bob, "USA", zkOnly);
        (bool bobAnyIssuer,) = NationalityPolicy.excludes(badge, bob, "USA");
        assertTrue(aliceProved);
        assertFalse(bobProved, "a proof did not show the operator list");
        assertTrue(bobAnyIssuer, "but it answers a caller that accepts all issuers");
    }

    // This contract cannot mint a fact that it cannot check. The key itself is permitted: an operator can assert
    // the same fact from its own examination. But a proof cannot show the fact. Therefore this contract must not
    // record it.
    function test_Revert_Mint_RejectsUncheckedKey() public {
        vm.expectRevert(ZKPassportBadgeIssuer.UnverifiedFactKey.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), K_NON_US);
    }

    function test_Revert_Mint_ZeroFactKeys() public {
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidFactKeys.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), 0);
    }

    // A request with only an unchecked key is the first attempt. The more dangerous attempt sends that key with a
    // key that this contract can mint. The legitimate key must not let the other key through. The contract refuses
    // the full request and mints no part of it. Thus a ZKPassport proof never supports a fact that an operator
    // must establish.
    function test_Revert_Mint_UncheckedKeySneakedInAlongsideCheckedOne() public {
        _expectFactKeysRefused(FK_NAT_OUT | K_NON_US, _excluded("USA"));
    }

    // A scope key gives the holder access to the offers of one SPV. An issuer grants it. A passport does not show
    // it, and the credential has no scope. Therefore the contract must refuse the key as unverified.
    function test_Revert_Mint_ScopeKeySneakedIn() public {
        _expectFactKeysRefused(FK_BAD_ACTOR | K_SPV_WHITELIST, _empty());
    }

    // A VALUE key needs data that this contract does not collect. Such a key would record an empty fact.
    function test_Revert_Mint_ValueKeySneakedIn() public {
        _expectFactKeysRefused(FK_NAT_OUT | K_INVESTOR_TYPE, _excluded("USA"));
    }

    // An undefined bit is a claim with no meaning. A request for the full mask is the same attempt, but simpler.
    function test_Revert_Mint_UndefinedBitSneakedIn() public {
        _expectFactKeysRefused(FK_BAD_ACTOR | (1 << 7), _empty());
    }

    function test_Revert_Mint_EveryKeyGrab() public {
        _expectFactKeysRefused(ALL_KEYS, _excluded("USA"));
        _expectFactKeysRefused(type(uint256).max, _excluded("USA"));
    }

    // The badge grant is a second, independent limit. If you make the grant smaller, the contract cannot record a
    // fact, although it can check that fact correctly. Thus an operator can control a delegated issuer, and no
    // change to the code of that issuer is necessary.
    function test_Revert_Mint_BeyondTheBadgeGrant() public {
        badge.setIssuerKeys(address(issuer), K_NATIONALITY_OUT); // bad-actor-clear withdrawn

        vm.expectRevert(
            abi.encodeWithSelector(
                ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, address(issuer), K_BAD_ACTOR_CLEAR
            )
        );
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_BAD_ACTOR);
    }

    // A new deployment of the issuer receives no authority. A mint needs a grant on the badge. This is the result
    // of the removal of the ADMIN_ROLE that the contract needed before.
    function test_Revert_Mint_WithoutAnyGrant() public {
        badge.setIssuerKeys(address(issuer), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, address(issuer), K_NATIONALITY_OUT
            )
        );
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT, _excluded("USA"));
    }

    // The contract refuses an empty fact-set before it reads the proof. The request asks for no fact, thus the
    // contract has nothing to check.
    function test_Revert_Mint_ZeroFactKeysScreenedBeforeProof() public {
        verifier.setShouldVerify(false);
        ProofVerificationParams memory p = _params(alice, block.timestamp, 1 days);
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidFactKeys.selector);
        issuer.submitProofAndMint(p, 0);
    }

    // The nationality function has a second argument. It must do the same check, and it must not be an easier way
    // to mint an unchecked key.
    function test_Revert_Mint_UncheckedKeySneakedInViaNationalityOverload() public {
        ProofVerificationParams memory p = _params(alice, block.timestamp, 1 days);
        string[] memory list = _excluded("USA");
        vm.expectRevert(ZKPassportBadgeIssuer.UnverifiedFactKey.selector);
        issuer.submitProofAndMint(p, FK_NAT_OUT | K_NON_US, list);
    }

    // The combined fact-set still asks for the nationality fact, so it still owes a country list.
    function test_Revert_CombinedFacts_WithoutList() public {
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidNationalityList.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_BOTH);
    }

    function test_Revert_NationalityKey_WithoutList() public {
        // The nationality fact needs a country list — the 2-arg overload (empty list) must refuse it.
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidNationalityList.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_NAT_OUT);
    }

    function test_Revert_NationalityList_WithoutKey() public {
        // A list supplied for a fact-set that doesn't ask for the nationality fact is a mismatch.
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidNationalityList.selector);
        issuer.submitProofAndMint(_params(alice, block.timestamp, 1 days), FK_BAD_ACTOR, _excluded("USA"));
    }

    function test_Revert_UpdateVerifier_Unauthorized() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(98), address(0xBEEF)));
        issuer.updateVerifier(address(0x1234));
    }

    function test_Revert_Upgrade_Unauthorized() public {
        address newImpl = address(new ZKPassportBadgeIssuer());
        vm.prank(address(0xDEAD));
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, uint256(99), address(0xDEAD)));
        issuer.upgradeToAndCall(newImpl, "");
    }

    function test_Revert_Initialize_ZeroBadge() public {
        address impl = address(new ZKPassportBadgeIssuer());
        bytes memory initData = abi.encodeCall(
            ZKPassportBadgeIssuer.initialize,
            (address(auth), address(0), DOMAIN, SCOPE, address(verifier), MAX_VALIDITY)
        );
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidBadge.selector);
        new ERC1967Proxy(impl, initData);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    function _excluded(string memory code) internal pure returns (string[] memory a) {
        a = new string[](1);
        a[0] = code;
    }

    function _empty() internal pure returns (string[] memory) {
        return new string[](0);
    }

    /// @dev Makes sure that the contract refuses `factKeys`, and that the attempt kept no data. There must be no
    /// credential on the badge and no entry in the register. Thus no person can read a refused request later as
    /// an approved request.
    function _expectFactKeysRefused(uint256 factKeys, string[] memory list) internal {
        ProofVerificationParams memory p = _params(alice, block.timestamp, 1 days);
        uint256 balanceBefore = badge.balanceOf(alice);

        vm.expectRevert(ZKPassportBadgeIssuer.UnverifiedFactKey.selector);
        if (list.length == 0) issuer.submitProofAndMint(p, factKeys);
        else issuer.submitProofAndMint(p, factKeys, list);

        assertEq(badge.balanceOf(alice), balanceBefore, "no credential minted");
        (, bool exists) = issuer.currentTokenOf(factKeys, alice);
        assertFalse(exists, "no tracked entry");
    }

    function _params(address sender, uint256 proofTimestamp, uint256 validityPeriod)
        internal
        view
        returns (ProofVerificationParams memory)
    {
        bytes32[] memory pubs = new bytes32[](3);
        pubs[0] = keccak256(bytes(DOMAIN));
        pubs[1] = keccak256(bytes(SCOPE));
        pubs[2] = bytes32(proofTimestamp);
        return ProofVerificationParams({
            version: bytes32(0),
            proofVerificationData: ProofVerificationData({vkeyHash: bytes32(0), proof: "", publicInputs: pubs}),
            committedInputs: abi.encode(BoundData({senderAddress: sender, chainId: block.chainid, customData: ""})),
            serviceConfig: ServiceConfig({validityPeriodInSeconds: validityPeriod, domain: DOMAIN, scope: SCOPE, devMode: false})
        });
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {
    CategoryKind,
    Credential,
    CredentialCategory,
    ATTR_INVESTOR_JURISDICTION,
    ATTR_REGULATORY_JURISDICTION,
    ATTR_US_STATE,
    ATTR_BO_COUNT
} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {IERC5484} from "../src/interfaces/IERC5484.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Unit tests for the LeXcheXBadge credential reads — the credentialing layer every cyberTRADE
/// compliance condition and the offer-visibility UI read from.
///
/// Key invariants / assumptions this suite guards (legal / economic intent, not mechanics):
///  1. Validity is the master gate: a wallet is eligible only while it holds a credential that is issued,
///     unexpired, and not voided. Expiry forces re-attestation; a void (sanctions hit, failed re-KYC,
///     discovered bad actor) locks the holder out at once, regardless of how recent it is.
///  2. Current standing governs, per attribute: each attribute read reflects the holder's most-recent valid
///     credential from a credential type authoritative for that attribute, so corrections and recertifications
///     take effect immediately and stale facts never override fresher ones.
///  3. Eligibility filters on what is attested, not which credential: any valid credential of the required
///     kind (and investor type, where relevant) admits — the specific instance is interchangeable.
///  4. Whitelist and syndicate entitlements are scoped to a single SPV; membership never leaks to another SPV.
///  5. U.S. status is conservative: a holder is U.S. if either its §3(c)(1)(A) look-through classification or
///     its physical domicile is U.S., and a U.S.-domiciled party can never be declassified out of the count.
///  6. Look-through classification is decoupled from physical domicile: a non-U.S. feeder with any U.S.
///     beneficial owner counts as U.S. for the ICA look-through while its domicile stays foreign for
///     CFIUS / blue-sky.
///  7. Recertification preserves the seasoning anchor (original issuance date), so a routine refresh does not
///     reset time-based eligibility.
///  8. Credentials are soulbound to the verified wallet: non-transferable, no delegation.
///  9. Attribute authority is per credential type: only a type the issuer designates as a source of truth for
///     an attribute can answer it, so an unrelated credential (e.g. a whitelist) neither answers it nor shadows
///     one that does. The newest authoritative credential is taken verbatim, so a blank field is a deliberate
///     clear (an entity leaving the U.S. clears its state), never a silent gap.
contract LeXcheXBadgeTest is Test {
    bytes32 constant CAT_KYC = keccak256("cat.kyc");
    bytes32 constant CAT_ACCREDITED = keccak256("cat.accredited");

    address owner;
    LeXcheXBadge badge;

    function setUp() public {
        owner = makeAddr("owner");
        BorgAuth auth = new BorgAuth(owner);
        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(
                    address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth)))
                )
            )
        );
        _createCategory(CAT_KYC, CategoryKind.KYC_AML);
        _createCategory(CAT_ACCREDITED, CategoryKind.ACCREDITED_INVESTOR);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Single live credential — baseline: every read resolves to the one record
    // ─────────────────────────────────────────────────────────────────────────

    // A holder with one live credential: every read resolves to that credential's facts, across every attribute
    // (jurisdiction, regulatory, U.S. state, beneficial-owner count).
    function test_SingleLiveCredential_AllSelectorsResolveToIt() public {
        address holder = address(0xB0B5);
        Credential memory c = _baseCred("US", bytes2("CA"));
        c.investorName = "Domestic Fund LP";
        c.investorType = "Fund";
        c.beneficialOwnerCount = 4;
        c.regulatoryJurisdiction = "US";
        _mint(holder, CAT_ACCREDITED, c);

        assertEq(badge.getUsState(holder), bytes2("CA"));
        assertEq(uint256(badge.getBeneficialOwnerCount(holder)), 4);
        assertEq(badge.getInvestorJurisdiction(holder), "US");
        assertEq(badge.getRegulatoryJurisdiction(holder), "US");
        assertTrue(badge.isUSInvestor(holder));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // regulatoryJurisdiction / isUSInvestor (the _ANY selector)
    // ─────────────────────────────────────────────────────────────────────────

    // A Cayman feeder with any U.S. beneficial owner is classified regulatory-US; the look-through read
    // (isUSInvestor) is U.S. while the physical domicile stays Cayman for CFIUS/blue-sky.
    function test_RegulatoryJurisdiction_DecouplesFromPhysicalDomicile() public {
        address feeder = address(0xFEEDFEED);
        Credential memory c = _baseCred("KY", bytes2(0));
        c.investorName = "Acme Feeder LP";
        c.investorType = "Fund";
        c.beneficialOwnerCount = 10;
        c.regulatoryJurisdiction = "US";
        _mint(feeder, CAT_ACCREDITED, c);

        assertTrue(badge.isUSInvestor(feeder));
        assertEq(badge.getRegulatoryJurisdiction(feeder), "US");
        assertEq(badge.getInvestorJurisdiction(feeder), "KY");
    }

    // When regulatoryJurisdiction is unset, isUSInvestor falls back to the physical investorJurisdiction.
    function test_RegulatoryJurisdiction_FallsBackToPhysicalWhenUnset() public {
        address usIndiv = address(0xB0B0);
        _mintCred(usIndiv, CAT_ACCREDITED, "US", bytes2(0));
        assertEq(badge.getRegulatoryJurisdiction(usIndiv), "");
        assertTrue(badge.isUSInvestor(usIndiv));

        address kyIndiv = address(0xB0B1);
        _mintCred(kyIndiv, CAT_ACCREDITED, "KY", bytes2(0));
        assertFalse(badge.isUSInvestor(kyIndiv));
    }

    // A wholly-non-US feeder that admits its first U.S. beneficial owner flips to regulatory-US in place,
    // without disturbing the physical domicile.
    function test_SetRegulatoryJurisdiction_FlipsClassificationInPlace() public {
        address feeder = address(0xFEED02);
        _mintCred(feeder, CAT_ACCREDITED, "KY", bytes2(0));
        assertFalse(badge.isUSInvestor(feeder));

        uint256 tokenId = badge.getCredentialByOwner(feeder);
        vm.prank(owner);
        badge.setRegulatoryJurisdiction(tokenId, "US");

        assertTrue(badge.isUSInvestor(feeder));
        assertEq(badge.getInvestorJurisdiction(feeder), "KY");
    }

    // Conservative: a U.S.-domiciled party is a U.S. investor even if its regulatory classification says
    // otherwise — physical U.S. domicile can never be declassified out of the count.
    function test_RegulatoryJurisdiction_UsDomicileCannotBeDeclassified() public {
        address usEntity = address(0xB0B2);
        Credential memory c = _baseCred("US", bytes2(0));
        c.investorName = "US Co";
        c.investorType = "Fund";
        c.beneficialOwnerCount = 3;
        c.regulatoryJurisdiction = "KY";
        _mint(usEntity, CAT_ACCREDITED, c);

        assertTrue(badge.isUSInvestor(usEntity));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Recency & determinism of _mostRecentValidWith
    // ─────────────────────────────────────────────────────────────────────────

    // Recency ranks on lastUpdated, not issuanceDate: an in-place correction on the OLDER-issuance credential
    // must win selection even when a newer-issuance credential exists and was left untouched.
    function test_RegulatoryJurisdiction_FreshCorrectionOnOlderCredentialWins() public {
        address feeder = address(0xFEED03);
        _mintCred(feeder, CAT_ACCREDITED, "KY", bytes2(0)); // credential A: earlier issuanceDate
        uint256 older = badge.getTokenIdsByOwner(feeder)[0];

        vm.warp(block.timestamp + 30 days);
        _mintCred(feeder, CAT_ACCREDITED, "KY", bytes2(0)); // credential B: later issuanceDate, untouched
        assertFalse(badge.isUSInvestor(feeder));

        // Flip the OLDER credential to regulatory-US; ranking on issuanceDate would keep B and miss this.
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        badge.setRegulatoryJurisdiction(older, "US");

        assertTrue(badge.isUSInvestor(feeder));
        assertEq(badge.getRegulatoryJurisdiction(feeder), "US");
    }

    // recertify bumps the recency key (lastUpdated) while preserving issuanceDate: a refreshed OLDER-issuance
    // credential wins selection over an untouched newer one, and its seasoning anchor is not reset.
    function test_Recertify_RefreshesRecencyForSelection() public {
        address feeder = address(0xFEED04);
        uint256 older = _mintCred(feeder, CAT_ACCREDITED, "KY", bytes2(0)); // credential A
        uint64 seasonedAt = badge.getCredential(older).issuanceDate;

        vm.warp(block.timestamp + 30 days);
        _mintCred(feeder, CAT_ACCREDITED, "KY", bytes2(0)); // credential B: later issuance, untouched
        assertFalse(badge.isUSInvestor(feeder));

        vm.warp(block.timestamp + 1 days);
        Credential memory refreshed = _baseCred("KY", bytes2(0));
        refreshed.regulatoryJurisdiction = "US";
        vm.prank(owner);
        badge.recertify(older, refreshed); // bumps A's lastUpdated past B, preserves issuanceDate

        assertTrue(badge.isUSInvestor(feeder));
        assertEq(badge.getRegulatoryJurisdiction(feeder), "US");
        assertEq(uint256(badge.getCredential(older).issuanceDate), uint256(seasonedAt));
    }

    // Ties on lastUpdated (two credentials attested in the same block) resolve deterministically to the higher
    // tokenId, independent of enumeration order — the read cannot flip based on unrelated burns.
    function test_UsState_TieBreaksOnHigherTokenId() public {
        address holder = address(0xB0B3);
        _mintCred(holder, CAT_KYC, "US", bytes2("NY"));        // lower tokenId
        _mintCred(holder, CAT_ACCREDITED, "US", bytes2("TX")); // higher tokenId, same block

        uint256[] memory ids = badge.getTokenIdsByOwner(holder);
        assertGt(ids[1], ids[0]);
        assertEq(badge.getUsState(holder), bytes2("TX"));
    }

    // A newer credential of a category that does NOT govern regulatory (here KYC) cannot shadow the look-through
    // classification a governing credential attests — the resolution of #14.
    function test_RegulatoryJurisdiction_UnrelatedCategoryDoesNotShadow() public {
        address feeder = address(0xFEED05);
        Credential memory c = _baseCred("KY", bytes2(0));
        c.regulatoryJurisdiction = "US";
        _mint(feeder, CAT_ACCREDITED, c); // accredited governs regulatory
        assertTrue(badge.isUSInvestor(feeder));

        vm.warp(block.timestamp + 1 days);
        _mintCred(feeder, CAT_KYC, "KY", bytes2(0)); // newer, but KYC does not govern regulatory

        assertEq(badge.getRegulatoryJurisdiction(feeder), "US"); // preserved
        assertTrue(badge.isUSInvestor(feeder));
    }

    // Within a governing category, the newest credential is authoritative verbatim: a later governing credential
    // that omits the classification clears it (a deliberate reclassification, not a silent gap).
    function test_RegulatoryJurisdiction_ClearedByNewerGoverningCredential() public {
        address feeder = address(0xFEED06);
        Credential memory c = _baseCred("KY", bytes2(0));
        c.regulatoryJurisdiction = "US";
        _mint(feeder, CAT_ACCREDITED, c);
        assertTrue(badge.isUSInvestor(feeder));

        vm.warp(block.timestamp + 1 days);
        _mintCred(feeder, CAT_ACCREDITED, "KY", bytes2(0)); // newer governing credential, regulatory empty

        assertEq(badge.getRegulatoryJurisdiction(feeder), ""); // cleared
        assertFalse(badge.isUSInvestor(feeder));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Attribute filters & validity gating
    // ─────────────────────────────────────────────────────────────────────────

    // No credentials: every attribute read returns its default and isUSInvestor is false (found == false path).
    function test_NoCredential_ReturnsDefaults() public view {
        address nobody = address(0xDEAD);
        assertEq(badge.getUsState(nobody), bytes2(0));
        assertEq(uint256(badge.getBeneficialOwnerCount(nobody)), 0);
        assertEq(badge.getInvestorJurisdiction(nobody), "");
        assertEq(badge.getRegulatoryJurisdiction(nobody), "");
        assertFalse(badge.isUSInvestor(nobody));
    }

    // A holder that relocates out of the U.S. clears its usState: the newest state-governing credential is
    // non-U.S. and carries no state, so getUsState reports none rather than resurfacing the stale U.S. state.
    function test_GetUsState_ClearedByNewerNonUsCredential() public {
        address holder = address(0xA2);
        _mintCred(holder, CAT_KYC, "US", bytes2("NY")); // older: U.S. resident, state NY
        vm.warp(block.timestamp + 1 days);
        _mintCred(holder, CAT_KYC, "KY", bytes2(0));     // newer: relocated to KY, no state

        assertEq(badge.getUsState(holder), bytes2(0));
        assertEq(badge.getInvestorJurisdiction(holder), "KY");
        assertFalse(badge.isUSInvestor(holder));
    }

    // A newer credential of a category that does NOT govern the look-through count (here KYC) cannot shadow the
    // §3(c)(1)(A) count a governing (accredited entity) credential attests.
    function test_GetBeneficialOwnerCount_NotShadowedByNonGoverningCategory() public {
        address entity = address(0xB1);
        Credential memory withCount = _baseCred("US", bytes2("CA"));
        withCount.investorType = "Fund";
        withCount.beneficialOwnerCount = 5;
        _mint(entity, CAT_ACCREDITED, withCount); // older, count 5, governs BO count

        vm.warp(block.timestamp + 1 days);
        _mintCred(entity, CAT_KYC, "US", bytes2("CA")); // newer, but KYC does not govern BO count

        assertEq(uint256(badge.getBeneficialOwnerCount(entity)), 5);
    }

    // Expired credentials are excluded from selection even when they are the most recent.
    function test_ExpiredCredentialSkipped() public {
        address holder = address(0xC1);
        _mintCred(holder, CAT_KYC, "US", bytes2("CA")); // long-lived, state CA

        vm.warp(block.timestamp + 1 days);
        Credential memory shortLived = _baseCred("US", bytes2("NY"));
        shortLived.expiryDate = uint64(block.timestamp + 1 days);
        _mint(holder, CAT_ACCREDITED, shortLived); // newer, state NY, expires soon

        vm.warp(block.timestamp + 2 days); // NY expired, CA still valid
        assertEq(badge.getUsState(holder), bytes2("CA"));
    }

    // Voided credentials are excluded despite void bumping lastUpdated to the newest touch — isValid gates them
    // out before the recency comparison, so the selection cannot land on a revoked credential.
    function test_VoidedCredentialExcluded_DespiteMostRecentTouch() public {
        address holder = address(0xD1);
        _mintCred(holder, CAT_KYC, "US", bytes2("CA")); // older, CA
        vm.warp(block.timestamp + 1 days);
        uint256 ny = _mintCred(holder, CAT_ACCREDITED, "US", bytes2("NY")); // newer, NY

        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        badge.void(ny, "revoked"); // bumps lastUpdated to newest, but isValid == false

        assertEq(badge.getUsState(holder), bytes2("CA"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Category-gating reads (Matrix A)
    // ─────────────────────────────────────────────────────────────────────────

    // hasValidCredential resolves an EXACT category: the right id admits, a valid credential of a different
    // category does not, and an uncredentialed wallet is rejected.
    function test_HasValidCredential_ExactCategoryMatch() public {
        address holder = address(0xE1);
        _mintCred(holder, CAT_KYC, "US", bytes2("CA"));
        assertTrue(badge.hasValidCredential(holder, CAT_KYC));
        assertFalse(badge.hasValidCredential(holder, CAT_ACCREDITED));
        assertFalse(badge.hasValidCredential(address(0xDEAD), CAT_KYC));
    }

    // The gate closes when the credential lapses: expiry and void both deny admission (the isValid mechanism
    // is category-agnostic, so this stands in for every kind's deny path).
    function test_HasValidCredential_DeniedWhenExpiredOrVoided() public {
        address expired = address(0xE2);
        Credential memory shortLived = _baseCred("US", bytes2("CA"));
        shortLived.expiryDate = uint64(block.timestamp + 1 days);
        _mint(expired, CAT_KYC, shortLived);
        vm.warp(block.timestamp + 2 days);
        assertFalse(badge.hasValidCredential(expired, CAT_KYC));

        address voided = address(0xE3);
        uint256 id = _mintCred(voided, CAT_KYC, "US", bytes2("CA"));
        vm.prank(owner);
        badge.void(id, "revoked");
        assertFalse(badge.hasValidCredential(voided, CAT_KYC));
    }

    // hasValidCredentialOfKind matches ANY category of the kind — the whole point of kind vs categoryId: a
    // second, differently-identified accredited category still satisfies an accredited gate, while a
    // different kind (qualified purchaser) the holder lacks is rejected.
    function test_HasValidCredentialOfKind_MatchesKindAcrossCategories() public {
        bytes32 catAccreditedAlt = keccak256("cat.accredited.alt");
        _createCategory(catAccreditedAlt, CategoryKind.ACCREDITED_INVESTOR);

        address holder = address(0xE4);
        _mintCred(holder, catAccreditedAlt, "US", bytes2("CA"));
        assertTrue(badge.hasValidCredentialOfKind(holder, CategoryKind.ACCREDITED_INVESTOR, ""));
        assertFalse(badge.hasValidCredentialOfKind(holder, CategoryKind.QUALIFIED_PURCHASER, ""));
    }

    // The investorType filter separates parameterizations that share a kind (e.g. accredited entity vs
    // individual): an empty filter matches any type, a matching type admits, a non-matching type is rejected.
    function test_HasValidCredentialOfKind_InvestorTypeFilter() public {
        address fund = address(0xE5);
        Credential memory c = _baseCred("US", bytes2("CA"));
        c.investorType = "Fund";
        _mint(fund, CAT_ACCREDITED, c);

        assertTrue(badge.hasValidCredentialOfKind(fund, CategoryKind.ACCREDITED_INVESTOR, ""));
        assertTrue(badge.hasValidCredentialOfKind(fund, CategoryKind.ACCREDITED_INVESTOR, "Fund"));
        assertFalse(badge.hasValidCredentialOfKind(fund, CategoryKind.ACCREDITED_INVESTOR, "Individual"));
    }

    // hasValidWhitelistFor is scoped to a specific SPV: a whitelist minted for one SPV admits only that SPV's
    // offers and never another's, and a SYNDICATE credential resolves the same scoped way.
    function test_HasValidWhitelistFor_ScopedToSPV() public {
        address spvA = address(0x5A);
        address spvB = address(0x5B);

        bytes32 whitelistA = keccak256("cat.wl.spvA");
        _createScopedCategory(whitelistA, CategoryKind.SPV_WHITELIST, spvA);
        address holder = address(0xE6);
        _mintCred(holder, whitelistA, "KY", bytes2(0));
        assertTrue(badge.hasValidWhitelistFor(holder, spvA));
        assertFalse(badge.hasValidWhitelistFor(holder, spvB));

        bytes32 syndicateB = keccak256("cat.syn.spvB");
        _createScopedCategory(syndicateB, CategoryKind.SYNDICATE, spvB);
        address member = address(0xE7);
        _mintCred(member, syndicateB, "KY", bytes2(0));
        assertTrue(badge.hasValidWhitelistFor(member, spvB));
    }

    // A non-whitelist credential (KYC) never grants SPV whitelist entitlement, even when valid.
    function test_HasValidWhitelistFor_IgnoresNonWhitelistKinds() public {
        address holder = address(0xE8);
        _mintCred(holder, CAT_KYC, "US", bytes2("CA"));
        assertFalse(badge.hasValidWhitelistFor(holder, address(0x5A)));
    }

    // hasValidLexCheX (v1-compatible) is true for any valid credential and false for an uncredentialed wallet.
    function test_HasValidLexCheX_AnyValidCredential() public {
        address holder = address(0xE9);
        assertFalse(badge.hasValidLexCheX(holder));
        _mintCred(holder, CAT_KYC, "US", bytes2("CA"));
        assertTrue(badge.hasValidLexCheX(holder));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _createCategory(bytes32 id, CategoryKind kind) internal {
        _createScopedCategory(id, kind, address(0));
    }

    function _createScopedCategory(bytes32 id, CategoryKind kind, address scope) internal {
        CredentialCategory memory c;
        c.name = "cat";
        c.kind = kind;
        c.defaultValidityDuration = 3650 days;
        c.burnAuth = IERC5484.BurnAuth.OwnerOnly;
        c.scope = scope;
        // Governance map for these tests: KYC_AML is the identity/residence anchor (jurisdiction + usState);
        // ACCREDITED_INVESTOR carries the full entity profile; whitelist/syndicate/custom govern nothing.
        if (kind == CategoryKind.KYC_AML) {
            c.governedAttributes = ATTR_INVESTOR_JURISDICTION | ATTR_US_STATE;
        } else if (kind == CategoryKind.ACCREDITED_INVESTOR) {
            c.governedAttributes = ATTR_INVESTOR_JURISDICTION | ATTR_REGULATORY_JURISDICTION | ATTR_US_STATE | ATTR_BO_COUNT;
        }
        vm.prank(owner);
        badge.createCategory(id, c);
    }

    function _baseCred(string memory jurisdiction, bytes2 state) internal pure returns (Credential memory c) {
        c.investorName = "Inv";
        c.investorType = "Individual";
        c.investorJurisdiction = jurisdiction;
        c.usState = state;
    }

    function _mint(address to, bytes32 categoryId, Credential memory c) internal returns (uint256) {
        vm.prank(owner);
        return badge.mint(to, categoryId, c);
    }

    function _mintCred(address to, bytes32 categoryId, string memory jurisdiction, bytes2 state)
        internal
        returns (uint256)
    {
        return _mint(to, categoryId, _baseCred(jurisdiction, state));
    }
}

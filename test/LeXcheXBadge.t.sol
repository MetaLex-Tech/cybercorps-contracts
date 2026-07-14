// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {CategoryKind, Credential, CredentialCategory} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {IERC5484} from "../src/interfaces/IERC5484.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Unit tests for the LeXcheXBadge credential reads, focused on the `_mostRecentValidWith` selection
/// behind getUsState / getBeneficialOwnerCount / getInvestorJurisdiction / getRegulatoryJurisdiction /
/// isUSInvestor. Coverage tracked in `specs/analysis/LeXcheXBadge — _mostRecentValidWith coverage map.md`.
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

    // _HAS_US_STATE skips stateless credentials: a non-US holder reports no state, and a more-recent stateless
    // credential does not shadow an older stateful one.
    function test_GetUsState_SkipsStatelessCredential() public {
        address nonUs = address(0xA1);
        _mintCred(nonUs, CAT_KYC, "KY", bytes2(0));
        assertEq(badge.getUsState(nonUs), bytes2(0));

        address mixed = address(0xA2);
        _mintCred(mixed, CAT_KYC, "US", bytes2("NY")); // older, carries state
        vm.warp(block.timestamp + 1 days);
        _mintCred(mixed, CAT_ACCREDITED, "KY", bytes2(0)); // newer, no state → skipped
        assertEq(badge.getUsState(mixed), bytes2("NY"));
    }

    // _HAS_BO_COUNT skips zero-count credentials: a more-recent count-0 credential does not shadow an older
    // credential that actually carries the §3(c)(1)(A) look-through count.
    function test_GetBeneficialOwnerCount_SkipsZeroCount() public {
        address entity = address(0xB1);
        Credential memory withCount = _baseCred("US", bytes2("CA"));
        withCount.investorType = "Fund";
        withCount.beneficialOwnerCount = 5;
        _mint(entity, CAT_ACCREDITED, withCount); // older, count 5

        vm.warp(block.timestamp + 1 days);
        _mintCred(entity, CAT_KYC, "US", bytes2("CA")); // newer, count 0 → skipped

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
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _createCategory(bytes32 id, CategoryKind kind) internal {
        CredentialCategory memory c;
        c.name = "cat";
        c.kind = kind;
        c.defaultValidityDuration = 3650 days;
        c.burnAuth = IERC5484.BurnAuth.OwnerOnly;
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

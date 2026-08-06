// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {
    ILexChexBadge,
    K_INVESTOR_TYPE,
    K_INVESTOR_JURISDICTION,
    K_LOOKTHROUGH_JURISDICTION,
    InvestorType
} from "../src/interfaces/ILexChexBadge.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {LookThroughPolicy} from "../src/libs/policies/LookThroughPolicy.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Unit tests for the ICA §3(c)(1)(A) U.S.-investor classification. The badge stores the two
/// jurisdiction facts; deciding what they mean for the holder count is this policy's job, so the rules
/// below live here rather than in the badge suite.
///
/// Invariants guarded:
///  1. U.S. if EITHER the look-through classification or the physical domicile is U.S. — a U.S.-domiciled
///     party can never be declassified out of the count.
///  2. Look-through classification is decoupled from physical domicile (an offshore feeder with U.S.
///     beneficial owners counts U.S. while its domicile stays foreign).
///  3. An entirely unestablished holder is conservatively U.S., so missing evidence cannot slip an ICA /
///     no-U.S.-investor gate.
///  4. Only the canonical U.S. spellings match — the shared `USJurisdictionPolicy` reading, checked here
///     with the look-through's polarity (a non-canonical spelling must not declassify a party).
contract LookThroughPolicyTest is Test {
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
    }

    // A holder with no credential at all is conservatively U.S.
    function test_Unknown_IsConservativelyUS() public {
        assertTrue(_isUS(makeAddr("nobody")));
    }

    // An established non-U.S. jurisdiction is not conservatively U.S.
    function test_EstablishedNonUs_IsNotUS() public {
        assertFalse(_isUS(_holder("ky", "KY", "")));
    }

    // With no look-through classification, the physical jurisdiction decides.
    function test_FallsBackToPhysical() public {
        assertTrue(_isUS(_holder("usIndiv", "US", "")));
    }

    // A Cayman feeder classified U.S. by look-through counts U.S., while its domicile stays Cayman.
    function test_LookThroughDecouplesFromPhysical() public {
        address feeder = _holder("feeder", "KY", "US");
        assertTrue(_isUS(feeder));
        (string memory physical,) = badge.getInvestorJurisdiction(feeder);
        assertEq(physical, "KY");
    }

    // Conservative: a U.S.-domiciled party stays U.S. even when its look-through classification says otherwise.
    function test_UsDomicileCannotBeDeclassified() public {
        assertTrue(_isUS(_holder("usEntity", "US", "KY")));
    }

    // "US"/"USA"/"United States" all read as U.S.; nothing else does, including case and punctuation variants.
    function test_UsJurisdiction_CanonicalSpellingsOnly() public {
        string[3] memory us = ["US", "USA", "United States"];
        for (uint256 i = 0; i < us.length; i++) {
            assertTrue(_isUS(_holder(us[i], us[i], "")), us[i]);
        }

        string[3] memory notUs = ["us", "U.S.", "KY"];
        for (uint256 i = 0; i < notUs.length; i++) {
            assertFalse(_isUS(_holder(notUs[i], notUs[i], "")), notUs[i]);
        }
    }

    // ── Answer expiry ─────────────────────────────────────────────────────────
    // A cached non-U.S. answer rests on credentials that lapse with no transaction to observe, and a lapsed
    // fact reads empty, which reads U.S. The second return says when to stop trusting it; 0 means never.

    // A U.S. answer can only drift to non-U.S., which overstates the U.S. count, so it never expires.
    function test_Expiry_UsAnswerNeverExpires() public {
        (bool isUS, uint64 expiry) = _isUSWithExpiry(_holder("usIndiv", "US", ""));
        assertTrue(isUS);
        assertEq(expiry, 0);
    }

    // Same for an entirely unestablished holder: already conservative, nothing to lapse.
    function test_Expiry_UnknownNeverExpires() public {
        (bool isUS, uint64 expiry) = _isUSWithExpiry(makeAddr("nobody"));
        assertTrue(isUS);
        assertEq(expiry, 0);
    }

    // A non-U.S. answer is trusted only until the credential behind it expires.
    function test_Expiry_NonUsCarriesItsExpiry() public {
        uint64 credExpiry = uint64(block.timestamp + 30 days);
        (bool isUS, uint64 expiry) = _isUSWithExpiry(_holderExpiring("ky", "KY", "", credExpiry));
        assertFalse(isUS);
        assertEq(expiry, credExpiry);
    }

    // Two facts behind the answer: the earlier expiry is the one that matters.
    function test_Expiry_TakesEarliestOfBothFacts() public {
        address holder = makeAddr("twoCreds");
        uint64 early = uint64(block.timestamp + 10 days);
        uint64 late = uint64(block.timestamp + 90 days);

        Credential memory physical;
        physical.asserts = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
        physical.expiryDate = late;
        physical.investorType = InvestorType.INDIVIDUAL;
        physical.investorJurisdiction = "KY";

        Credential memory regulatory;
        regulatory.asserts = K_LOOKTHROUGH_JURISDICTION;
        regulatory.expiryDate = early;
        regulatory.lookThroughJurisdiction = "KY";

        vm.startPrank(owner);
        badge.mint(holder, physical);
        badge.mint(holder, regulatory);
        vm.stopPrank();

        (bool isUS, uint64 expiry) = _isUSWithExpiry(holder);
        assertFalse(isUS);
        assertEq(expiry, early);
    }

    // Once the evidence lapses the answer flips to U.S. on its own — what the expiry exists to predict.
    function test_Expiry_AnswerFlipsUsAfterExpiry() public {
        uint64 credExpiry = uint64(block.timestamp + 30 days);
        address holder = _holderExpiring("ky", "KY", "", credExpiry);
        assertFalse(_isUS(holder));

        vm.warp(credExpiry + 1);
        assertTrue(_isUS(holder));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _isUS(address holder) internal view returns (bool isUS) {
        (isUS,) = LookThroughPolicy.isUSInvestor(ILexChexBadge(address(badge)), holder);
    }

    function _isUSWithExpiry(address holder) internal view returns (bool, uint64) {
        return LookThroughPolicy.isUSInvestor(ILexChexBadge(address(badge)), holder);
    }

    function _holderExpiring(string memory label, string memory physical, string memory lookThrough, uint64 expiry)
        internal
        returns (address holder)
    {
        holder = makeAddr(label);
        uint256 asserts = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
        if (bytes(lookThrough).length > 0) asserts |= K_LOOKTHROUGH_JURISDICTION;

        Credential memory c;
        c.asserts = asserts;
        c.expiryDate = expiry;
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = physical;
        c.lookThroughJurisdiction = lookThrough;

        vm.prank(owner);
        badge.mint(holder, c);
    }

    /// @dev Mints one credential carrying the physical jurisdiction, plus the look-through classification
    /// when non-empty, and returns the holder.
    function _holder(string memory label, string memory physical, string memory lookThrough)
        internal
        returns (address holder)
    {
        holder = makeAddr(label);
        uint256 asserts = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
        if (bytes(lookThrough).length > 0) asserts |= K_LOOKTHROUGH_JURISDICTION;

        Credential memory c;
        c.asserts = asserts;
        c.expiryDate = uint64(block.timestamp + 3650 days);
        c.investorType = InvestorType.INDIVIDUAL;
        c.investorJurisdiction = physical;
        c.lookThroughJurisdiction = lookThrough;

        vm.prank(owner);
        badge.mint(holder, c);
    }
}

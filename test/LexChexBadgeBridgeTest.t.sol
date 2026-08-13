// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {Credential} from "../src/creds/storage/lexchexBadgeStorage.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Accreditation} from "../src/creds/storage/lexchexStorage.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {LookThroughPolicy} from "../src/libs/policies/LookThroughPolicy.sol";
import {
    ILexChexBadge,
    InvestorType,
    K_ACCREDITED,
    K_INVESTOR_JURISDICTION,
    K_INVESTOR_TYPE,
    K_QP
} from "../src/interfaces/ILexChexBadge.sol";
import {Test} from "forge-std/Test.sol";

/// @notice The LeXcheX v1 -> LeXcheXBadge bridge: v1 becomes a delegated issuer on the badge, and a holder of
/// a valid v1 accreditation can pull a sibling credential carrying the same facts.
///
/// Invariants this suite guards:
///  1. A bridged credential claims only what the v1 record establishes. K_ACCREDITED always, investor type
///     only when the free-form v1 string names a type it knows, jurisdiction only when v1 recorded one.
///  2. Authority is the badge's grant, not a role: the minter holds no role on the badge's BorgAuth, so a key
///     outside its grant cannot be asserted even though it is an admin on LeXcheX v1's own auth.
///  3. Bridging is permissionless but not repeatable: the credential goes to the v1 owner whoever calls, and
///     an unchanged v1 record cannot be bridged twice. Otherwise anyone could grow a holder's active set until
///     every compliance read on that holder ran out of gas.
///  4. The v1 record stays the source of truth for its sibling, and the sibling never outlives it: a renewal
///     re-bridges by superseding, and once the v1 accreditation stops being valid for any reason (voided,
///     burned, or expired, including an expiry a renewal moved earlier) anyone may void the badge copied from
///     it. Both sides normally lapse together, since the badge inherits the v1 expiry.
///  5. Jurisdiction is copied verbatim, the bridge does not parse it nor mint K_US_STATE for the holder due to its unstructured nature
contract LexChexBadgeBridgeTest is Test {
    uint256 constant GRANT = K_ACCREDITED | K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;

    address owner = makeAddr("owner");
    address badgeOwner = makeAddr("badgeOwner");
    address treasury = makeAddr("treasury");
    address stranger = makeAddr("stranger");
    address user = makeAddr("user");

    BorgAuth coreAuth;
    BorgAuth badgeAuth;
    CyberAgreementRegistry registry;
    LeXcheX lexchex;
    LeXcheXMinter minter;
    LeXcheXBadge badge;

    function setUp() public {
        vm.startPrank(owner);
        coreAuth = new BorgAuth(owner);
        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy(
                    address(new CyberAgreementRegistry()),
                    abi.encodeCall(CyberAgreementRegistry.initialize, (address(coreAuth)))
                )
            )
        );
        lexchex = LeXcheX(
            address(new ERC1967Proxy(address(new LeXcheX()), abi.encodeCall(LeXcheX.initialize, (address(coreAuth)))))
        );
        minter = LeXcheXMinter(
            address(
                new ERC1967Proxy(
                    address(new LeXcheXMinter()),
                    abi.encodeCall(
                        LeXcheXMinter.initialize, (address(coreAuth), address(lexchex), address(registry), treasury)
                    )
                )
            )
        );
        // v1 mints are onlyAdmin on the shared LeXcheX auth
        coreAuth.updateRole(address(minter), coreAuth.ADMIN_ROLE());
        vm.stopPrank();

        // The badge runs under its own BorgAuth, where the minter holds no role at all: its authority to issue
        // is the per-key grant below and nothing else.
        vm.startPrank(badgeOwner);
        badgeAuth = new BorgAuth(badgeOwner);
        badge = LeXcheXBadge(
            address(
                new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(badgeAuth))))
            )
        );
        badge.setIssuerKeys(address(minter), GRANT);
        vm.stopPrank();
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    function _mintV1(address to, string memory investorType, string memory jurisdiction, uint256 expiry)
        internal
        returns (uint256 tokenId)
    {
        LeXcheXMinter.MintRequest memory request = LeXcheXMinter.MintRequest({
            uuid: uint256(keccak256(abi.encode(to, investorType, jurisdiction, expiry))),
            owner: to,
            investorName: "Test Investor",
            investorType: investorType,
            investorJurisdiction: jurisdiction,
            investorContact: "test@example.com",
            mintPrice: 0,
            expiry: expiry,
            paymentToken: address(0)
        });
        vm.prank(owner);
        tokenId = minter.adminMintFor(request);
    }

    function _mintV1Accredited(address to) internal returns (uint256 tokenId) {
        return _mintV1(to, "Natural person", "", block.timestamp + 365 days);
    }

    /// @dev Renewal writes only expiry, issuance date and signature back onto the v1 record, so the
    /// descriptive fields here are the ones the accreditation already carries.
    function _renewV1(uint256 tokenId, address holder, uint256 expiry) internal {
        LeXcheXMinter.MintRequest memory renewal = LeXcheXMinter.MintRequest({
            uuid: 1,
            owner: holder,
            investorName: "Test Investor",
            investorType: "individual",
            investorJurisdiction: "",
            investorContact: "test@example.com",
            mintPrice: 0,
            expiry: expiry,
            paymentToken: address(0)
        });
        vm.prank(owner);
        minter.requestRenewalFor(renewal, tokenId);
    }

    function _evidenceHash(uint256 tokenId) internal view returns (bytes32) {
        Accreditation memory acc = lexchex.accreditations(tokenId);
        return keccak256(abi.encode(address(lexchex), tokenId, acc));
    }

    function _issuers(address issuer) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = issuer;
    }

    // ── Happy path ───────────────────────────────────────────────────────────

    function testBridgeCopiesTheV1Record() public {
        uint256 tokenId = _mintV1(user, "Natural person", "US", block.timestamp + 365 days);
        Accreditation memory acc = lexchex.accreditations(tokenId);

        vm.prank(stranger); // anyone may bridge
        uint256 badgeTokenId = minter.mintLexChexBadge(tokenId, address(badge));

        assertEq(badge.ownerOf(badgeTokenId), user, "credential must go to the v1 owner, not the caller");
        Credential memory cred = badge.getCredential(badgeTokenId);
        assertEq(cred.issuer, address(minter), "issuer must be the minter");
        assertEq(cred.asserts, K_ACCREDITED | K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION, "unexpected asserts");
        assertEq(uint8(cred.investorType), uint8(InvestorType.INDIVIDUAL), "Natural person is an individual");
        assertEq(cred.investorJurisdiction, "US", "jurisdiction must be copied verbatim");
        assertEq(cred.investorName, acc.investorName, "name must be carried over");
        assertEq(uint256(cred.expiryDate), acc.expiryDate, "expiry must match the v1 record");
        assertEq(cred.agreementId, acc.agreementId, "agreement must be carried over");
        assertEq(cred.evidenceHash, _evidenceHash(tokenId), "evidence must bind the exact v1 record");
        assertEq(cred.scope, address(0), "bridged credentials are not scoped to an SPV");
        assertEq(cred.data.length, 0, "bridge must not write a K_DATA payload");
        assertTrue(badge.isValid(badgeTokenId), "credential must be valid");
    }

    function testBridgeRecordsTheLinkPerBadge() public {
        uint256 tokenId = _mintV1Accredited(user);
        uint256 badgeTokenId = minter.mintLexChexBadge(tokenId, address(badge));

        (uint256 recorded, bool bridged) = minter.bridgedBadgeOf(tokenId, address(badge));
        assertEq(recorded, badgeTokenId, "unexpected recorded badge token");
        assertTrue(bridged, "must be recorded as bridged");
        assertEq(minter.bridgedBadge(tokenId, address(badge)), badgeTokenId + 1, "raw slot is id + 1");

        (, bool otherBadge) = minter.bridgedBadgeOf(tokenId, stranger);
        assertFalse(otherBadge, "a bridge into one badge says nothing about another");
    }

    function testBridgedCredentialAnswersAnIssuerFilteredRead() public {
        uint256 tokenId = _mintV1Accredited(user);
        minter.mintLexChexBadge(tokenId, address(badge));

        assertTrue(badge.hasValidCredentialOf(user, K_ACCREDITED), "accredited must read true");
        assertTrue(
            badge.hasValidCredentialOf(user, K_ACCREDITED, _issuers(address(minter))),
            "must answer for consumers that pin LeXcheX v1 provenance"
        );
        assertFalse(
            badge.hasValidCredentialOf(user, K_ACCREDITED, _issuers(stranger)),
            "must not answer for another issuer's provenance"
        );
    }

    // ── What the bridge refuses to claim ─────────────────────────────────────

    function testInvestorTypeMapping() public {
        assertEq(_bridgedType(user, "Natural person"), uint8(InvestorType.INDIVIDUAL), "Natural person");
        assertEq(_bridgedType(makeAddr("a"), "individual"), uint8(InvestorType.INDIVIDUAL), "individual");
        assertEq(_bridgedType(makeAddr("b"), "Individual"), uint8(InvestorType.INDIVIDUAL), "case insensitive");
        assertEq(_bridgedType(makeAddr("c"), " LLC "), uint8(InvestorType.ENTITY), "spaces trimmed");
        assertEq(_bridgedType(makeAddr("d"), "Trust"), uint8(InvestorType.ENTITY), "Trust");
        assertEq(_bridgedType(makeAddr("e"), "I"), uint8(InvestorType.UNSET), "ambiguous string stays unmapped");
        assertEq(_bridgedType(makeAddr("f"), ""), uint8(InvestorType.UNSET), "empty string stays unmapped");
        assertEq(_bridgedType(makeAddr("g"), "Sasquatch"), uint8(InvestorType.UNSET), "unknown string stays unmapped");
    }

    /// @dev Bridges one v1 record carrying `investorType` and reports the credential's type, asserting that the
    /// key is present exactly when a type was established.
    function _bridgedType(address holder, string memory investorType) internal returns (uint8) {
        uint256 tokenId = _mintV1(holder, investorType, "", block.timestamp + 365 days);
        uint256 badgeTokenId = minter.mintLexChexBadge(tokenId, address(badge));
        Credential memory cred = badge.getCredential(badgeTokenId);

        bool asserted = (cred.asserts & K_INVESTOR_TYPE) != 0;
        assertEq(asserted, cred.investorType != InvestorType.UNSET, "key and value must agree");
        assertEq(cred.asserts & K_INVESTOR_JURISDICTION, 0, "no jurisdiction on record, so none claimed");
        return uint8(cred.investorType);
    }

    function testJurisdictionIsCopiedVerbatim() public {
        uint256 tokenId = _mintV1(user, "individual", "Delaware", block.timestamp + 365 days);
        uint256 badgeTokenId = minter.mintLexChexBadge(tokenId, address(badge));

        Credential memory cred = badge.getCredential(badgeTokenId);
        assertEq(cred.investorJurisdiction, "Delaware", "string must be copied as written");
        assertTrue((cred.asserts & K_INVESTOR_JURISDICTION) != 0, "jurisdiction key must be asserted");
        (string memory value,) = badge.getInvestorJurisdiction(user);
        assertEq(value, "Delaware", "getter must return the copied string");
    }

    /// @notice The cost of copying verbatim, pinned. USJurisdictionPolicy reads only US/USA/United States as
    /// U.S., so a v1 record that put a state in the country field reads as non-U.S. in the look-through.
    function testStateNamedJurisdictionReadsNonUS() public {
        uint256 delawareToken = _mintV1(user, "individual", "Delaware", block.timestamp + 365 days);
        minter.mintLexChexBadge(delawareToken, address(badge));
        (bool isUS,) = LookThroughPolicy.isUSInvestor(ILexChexBadge(address(badge)), user);
        assertFalse(isUS, "a state name is not a spelling of the United States");

        address usHolder = makeAddr("usHolder");
        uint256 usToken = _mintV1(usHolder, "individual", "US", block.timestamp + 365 days);
        minter.mintLexChexBadge(usToken, address(badge));
        (bool usIsUS,) = LookThroughPolicy.isUSInvestor(ILexChexBadge(address(badge)), usHolder);
        assertTrue(usIsUS, "US must read U.S.");

        address unknownHolder = makeAddr("unknownHolder");
        uint256 unknownToken = _mintV1Accredited(unknownHolder);
        minter.mintLexChexBadge(unknownToken, address(badge));
        (bool unknownIsUS,) = LookThroughPolicy.isUSInvestor(ILexChexBadge(address(badge)), unknownHolder);
        assertTrue(unknownIsUS, "an unestablished jurisdiction reads U.S., the conservative default");
    }

    // ── Authority ────────────────────────────────────────────────────────────

    function testMinterIsNotABadgeAdmin() public {
        assertEq(badge.issuerKeys(address(minter)), GRANT, "grant must be exactly the bridgeable keys");
        assertEq(badgeAuth.userRoles(address(minter)), 0, "the bridge must hold no role on the badge's auth");

        Credential memory cred;
        cred.asserts = K_QP;
        cred.expiryDate = uint64(block.timestamp + 1 days);
        vm.expectRevert(abi.encodeWithSelector(ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, address(minter), K_QP));
        vm.prank(address(minter));
        badge.mint(user, cred);
    }

    function testBridgeRevertsWhenAKeyIsNotGranted() public {
        vm.prank(badgeOwner);
        badge.setIssuerKeys(address(minter), K_ACCREDITED); // investor type no longer delegated

        uint256 tokenId = _mintV1Accredited(user);
        vm.expectRevert(
            abi.encodeWithSelector(ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector, address(minter), K_INVESTOR_TYPE)
        );
        minter.mintLexChexBadge(tokenId, address(badge));
    }

    function testBridgeRevertsWhenTheGrantIsWithdrawn() public {
        vm.prank(badgeOwner);
        badge.setIssuerKeys(address(minter), 0);

        uint256 tokenId = _mintV1Accredited(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILexChexBadge.LexChexBadge_KeysNotAuthorized.selector,
                address(minter),
                K_ACCREDITED | K_INVESTOR_TYPE
            )
        );
        minter.mintLexChexBadge(tokenId, address(badge));
    }

    // ── What cannot be bridged ───────────────────────────────────────────────

    function testRevertIf_BadgeIsZero() public {
        uint256 tokenId = _mintV1Accredited(user);
        vm.expectRevert(LeXcheXMinter.InvalidBadge.selector);
        minter.mintLexChexBadge(tokenId, address(0));
    }

    function testRevertIf_AccreditationDoesNotExist() public {
        vm.expectRevert(LeXcheXMinter.AccreditationDoesNotExist.selector);
        minter.mintLexChexBadge(42, address(badge));
    }

    function testRevertIf_AccreditationVoided() public {
        uint256 tokenId = _mintV1Accredited(user);
        vm.prank(owner);
        lexchex.void(tokenId, "failed re-KYC");

        vm.expectRevert(LeXcheXMinter.AccreditationVoided.selector);
        minter.mintLexChexBadge(tokenId, address(badge));
    }

    function testRevertIf_AccreditationExpired() public {
        uint256 expiry = block.timestamp + 30 days;
        uint256 tokenId = _mintV1(user, "individual", "", expiry);

        // The boundary second: v1 still calls this valid, but the badge will not take an expiry that is not
        // in the future, so the bridge refuses it with its own error.
        vm.warp(expiry);
        assertTrue(lexchex.isValid(tokenId), "v1 is still valid at the expiry second");
        vm.expectRevert(LeXcheXMinter.AccreditationExpired.selector);
        minter.mintLexChexBadge(tokenId, address(badge));

        vm.warp(expiry + 1);
        vm.expectRevert(LeXcheXMinter.AccreditationExpired.selector);
        minter.mintLexChexBadge(tokenId, address(badge));
    }

    function testRevertIf_ExpiryOutOfRange() public {
        uint256 tokenId = _mintV1(user, "individual", "", type(uint256).max);
        vm.expectRevert(LeXcheXMinter.ExpiryOutOfRange.selector);
        minter.mintLexChexBadge(tokenId, address(badge));
    }

    // ── Repeat bridging ──────────────────────────────────────────────────────

    function testRevertIf_AccreditationUnchanged() public {
        uint256 tokenId = _mintV1Accredited(user);
        minter.mintLexChexBadge(tokenId, address(badge));

        vm.expectRevert(LeXcheXMinter.AccreditationUnchanged.selector);
        minter.mintLexChexBadge(tokenId, address(badge));

        vm.prank(stranger);
        vm.expectRevert(LeXcheXMinter.AccreditationUnchanged.selector);
        minter.mintLexChexBadge(tokenId, address(badge));

        assertEq(badge.getActiveTokenIds(user).length, 1, "repeat calls must not grow the holder's active set");
    }

    function testRenewalRebridgeSupersedes() public {
        uint256 tokenId = _mintV1(user, "individual", "", block.timestamp + 30 days);
        uint256 first = minter.mintLexChexBadge(tokenId, address(badge));

        uint256 newExpiry = block.timestamp + 365 days;
        vm.warp(block.timestamp + 1);
        _renewV1(tokenId, user, newExpiry);

        uint256 second = minter.mintLexChexBadge(tokenId, address(badge));

        assertFalse(badge.isValid(first), "the superseded credential must be voided");
        assertTrue(badge.isValid(second), "the renewed credential must be valid");
        assertEq(uint256(badge.getCredential(second).expiryDate), newExpiry, "must carry the renewed expiry");
        assertEq(badge.getActiveTokenIds(user).length, 1, "the stale credential must leave the active set");
        (uint256 recorded,) = minter.bridgedBadgeOf(tokenId, address(badge));
        assertEq(recorded, second, "the link must point at the live credential");
    }

    function testRebridgeAfterAnAdminVoidNeedsAChangedRecord() public {
        uint256 tokenId = _mintV1(user, "individual", "", block.timestamp + 365 days);
        uint256 first = minter.mintLexChexBadge(tokenId, address(badge));

        vm.prank(badgeOwner);
        badge.void(first, "sanctions hit");

        // The v1 record has not changed, so the void stands
        vm.expectRevert(LeXcheXMinter.AccreditationUnchanged.selector);
        minter.mintLexChexBadge(tokenId, address(badge));

        // A renewal is a new attestation, so it may be bridged again
        vm.warp(block.timestamp + 1);
        _renewV1(tokenId, user, block.timestamp + 730 days);

        uint256 second = minter.mintLexChexBadge(tokenId, address(badge));
        assertTrue(badge.isValid(second), "a changed record mints a fresh credential");
        assertEq(badge.getActiveTokenIds(user).length, 1, "the voided credential is already out of the set");
    }

    function testBridgeIntoTwoBadgesIsTrackedSeparately() public {
        vm.startPrank(badgeOwner);
        LeXcheXBadge second = LeXcheXBadge(
            address(
                new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(badgeAuth))))
            )
        );
        second.setIssuerKeys(address(minter), GRANT);
        vm.stopPrank();

        uint256 tokenId = _mintV1Accredited(user);
        uint256 firstBadgeToken = minter.mintLexChexBadge(tokenId, address(badge));
        uint256 secondBadgeToken = minter.mintLexChexBadge(tokenId, address(second));

        assertTrue(badge.isValid(firstBadgeToken), "first badge holds a valid credential");
        assertTrue(second.isValid(secondBadgeToken), "second badge holds a valid credential");
        assertEq(minter.bridgedBadge(tokenId, address(badge)), firstBadgeToken + 1, "first link");
        assertEq(minter.bridgedBadge(tokenId, address(second)), secondBadgeToken + 1, "second link");
    }

    // ── Revocation ───────────────────────────────────────────────────────────

    function testVoidPropagatesFromV1() public {
        uint256 tokenId = _mintV1Accredited(user);
        uint256 badgeTokenId = minter.mintLexChexBadge(tokenId, address(badge));

        vm.expectRevert(LeXcheXMinter.AccreditationStillValid.selector);
        minter.voidLexChexBadge(tokenId, address(badge));

        vm.prank(owner);
        lexchex.void(tokenId, "failed re-KYC");

        vm.prank(stranger); // anyone may propagate it
        minter.voidLexChexBadge(tokenId, address(badge));

        assertFalse(badge.isValid(badgeTokenId), "the sibling credential must be voided");
        assertEq(badge.getActiveTokenIds(user).length, 0, "and evicted from the active set");
        assertFalse(badge.hasValidCredentialOf(user, K_ACCREDITED), "accredited must stop reading true");
    }

    function testVoidPropagatesAfterAV1Burn() public {
        uint256 tokenId = _mintV1Accredited(user);
        uint256 badgeTokenId = minter.mintLexChexBadge(tokenId, address(badge));

        vm.prank(user);
        lexchex.burn(tokenId);

        minter.voidLexChexBadge(tokenId, address(badge));
        assertFalse(badge.isValid(badgeTokenId), "a burned accreditation leaves no valid sibling");
    }

    /// @notice The one way a sibling can outlive its source: v1 renewal accepts an earlier expiry, and the
    /// badge keeps the longer one it inherited. Reading v1's own validity is what lets anyone close that.
    function testVoidPropagatesAfterARenewalShortensTheV1Expiry() public {
        uint256 tokenId = _mintV1(user, "individual", "", block.timestamp + 365 days);
        uint256 badgeTokenId = minter.mintLexChexBadge(tokenId, address(badge));

        uint256 shortened = block.timestamp + 1 days;
        _renewV1(tokenId, user, shortened);
        vm.warp(shortened + 1);

        assertFalse(lexchex.isValid(tokenId), "the v1 accreditation has lapsed");
        assertTrue(badge.isValid(badgeTokenId), "the sibling still carries the longer expiry it inherited");

        vm.prank(stranger); // anyone may close it
        minter.voidLexChexBadge(tokenId, address(badge));

        assertFalse(badge.isValid(badgeTokenId), "the sibling must not outlive its source");
        assertEq(badge.getActiveTokenIds(user).length, 0, "and must leave the active set");
    }

    function testRevertIf_VoidingWhatWasNeverBridged() public {
        uint256 tokenId = _mintV1Accredited(user);
        vm.expectRevert(LeXcheXMinter.BadgeNotBridged.selector);
        minter.voidLexChexBadge(tokenId, address(badge));
    }

    function testRevertIf_VoidingTwice() public {
        uint256 tokenId = _mintV1Accredited(user);
        minter.mintLexChexBadge(tokenId, address(badge));
        vm.prank(owner);
        lexchex.void(tokenId, "failed re-KYC");
        minter.voidLexChexBadge(tokenId, address(badge));

        vm.expectRevert(LeXcheXMinter.BadgeAlreadyInvalid.selector);
        minter.voidLexChexBadge(tokenId, address(badge));
    }

    // ── The v1 workflow is untouched ─────────────────────────────────────────

    function testV1MintingIsUnaffectedByTheBridge() public {
        uint256 tokenId = _mintV1Accredited(user);
        assertEq(lexchex.ownerOf(tokenId), user, "v1 mint must still work on its own");
        assertTrue(lexchex.hasValidLexCheX(user), "v1 read must still work");
        assertEq(badge.balanceOf(user), 0, "a v1 mint must not touch the badge");
    }
}

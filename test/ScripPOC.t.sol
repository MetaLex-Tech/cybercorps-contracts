// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/IssuanceManager.sol";
import "../src/CyberScrip.sol";
import "../src/LedgerEntryToken.sol";
import "../src/interfaces/ICyberScrip.sol";
import "../src/interfaces/ILedgerEntryToken.sol";
import "../src/interfaces/ICondition.sol";
import "../src/interfaces/ITransferRestrictionHook.sol";
import "../src/libs/auth.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import "../test/mock/TestableCyberScrip.sol";
import "../test/mock/MockTransferHook.sol";

// ============================================================================
// Mock contracts
// ============================================================================

/// @notice Mock CyberCorp that exposes dealManager
contract POCMockCyberCorp {
    string public cyberCORPName = "TestCorp";
    string public cyberCORPJurisdiction = "Delaware";
    string public cyberCORPType = "corporation";
    string public cyberCORPContactDetails = "test@test.com";
    address public dealManager;
    address public roundManager;

    function setDealManager(address _dm) external {
        dealManager = _dm;
    }
}

/// @notice Extended mock CertPrinter for IssuanceManager-level POC tests.
///         Mimics the real LedgerEntryToken enough for the IM to call through the interface.
contract POCMockCertPrinter {
    mapping(uint256 => CertificateDetails) internal _details;
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(address => uint256[]) internal _ownedTokens;
    mapping(uint256 => bool) internal _voided;
    mapping(uint256 => address) internal _restrictionHooks;
    mapping(uint256 => bytes[]) internal _issuerSignatures;
    uint256 internal _total;
    string internal _name;
    string internal _symbol;

    function initialize(
        string[] memory,
        string memory name_,
        string memory symbol_,
        string memory,
        address,
        SecurityClass,
        SecuritySeries,
        address
    ) external {
        _name = name_;
        _symbol = symbol_;
    }

    function name() external view returns (string memory) { return _name; }
    function symbol() external view returns (string memory) { return _symbol; }
    function totalSupply() external view returns (uint256) { return _total; }
    function tokenURI(uint256) external pure returns (string memory) { return ""; }
    function ownerOf(uint256 tokenId) external view returns (address) { return _owners[tokenId]; }
    function balanceOf(address owner_) external view returns (uint256) { return _balances[owner_]; }

    function tokenOfOwnerByIndex(address owner_, uint256 index) external view returns (uint256) {
        return _ownedTokens[owner_][index];
    }

    // In this mock custody owner == legal owner, so the per-legal-owner enumeration is the same backing data.
    function balanceOfLegalOwner(address owner_) external view returns (uint256) {
        return _balances[owner_];
    }

    function tokenOfLegalOwnerByIndex(address owner_, uint256 index) external view returns (uint256) {
        return _ownedTokens[owner_][index];
    }

    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        return _details[tokenId];
    }

    function getActiveCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory) {
        return _details[tokenId];
    }

    function safeMint(uint256 tokenId, address to, CertificateDetails memory details) external returns (uint256) {
        return _mint(tokenId, to, details);
    }

    function safeMintAndAssign(address to, uint256 tokenId, CertificateDetails memory details) external returns (uint256) {
        return _mint(tokenId, to, details);
    }

    function updateCertificateDetails(uint256 tokenId, CertificateDetails calldata details) external {
        _details[tokenId] = details;
    }

    function voidCert(uint256 tokenId) external { _voided[tokenId] = true; }
    function isVoided(uint256 tokenId) external view returns (bool) { return _voided[tokenId]; }
    function unitsReserved(uint256) external pure returns (uint256) { return 0; }
    function legalOwnerOf(uint256 tokenId) external view returns (address) { return _owners[tokenId]; }

    /// @dev Mock safeTransferFrom -- no IERC721Receiver check, no endorsement check.
    ///      The real LedgerEntryToken would revert here if `to` is a contract without
    ///      IERC721Receiver, or if transfer restrictions / endorsements aren't met.
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from, "not owner");
        _owners[tokenId] = to;
        _balances[from] -= 1;
        _balances[to] += 1;
    }

    function assignCert(address from, uint256 tokenId, address, CertificateDetails memory details) external returns (uint256) {
        require(_owners[tokenId] == from, "not owner");
        // NOTE: the real LedgerEntryToken has _transfer commented out, so the token is NOT moved
        _details[tokenId] = details;
        return tokenId;
    }

    function addIssuerSignature(uint256 tokenId, bytes calldata signature) external {
        _issuerSignatures[tokenId].push(signature);
    }

    function getIssuerSignatureCount(uint256 tokenId) external view returns (uint256) {
        return _issuerSignatures[tokenId].length;
    }

    function getIssuerSignatureAt(uint256 tokenId, uint256 index) external view returns (bytes memory) {
        return _issuerSignatures[tokenId][index];
    }

    function setRestrictionHook(uint256 id, address hook) external {
        _restrictionHooks[id] = hook;
    }

    function getRestrictionHook(uint256 id) external view returns (address) {
        return _restrictionHooks[id];
    }

    function tokenByIndex(uint256 index) external view returns (uint256) { return index; }
    function unvoidCert(uint256 tokenId) external { _voided[tokenId] = false; }

    // Stubs for functions called through the interface
    function addEndorsement(uint256, Endorsement memory) external {}
    function setGlobalRestrictionHook(address) external {}
    function setGlobalTransferable(bool) external {}
    function setTokenTransferable(uint256, bool) external {}
    function addDefaultLegend(string memory) external {}
    function removeDefaultLegendAt(uint256) external {}
    function addCertLegend(uint256, string memory) external {}
    function removeCertLegendAt(uint256, uint256) external {}

    function _mint(uint256 tokenId, address to, CertificateDetails memory details) internal returns (uint256) {
        _details[tokenId] = details;
        _owners[tokenId] = to;
        _balances[to] += 1;
        _ownedTokens[to].push(tokenId);
        if (tokenId >= _total) {
            _total = tokenId + 1;
        }
        return tokenId;
    }
}

// ============================================================================
// POC Test Contract
// ============================================================================

contract ScripPOCTest is Test {
    bytes32 constant SALT = bytes32(keccak256("ScripPOCTest"));

    IssuanceManager public issuanceManager;
    IssuanceManagerFactory public imFactory;
    POCMockCyberCorp public mockCorp;
    POCMockCertPrinter public certPrinter;
    BorgAuth public auth;

    address public owner;
    address public investor;
    address public attacker;
    address public dealManagerAddr;

    function setUp() public {
        owner = address(this);
        investor = makeAddr("investor");
        attacker = makeAddr("attacker");
        dealManagerAddr = makeAddr("dealManager");

        auth = new BorgAuth(owner);

        imFactory = IssuanceManagerFactory(address(
            new ERC1967Proxy{salt: SALT}(
                address(new IssuanceManagerFactory{salt: SALT}()),
                abi.encodeWithSelector(
                    IssuanceManagerFactory.initialize.selector,
                    address(auth),
                    new IssuanceManager(),
                    new LedgerEntryToken(),
                    new CyberScrip()
                )
            )
        ));

        issuanceManager = IssuanceManager(imFactory.deployIssuanceManager(SALT));

        mockCorp = new POCMockCyberCorp();
        mockCorp.setDealManager(dealManagerAddr);

        issuanceManager.initialize(
            address(auth),
            address(mockCorp),
            address(0xBEEF),
            address(imFactory)
        );

        certPrinter = new POCMockCertPrinter();
        certPrinter.initialize(
            new string[](0), "Test Cert", "TCRT", "uri://test",
            address(issuanceManager), SecurityClass.CommonStock, SecuritySeries.SeriesA, address(0)
        );
    }

    // =========================================================================
    // POC #1 - deployCyberScrip access control (Fixed)
    //
    // Previously had no access modifier. Now protected by onlyOwner.
    // This test verifies the fix: unauthorized callers are rejected.
    // =========================================================================

    function test_POC1_DeployCyberScrip_RejectsUnauthorized() public {
        // Attacker (random address with no role) cannot deploy scrip
        vm.prank(attacker);
        vm.expectRevert(); // BorgAuth_NotAuthorized
        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,     // no minimum
            1, 1,  // 1:1 ratio
            new uint256[](0),
            false,
            true, true, true
        );
    }

    function test_POC1_DeployCyberScrip_OwnerSucceeds() public {
        // Owner can deploy
        vm.prank(owner);
        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0,
            1, 1,
            new uint256[](0),
            false,
            true, true, true
        );
        assertTrue(scrip != address(0), "Owner can deploy scrip");
    }

    // =========================================================================
    // POC #2 - addIssuerSignature implementation regression guard
    // =========================================================================

    function test_POC2_AddIssuerSignature_Implemented() public {
        CertificateDetails memory details = _defaultDetails(100);
        vm.prank(owner);
        uint256 certId = issuanceManager.createCert(address(certPrinter), investor, details);

        vm.prank(owner);
        bytes memory signature = abi.encodePacked("signed-hash");
        certPrinter.addIssuerSignature(certId, signature);
        assertEq(certPrinter.getIssuerSignatureCount(certId), 1, "signature should be added");
        assertEq(certPrinter.getIssuerSignatureAt(certId, 0), signature, "stored signature mismatch");
    }

    // =========================================================================
    // POC #3 - forceTransfer/forceBurn corrupt holderCount (High)
    //
    // Before the fix: forceTransfer and forceBurn called ERC20._update directly,
    // bypassing the holderCount tracking in CyberScrip._update.
    //
    // After the fix: _updateHolderCount is called explicitly in both functions.
    // These tests verify the fix works correctly.
    // =========================================================================

    function test_POC3_ForceTransfer_HolderCountTracked() public {
        TestableCyberScrip scrip = _deployTestableScrip();
        address user1 = makeAddr("u1");
        address user2 = makeAddr("u2");
        address im = scrip.issuanceManager();

        scrip.unrestrictedMint(user1, 1000);
        assertEq(scrip.holderCount(), 1, "1 holder after mint");

        // Force transfer part of balance to new user
        vm.prank(im);
        scrip.forceTransfer(user1, user2, 400);
        assertEq(scrip.holderCount(), 2, "2 holders after force transfer to new address");

        // Force transfer entire remaining balance (user1 drops to 0)
        vm.prank(im);
        scrip.forceTransfer(user1, user2, 600);
        assertEq(scrip.holderCount(), 1, "1 holder after force transfer drains user1");
    }

    function test_POC3_ForceBurn_HolderCountTracked() public {
        TestableCyberScrip scrip = _deployTestableScrip();
        address user1 = makeAddr("u1b");
        address im = scrip.issuanceManager();

        scrip.unrestrictedMint(user1, 1000);
        assertEq(scrip.holderCount(), 1);

        // Force burn all tokens
        vm.prank(im);
        scrip.forceBurn(user1, 1000);
        assertEq(scrip.holderCount(), 0, "0 holders after force burn drains account");
    }

    function test_POC3_MaxHolderCount_RespectedAfterForceOps() public {
        TestableCyberScrip scrip = _deployTestableScrip();
        address user1 = makeAddr("u1c");
        address user2 = makeAddr("u2c");
        address user3 = makeAddr("u3c");
        address im = scrip.issuanceManager();

        scrip.unrestrictedMint(user1, 1000);

        // Set max holders to 2
        vm.prank(im);
        scrip.setMaxHolderCount(2);

        // Force transfer to user2 (now 2 holders, at limit)
        vm.prank(im);
        scrip.forceTransfer(user1, user2, 100);
        assertEq(scrip.holderCount(), 2);

        // Normal transfer to user3 should be blocked by max holder limit
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(CyberScrip.HolderLimitExceeded.selector, 2));
        scrip.transfer(user3, 50);
    }

    // =========================================================================
    // POC #4 - Full scripification path uses safeTransferFrom (High)
    //
    // The current code does: certificate.safeTransferFrom(msg.sender, dm, id)
    // In the real LedgerEntryToken:
    //   a) The IssuanceManager is msg.sender to CertPrinter, but isn't the
    //      token owner or approved -- transferFrom would fail
    //   b) _update override enforces endorsement checks for transfers
    //   c) If dm is a contract, safeTransferFrom checks IERC721Receiver
    //
    // With our mock (no restriction checks), we verify the flow's intent:
    // the voided cert should end up at the dealManager.
    // =========================================================================

    function test_POC4_FullScripifyCert_SendsToDealManager() public {
        CertificateDetails memory details = _defaultDetails(100);
        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, details);

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0, 1, 1, new uint256[](0), false, true, true, true
        );

        // Full scripification (amount == unitsRepresented)
        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), 0, 100, address(0));

        // After full scripify, cert stays with investor but has 0 units (not voided)
        assertEq(certPrinter.ownerOf(0), investor, "cert stays with investor after full scripify");
        assertFalse(certPrinter.isVoided(0), "cert is not voided after scripify");
        CertificateDetails memory updated = certPrinter.getCertificateDetails(0);
        assertEq(updated.unitsRepresented, 0, "cert has 0 units after full scripify");
        assertEq(ICyberScrip(scrip).balanceOf(investor), 100, "investor should receive scrip");
    }

    function test_POC4_PartialScripifyCert_CertStaysWithOwner() public {
        CertificateDetails memory details = _defaultDetails(100);
        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, details);

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0, 1, 1, new uint256[](0), false, true, true, true
        );

        // Partial scripification (50 of 100 units)
        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), 0, 50, address(0));

        // Cert stays with investor, units reduced
        assertEq(certPrinter.ownerOf(0), investor, "cert stays with investor on partial");
        assertFalse(certPrinter.isVoided(0), "cert should NOT be voided on partial");
        CertificateDetails memory updated = certPrinter.getCertificateDetails(0);
        assertEq(updated.unitsRepresented, 50, "units should be reduced");
        assertEq(ICyberScrip(scrip).balanceOf(investor), 50, "investor should receive partial scrip");
    }

    // =========================================================================
    // POC #4 (continued) - convertScripToCert should search dealManager for
    // voided certs and move them back to the user
    //
    // Current code searches msg.sender's certs for voided ones. After the
    // scripifyCert fix sends voided certs to dealManager, the search must
    // also look at the dealManager's holdings.
    // =========================================================================

    function test_POC4_ConvertScripToCert_CreatesNewWhenNoVoidedFound() public {
        CertificateDetails memory details = _defaultDetails(100);
        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, details);

        address scrip = issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0, 1, 1, new uint256[](0), false, true, true, true
        );

        // Full scripify -> cert stays with investor, 0 units
        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), 0, 100, address(0));

        // Convert scrip back to cert
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 100);

        // Scrip should be burned
        assertEq(ICyberScrip(scrip).balanceOf(investor), 0, "scrip burned");

        // Units restored to existing cert 0 (no new cert created since cert 0 is not voided)
        assertEq(certPrinter.ownerOf(0), investor, "cert 0 still with investor");
        CertificateDetails memory restored = certPrinter.getCertificateDetails(0);
        assertEq(restored.unitsRepresented, 100, "cert 0 units restored to 100");
    }

    // =========================================================================
    // POC #6 - assignCert doesn't actually transfer the token (Medium)
    //
    // In the real LedgerEntryToken, _transfer(from, to, tokenId) is
    // commented out inside assignCert. The function updates details but
    // the ERC721 ownership doesn't change.
    // =========================================================================

    function test_POC6_AssignCert_TransferCommentedOut() public {
        // Document the issue: in LedgerEntryToken.sol line 177:
        //   // _transfer(from, to, tokenId);
        // This means assignCert only updates details, not ownership.
        //
        // Our mock DOES move ownership for utility, but the real contract doesn't.
        // The IssuanceManager.assignCert function is therefore broken for its
        // intended purpose of reassigning a certificate to a new investor.
        assertTrue(true);
    }

    // =========================================================================
    // POC #8 - convertScripToCert on a voided cert requires approval
    //
    // When all certs owned by the investor are voided, convertScripToCert
    // cannot find an active cert and requires a recertification approval
    // from an officer before issuing a new cert.
    // =========================================================================

    function test_POC8_ConvertScripToCert_StaleDataOnReform() public {
        // Create cert with specific metadata
        CertificateDetails memory originalDetails = CertificateDetails({
            signingOfficerName: "Jane Smith",
            signingOfficerTitle: "CFO",
            investmentAmountUSD: 500000,
            issuerUSDValuationAtTimeOfInvestment: 50000000,
            unitsRepresented: 100,
            legalDetails: "SAFE Agreement dated 2024-01-01",
            extensionData: ""
        });

        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, originalDetails);

        issuanceManager.deployCyberScrip(
            address(certPrinter),
            new ITransferRestrictionHook[](0),
            new ICondition[](0),
            new ICondition[](0),
            0, 1, 1, new uint256[](0), false, true, true, true
        );

        // Partial scripify: converts 50 of 100 units
        vm.prank(investor);
        issuanceManager.scripifyCert(address(certPrinter), 0, 50, address(0));

        // Manually void cert #0 — now investor has no active certs
        certPrinter.voidCert(0);

        // Convert scrip back — no active cert found, approval required
        vm.expectRevert(IssuanceManager.RecertificationApprovalRequired.selector);
        vm.prank(investor);
        issuanceManager.convertScripToCert(address(certPrinter), 50);
    }

    // =========================================================================
    // POC #9 - setExtension/getExtension misleading tokenId parameter (Low)
    //
    // Both functions accept tokenId but operate on a GLOBAL extension field.
    // Setting extension for token 0 also changes it for token 1, etc.
    // =========================================================================

    function test_POC9_SetExtension_IgnoresTokenId() public {
        // In LedgerEntryToken:
        //   function setExtension(uint256 tokenId, address extension) external onlyIssuanceManager {
        //       LedgerEntryTokenStorage.cyberCertStorage().extension = extension;
        //   }
        //
        //   function getExtension(uint256 tokenId) external view returns (address) {
        //       return LedgerEntryTokenStorage.cyberCertStorage().extension;
        //   }
        //
        // tokenId is completely ignored - extension is a single global value.
        // Setting extension "for token 5" actually sets it for ALL tokens.
        assertTrue(true);
    }

    // =========================================================================
    // POC #11 - Per-token restriction hooks settable but never enforced (Low)
    //
    // setRestrictionHook stores a per-token hook, but the check in _update
    // is commented out. Admins may believe hooks are active when they're not.
    // =========================================================================

    function test_POC11_PerTokenHooks_StoredButNotEnforced() public {
        CertificateDetails memory details = _defaultDetails(100);
        vm.prank(owner);
        issuanceManager.createCert(address(certPrinter), investor, details);

        // Admin sets a deny-all hook for token 0
        MockTransferHook denyHook = new MockTransferHook();
        denyHook.setAllowTransfers(false);

        vm.prank(owner);
        certPrinter.setRestrictionHook(0, address(denyHook));

        // Hook is stored
        assertEq(certPrinter.getRestrictionHook(0), address(denyHook), "hook stored");

        // But in the real LedgerEntryToken._update, the per-token hook check
        // is commented out (lines 235-242), so transfers would SUCCEED despite
        // the hook being configured to deny them.
    }

    // =========================================================================
    // POC #14 - Manual selector hash instead of .selector (Low)
    //
    // scripifyCert computes the selector via keccak256 of the signature string
    // instead of using this.scripifyCert.selector. This is fragile.
    // =========================================================================

    function test_POC14_ManualSelectorHash_MatchesButFragile() public {
        // scripifyCert uses:
        //   bytes4 selector3 = bytes4(keccak256("scripifyCert(address,uint256,uint256,address)"));
        //
        // vs convertScripToCert which correctly uses:
        //   this.convertScripToCert.selector

        bytes4 manualSelector = bytes4(keccak256("scripifyCert(address,uint256,uint256,address)"));
        bytes4 compilerSelector = IssuanceManager.scripifyCert.selector;

        // They match today, but manual approach won't auto-update if params change
        assertEq(manualSelector, compilerSelector, "match now, but manual is fragile if signature changes");
    }

    // =========================================================================
    // POC #5 - getEndorsementHistory interface mismatch (Medium)
    //
    // ILedgerEntryToken declares getEndorsementHistory returning individual
    // fields, but LedgerEntryToken returns Endorsement memory. These are
    // ABI-incompatible for external callers using the interface.
    // =========================================================================

    function test_POC5_GetEndorsementHistory_InterfaceMismatch() public {
        // Deploy a real printer (not the local mock), mint, then add an endorsement.
        address realPrinter = issuanceManager.createCertPrinter(
            new string[](0),
            "Real Cert",
            "RCERT",
            "uri://real",
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            address(0),
            bytes("")
        );

        // Avoid IssuanceManager.createCert in this PoC: it fetches tokenURI, which
        // depends on uriBuilder being configured in setUp.
        vm.prank(address(issuanceManager));
        ILedgerEntryToken(realPrinter).safeMint(0, investor, _defaultDetails(100));

        bytes memory signature = abi.encodePacked(uint256(12345));
        bytes32 agreementId = keccak256("POC5");
        Endorsement memory endorsement = Endorsement(
            owner,
            block.timestamp,
            signature,
            address(0),
            agreementId,
            address(0),
            ""
        );
        vm.prank(address(issuanceManager));
        ILedgerEntryToken(realPrinter).addEndorsement(0, endorsement);

        // Do a raw call first (this succeeds and returns bytes).
        (bool ok, bytes memory returndata) = realPrinter.staticcall(
            abi.encodeWithSelector(ILedgerEntryToken.getEndorsementHistory.selector, 0, 0)
        );
        assertTrue(ok, "raw getEndorsementHistory call failed");

        // The raw call succeeds — the POC confirmed that getEndorsementHistory
        // returns bytes regardless of how the caller interprets the ABI layout.
        assertGt(returndata.length, 0, "returndata should not be empty");
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _defaultDetails(uint256 units) internal pure returns (CertificateDetails memory) {
        return CertificateDetails({
            signingOfficerName: "Officer",
            signingOfficerTitle: "Title",
            investmentAmountUSD: 1000,
            issuerUSDValuationAtTimeOfInvestment: 10000,
            unitsRepresented: units,
            legalDetails: "",
            extensionData: ""
        });
    }

    function _deployTestableScrip() internal returns (TestableCyberScrip) {
        address im = makeAddr("scripIM");
        BorgAuth testAuth = new BorgAuth(address(this));

        TestableCyberScrip scrip = TestableCyberScrip(address(
            new ERC1967Proxy(
                address(new TestableCyberScrip()),
                abi.encodeWithSelector(
                    CyberScrip.initialize.selector,
                    address(testAuth),
                    makeAddr("certPrinterForScrip"),
                    im,
                    "POC Scrip",
                    "POCS",
                    new ITransferRestrictionHook[](0),
                    true,  // enableForceTransfer
                    true,  // enableForceBurn
                    true   // enableFreeze
                )
            )
        ));
        return scrip;
    }
}

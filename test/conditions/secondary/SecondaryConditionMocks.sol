// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC1967Proxy} from "../../../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CategoryKind} from "../../../src/creds/storage/lexchexBadgeStorage.sol";
import {CertificateDetails} from "../../../src/interfaces/ICyberCertPrinter.sol";
import {ExemptionPathway, Offer, OfferSide, SecondaryEscrow} from "../../../src/interfaces/ISecondaryTradeStorage.sol";
import {BorgAuth} from "../../../src/libs/auth.sol";
import {Test} from "forge-std/Test.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Lightweight mocks — just the surface each secondary-trading condition reads.
// These keep the condition unit tests fast and let a single test set up dozens of
// distinct legal/economic scenarios (expired badge, wrong jurisdiction, stale
// disclosure, unmet hold, …) that would be impractical against the full stack.
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Answers the three IDealManager getters the conditions call, and exposes AUTH() so setters
/// gated on the DealManager's own BorgAuth (LegalOpinion, GPLPApproval, TimeSettlement) resolve here.
contract MockDealManager {
    address public AUTH;
    uint256 internal settlementWindow;
    mapping(bytes32 => Offer) internal offers;
    mapping(bytes32 => SecondaryEscrow) internal escrows;

    constructor(address auth_) {
        AUTH = auth_;
    }

    function setSettlementWindow(uint256 w) external {
        settlementWindow = w;
    }

    function getSettlementWindow() external view returns (uint256) {
        return settlementWindow;
    }

    function setOffer(bytes32 id, Offer memory o) external {
        offers[id] = o;
    }

    function getOffer(bytes32 id) external view returns (Offer memory) {
        return offers[id];
    }

    function setEscrow(bytes32 id, SecondaryEscrow memory e) external {
        escrows[id] = e;
    }

    function getSecondaryEscrow(bytes32 id) external view returns (SecondaryEscrow memory) {
        return escrows[id];
    }
}

/// @notice An SPV/target address that only needs to advertise its BorgAuth for the per-SPV setters.
contract MockAuthTarget {
    address public AUTH;

    constructor(address auth_) {
        AUTH = auth_;
    }
}

/// @notice Configurable LeXcheXBadge credential layer.
contract MockBadge {
    mapping(address => mapping(bytes32 => bool)) internal categoryCred;
    mapping(bytes32 => bool) internal kindCred;
    mapping(address => bytes2) internal usState;
    mapping(address => uint32) internal boCount;
    mapping(address => string) internal jurisdiction;
    mapping(address => string) internal regulatoryJurisdiction;

    function _kindKey(address owner, CategoryKind kind, string memory filter) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, kind, filter));
    }

    function setValidCredential(address owner, bytes32 categoryId, bool v) external {
        categoryCred[owner][categoryId] = v;
    }

    function setValidKind(address owner, CategoryKind kind, string memory filter, bool v) external {
        kindCred[_kindKey(owner, kind, filter)] = v;
    }

    function setUsState(address owner, bytes2 s) external {
        usState[owner] = s;
    }

    function setBeneficialOwnerCount(address owner, uint32 c) external {
        boCount[owner] = c;
    }

    function setInvestorJurisdiction(address owner, string memory j) external {
        jurisdiction[owner] = j;
    }

    function setRegulatoryJurisdiction(address owner, string memory j) external {
        regulatoryJurisdiction[owner] = j;
    }

    function hasValidCredential(address owner, bytes32 categoryId) external view returns (bool) {
        return categoryCred[owner][categoryId];
    }

    function hasValidCredentialOfKind(address owner, CategoryKind kind, string memory filter)
        external
        view
        returns (bool)
    {
        return kindCred[_kindKey(owner, kind, filter)];
    }

    function getUsState(address owner) external view returns (bytes2) {
        return usState[owner];
    }

    function getBeneficialOwnerCount(address owner) external view returns (uint32) {
        return boCount[owner];
    }

    function getInvestorJurisdiction(address owner) external view returns (string memory) {
        return jurisdiction[owner];
    }

    function getRegulatoryJurisdiction(address owner) external view returns (string memory) {
        return regulatoryJurisdiction[owner];
    }

    function isUSInvestor(address owner) external view returns (bool) {
        return _isUS(regulatoryJurisdiction[owner]) || _isUS(jurisdiction[owner]);
    }

    function _isUS(string memory j) private pure returns (bool) {
        bytes32 h = keccak256(bytes(j));
        return h == keccak256("US") || h == keccak256("USA") || h == keccak256("United States");
    }
}

/// @notice Configurable CyberAgreementRegistry surface (signatures + per-signer party values).
contract MockRegistry {
    mapping(bytes32 => bool) internal signed;
    mapping(bytes32 => mapping(address => string[])) internal signerValues;

    function setAllPartiesSigned(bytes32 id, bool v) external {
        signed[id] = v;
    }

    function setSignerValues(bytes32 id, address signer, string[] memory values) external {
        signerValues[id][signer] = values;
    }

    function allPartiesSigned(bytes32 id) external view returns (bool) {
        return signed[id];
    }

    function getSignerValues(bytes32 id, address signer) external view returns (string[] memory) {
        return signerValues[id][signer];
    }
}

/// @notice Configurable CyberCertPrinter surface (per-lot acquisition anchor, tacking extension, holders).
contract MockCertPrinter {
    mapping(uint256 => uint64) internal acqTs;
    mapping(uint256 => bytes) internal ext;
    address internal extensionAddr;
    mapping(address => uint256) internal legalBalance;
    mapping(uint256 => address) internal legalOwner;
    mapping(uint256 => uint256) internal tokenAtIndex;
    uint256 internal holders;
    uint256 internal supply;
    uint256 internal lookThroughHolders;
    uint256 internal usLookThroughHolders;
    mapping(address => bool) internal legalHolder;

    function setAcquisitionTimestamp(uint256 tokenId, uint64 ts) external {
        acqTs[tokenId] = ts;
    }

    function setExtensionData(uint256 tokenId, bytes memory data) external {
        ext[tokenId] = data;
    }

    function setExtension(address _extension) external {
        extensionAddr = _extension;
    }

    function getExtension(uint256) external view returns (address) {
        return extensionAddr;
    }

    function setBalanceOfLegalOwner(address owner, uint256 bal) external {
        legalBalance[owner] = bal;
    }

    function setHolderCount(uint256 c) external {
        holders = c;
    }

    function setLookThroughHolderCount(uint256 c) external {
        lookThroughHolders = c;
    }

    function setUsLookThroughHolderCount(uint256 c) external {
        usLookThroughHolders = c;
    }

    function setIsLegalHolder(address owner, bool v) external {
        legalHolder[owner] = v;
    }

    function setTotalSupply(uint256 s) external {
        supply = s;
    }

    function setTokenAt(uint256 index, uint256 tokenId, address owner) external {
        tokenAtIndex[index] = tokenId;
        legalOwner[tokenId] = owner;
    }

    function acquisitionTimestamp(uint256 tokenId) external view returns (uint64) {
        return acqTs[tokenId];
    }

    function getCertificateDetails(uint256 tokenId) external view returns (CertificateDetails memory d) {
        d.extensionData = ext[tokenId];
    }

    function balanceOfLegalOwner(address owner) external view returns (uint256) {
        return legalBalance[owner];
    }

    function holderCount() external view returns (uint256) {
        return holders;
    }

    function lookThroughHolderCount() external view returns (uint256) {
        return lookThroughHolders;
    }

    function usLookThroughHolderCount() external view returns (uint256) {
        return usLookThroughHolders;
    }

    function isLegalHolder(address owner) external view returns (bool) {
        return legalHolder[owner];
    }

    function totalSupply() external view returns (uint256) {
        return supply;
    }

    function tokenByIndex(uint256 index) external view returns (uint256) {
        return tokenAtIndex[index];
    }

    function legalOwnerOf(uint256 tokenId) external view returns (address) {
        return legalOwner[tokenId];
    }
}

/// @notice Shared setup for the secondary-trading condition unit tests. The test contract itself holds
/// OWNER_ROLE on `auth`, so it can call the conditions' admin/owner setters without pranking; `stranger`
/// stands in for an unauthorized caller in negative-authorization cases.
abstract contract SecondaryConditionTestBase is Test {
    BorgAuth internal auth;
    MockBadge internal badge;
    MockRegistry internal registry;
    MockCertPrinter internal cert;
    MockDealManager internal dm;

    address internal stranger = makeAddr("stranger");
    address internal seller = makeAddr("seller");
    address internal buyer = makeAddr("buyer");

    bytes32 internal constant OFFER_ID = keccak256("offer");
    bytes32 internal constant AGREEMENT_ID = keccak256("settlement");

    function _setUpBase() internal {
        auth = new BorgAuth(address(this));
        badge = new MockBadge();
        registry = new MockRegistry();
        cert = new MockCertPrinter();
        dm = new MockDealManager(address(auth));
    }

    function _proxy(address impl, bytes memory initData) internal returns (address) {
        return address(new ERC1967Proxy(impl, initData));
    }

    /// @dev A SELL offer with the mock cert printer and dm-as-SPV wired in. Callers tweak per scenario.
    function _sellOffer() internal view returns (Offer memory o) {
        o.spvAddress = address(dm);
        o.offeror = seller;
        o.side = OfferSide.SELL;
        o.certPrinter = address(cert);
        o.tokenId = 1;
        o.exemptionPathway = ExemptionPathway.RULE_144;
    }

    /// @dev An escrow whose counterparty is the buyer (as materialized at acceptOffer for a SELL offer).
    function _sellEscrow() internal view returns (SecondaryEscrow memory e) {
        e.counterparty = buyer;
        e.tokenId = 1;
    }

    /// @dev Posts a SELL offer and its accepted escrow into the mock DealManager.
    function _postSellAndAccept(Offer memory o, SecondaryEscrow memory e) internal {
        dm.setOffer(OFFER_ID, o);
        dm.setEscrow(AGREEMENT_ID, e);
    }

    function _one(string memory v) internal pure returns (string[] memory a) {
        a = new string[](1);
        a[0] = v;
    }
}

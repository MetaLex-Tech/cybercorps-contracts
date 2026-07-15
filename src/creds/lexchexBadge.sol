/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
o88o     o8888o                                                                                       
                                                                                                      
ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
`88.       .888'             .o8             `888'                   `8888    d8'                     
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/
pragma solidity 0.8.28;

import "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/token/ERC721/IERC721.sol";
import "./storage/lexchexBadgeStorage.sol";
import "./LeXcheXBadgeRender.sol";
import "../libs/auth.sol";
import "../interfaces/IERC5484.sol";
import "../interfaces/ILexChexBadge.sol";

/// @title  LeXcheXBadge - Unified Soulbound Credential Contract (LeXcheX v2)
/// @author MetaLeX Labs, Inc.
/// @notice Generalizes the single-purpose LeXcheX U.S. Accredited Investor certificate into one soulbound
/// credential registry covering all credentialing and whitelisting in the cyberTRADE spec: KYC/AML,
/// accredited investor, qualified purchaser, QIB, non-U.S. person, bad-actor negative attestation, per-SPV
/// whitelist entitlements, syndicate circles, and custom issuer-defined tiers — plus the §4.1.3A credential
/// attributes (U.S. state of residence/organization and entity beneficial-owner count).
/// @dev One deployment = one credentialing layer under one operator's BorgAuth (§4.1.3A layer model).
/// Pure state: no per-trade compliance logic (conditions do that), no offer-visibility enforcement, no KYC
/// itself, no delegation — credentials attach to the verified wallet only.
contract LeXcheXBadge is
    Initializable,
    ERC721EnumerableUpgradeable,
    UUPSUpgradeable,
    BorgAuthACL,
    ILexChexBadge
{
    uint256 public constant VERSION = 2;

    /// @dev Default when a category does not exist (mirrors LeXcheX v1's constant BurnAuth)
    BurnAuth constant DEFAULT_BURNAUTH = BurnAuth.OwnerOnly;

    // Upgrade notes: Reduced gap to account for new variables (50 - 1 = 49)
    uint256[49] private __gap;

    // Custom errors
    error LexChexBadge_SoulBound();
    error LexChexBadge_TokenDoesNotExist();
    error LexChexBadge_TokenCannotBeBurned();
    error LexChexBadge_OnlyIssuerCanBurn();
    error LexChexBadge_OnlyOwnerCanBurn();
    error LexChexBadge_CategoryDoesNotExist();
    error LexChexBadge_CategoryAlreadyExists();
    error LexChexBadge_CategoryNotActive();
    error LexChexBadge_InvalidValidityConfig();
    error LexChexBadge_MissingUsState();
    error LexChexBadge_UsStateNotAllowedForNonUS();
    error LexChexBadge_MissingBeneficialOwnerCount();
    error LexChexBadge_MissingEvidenceHash();

    // Events (indexer surface: Ponder ingests these for /api/offers eligibility and the admin panel §8.7)
    event CategoryCreated(bytes32 indexed categoryId, CredentialCategory category);
    event CategoryUpdated(bytes32 indexed categoryId, CredentialCategory category);
    event CategoryRetired(bytes32 indexed categoryId);
    event CredentialIssued(address indexed owner, uint256 indexed tokenId, bytes32 indexed categoryId, Credential cred);
    event CredentialRecertified(address indexed owner, uint256 indexed tokenId, Credential cred);
    event CredentialAttributesUpdated(uint256 indexed tokenId, bytes2 usState, uint32 beneficialOwnerCount);
    event CredentialRegulatoryJurisdictionUpdated(uint256 indexed tokenId, string regulatoryJurisdiction);
    event CredentialVoided(address indexed owner, uint256 indexed tokenId, string reason);
    event CredentialBurned(address indexed owner, uint256 indexed tokenId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __BorgAuthACL_init(_auth);
        __ERC721_init("LeXcheX Badge", "LXB");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Category / schema system (§0.3)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Registers a new issuer-defined credential category
    function createCategory(bytes32 categoryId, CredentialCategory memory category) external onlyAdmin {
        if (LeXcheXBadgeStorage.getCategory(categoryId).exists) revert LexChexBadge_CategoryAlreadyExists();
        category.exists = true;
        category.active = true;
        LeXcheXBadgeStorage.setCategory(categoryId, category);
        emit CategoryCreated(categoryId, category);
    }

    /// @notice Updates an existing category's schema (does not touch outstanding credentials)
    function updateCategory(bytes32 categoryId, CredentialCategory memory category) external onlyAdmin {
        CredentialCategory storage existing = LeXcheXBadgeStorage.getCategory(categoryId);
        if (!existing.exists) revert LexChexBadge_CategoryDoesNotExist();
        category.exists = true;
        LeXcheXBadgeStorage.setCategory(categoryId, category);
        emit CategoryUpdated(categoryId, category);
    }

    /// @notice Retires a category: stops new issuance but does not void outstanding credentials
    /// (void them explicitly if intended)
    function retireCategory(bytes32 categoryId) external onlyAdmin {
        CredentialCategory storage existing = LeXcheXBadgeStorage.getCategory(categoryId);
        if (!existing.exists) revert LexChexBadge_CategoryDoesNotExist();
        existing.active = false;
        emit CategoryRetired(categoryId);
    }

    function getCategory(bytes32 categoryId) public view returns (CredentialCategory memory) {
        return LeXcheXBadgeStorage.getCategory(categoryId);
    }

    function getCategoryIds() external view returns (bytes32[] memory) {
        return LeXcheXBadgeStorage.getCategoryIds();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle entry points (§0.5)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Issues a credential under an active category. Validates required attributes per the
    /// category's flags, stamps issuanceDate, and computes expiryDate from the category default if unset.
    function mint(
        address to,
        bytes32 categoryId,
        Credential memory cred
    ) public onlyAdmin returns (uint256 tokenId) {
        CredentialCategory storage category = LeXcheXBadgeStorage.getCategory(categoryId);
        if (!category.exists) revert LexChexBadge_CategoryDoesNotExist();
        if (!category.active) revert LexChexBadge_CategoryNotActive();

        cred.categoryId = categoryId;
        cred.issuanceDate = uint64(block.timestamp);
        cred.lastUpdated = uint64(block.timestamp);
        if (cred.expiryDate == 0) {
            if (category.defaultValidityDuration == 0) revert LexChexBadge_InvalidValidityConfig();
            cred.expiryDate = uint64(block.timestamp) + category.defaultValidityDuration;
        }
        _validateRequiredAttributes(category, cred);

        tokenId = LeXcheXBadgeStorage.getSupply();
        _mint(to, tokenId);
        LeXcheXBadgeStorage.setCredential(tokenId, cred);
        LeXcheXBadgeStorage.incrementSupply();

        emit CredentialIssued(to, tokenId, categoryId, cred);
        emit Issued(address(0), to, tokenId, category.burnAuth);
    }

    /// @notice The §6.9 refresh path: updates attributes and extends expiryDate in place, preserving
    /// issuanceDate (so seasoning is not reset by routine recertification) and the original category.
    function recertify(uint256 tokenId, Credential memory cred) external onlyAdmin {
        Credential storage existing = LeXcheXBadgeStorage.getCredential(tokenId);
        if (existing.issuanceDate == 0) revert LexChexBadge_TokenDoesNotExist();
        CredentialCategory storage category = LeXcheXBadgeStorage.getCategory(existing.categoryId);

        // Preserve the seasoning anchor and category link; bump the recency key
        cred.categoryId = existing.categoryId;
        cred.issuanceDate = existing.issuanceDate;
        cred.lastUpdated = uint64(block.timestamp);
        if (cred.expiryDate == 0) {
            if (category.defaultValidityDuration == 0) revert LexChexBadge_InvalidValidityConfig();
            cred.expiryDate = uint64(block.timestamp) + category.defaultValidityDuration;
        }
        _validateRequiredAttributes(category, cred);

        LeXcheXBadgeStorage.setCredential(tokenId, cred);
        emit CredentialRecertified(_requireOwned(tokenId), tokenId, cred);
    }

    /// @notice Material-change path for usState and beneficialOwnerCount between recertifications.
    /// @dev Per §6.9, a holder-reported state change routes through recertify (the credential is voided if
    /// the state is changed without recertification); this is reserved for corrections and BO-count refreshes.
    function updateAttributes(uint256 tokenId, bytes2 usState, uint32 beneficialOwnerCount) external onlyAdmin {
        Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
        if (cred.issuanceDate == 0) revert LexChexBadge_TokenDoesNotExist();
        cred.usState = usState;
        cred.beneficialOwnerCount = beneficialOwnerCount;
        cred.lastUpdated = uint64(block.timestamp);
        emit CredentialAttributesUpdated(tokenId, usState, beneficialOwnerCount);
    }

    /// @notice Reclassify a credential's §3(c)(1)(A) look-through jurisdiction in place (e.g. a wholly-non-U.S.
    /// feeder that admits its first U.S. beneficial owner flips to "US" without re-attesting the whole record).
    /// @dev Pair with updateAttributes to refresh beneficialOwnerCount when the classification changes.
    function setRegulatoryJurisdiction(uint256 tokenId, string calldata jurisdiction) external onlyAdmin {
        Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
        if (cred.issuanceDate == 0) revert LexChexBadge_TokenDoesNotExist();
        cred.regulatoryJurisdiction = jurisdiction;
        cred.lastUpdated = uint64(block.timestamp);
        emit CredentialRegulatoryJurisdictionUpdated(tokenId, jurisdiction);
    }

    /// @notice Revocation: failed re-KYC, discovered bad-actor status, relocation without recertification,
    /// sanctions hits. Reason string recorded and emitted.
    function void(uint256 tokenId, string memory reason) external onlyOwner {
        Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
        if (cred.issuanceDate == 0) revert LexChexBadge_TokenDoesNotExist();
        cred.voided = reason;
        cred.lastUpdated = uint64(block.timestamp);
        emit CredentialVoided(_requireOwned(tokenId), tokenId, reason);
    }

    /// @notice Burns a credential, gated by the category's BurnAuth (default OwnerOnly, matching LeXcheX v1;
    /// IssuerOnly for whitelist/syndicate categories so a holder cannot self-remove and re-onboard to reset seasoning)
    function burn(uint256 tokenId) public {
        address owner = _requireOwned(tokenId);
        BurnAuth auth = burnAuth(tokenId);

        if (auth == BurnAuth.Neither) revert LexChexBadge_TokenCannotBeBurned();
        if (auth == BurnAuth.OwnerOnly && msg.sender != owner) revert LexChexBadge_OnlyOwnerCanBurn();
        if (auth == BurnAuth.IssuerOnly && !_isIssuer(msg.sender)) revert LexChexBadge_OnlyIssuerCanBurn();
        if (auth == BurnAuth.Both && msg.sender != owner && !_isIssuer(msg.sender)) {
            revert LexChexBadge_OnlyOwnerCanBurn();
        }

        _burn(tokenId);
        LeXcheXBadgeStorage.deleteCredential(tokenId);
        emit CredentialBurned(owner, tokenId);
    }

    /// @inheritdoc IERC5484
    function burnAuth(uint256 tokenId) public view override returns (BurnAuth) {
        CredentialCategory storage category =
            LeXcheXBadgeStorage.getCategory(LeXcheXBadgeStorage.getCredential(tokenId).categoryId);
        return category.exists ? category.burnAuth : DEFAULT_BURNAUTH;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Read interface (§0.6) — what conditions and the UI consume
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Three-part validity test carried over from v1: issued, not voided, not expired
    function isValid(uint256 tokenId) public view returns (bool) {
        Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
        if (cred.issuanceDate == 0) return false;
        if (bytes(cred.voided).length > 0) return false;
        if (block.timestamp > cred.expiryDate) return false;
        return true;
    }

    /// @notice The workhorse for KYCAMLCondition, LegionSoulboundCondition, and whitelist checks
    function hasValidCredential(address owner, bytes32 categoryId) public view returns (bool) {
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            if (LeXcheXBadgeStorage.getCredential(tokenId).categoryId == categoryId && isValid(tokenId)) {
                return true;
            }
        }
        return false;
    }

    /// @notice Serves the LexChexCondition parameterizations (AccreditedInvestor / QP / QIB) without
    /// hardcoding category IDs. Empty investorTypeFilter matches any investor type.
    function hasValidCredentialOfKind(
        address owner,
        CategoryKind kind,
        string memory investorTypeFilter
    ) public view returns (bool) {
        bytes32 filterHash = keccak256(bytes(investorTypeFilter));
        bool hasFilter = bytes(investorTypeFilter).length > 0;
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
            CredentialCategory storage category = LeXcheXBadgeStorage.getCategory(cred.categoryId);
            if (!category.exists || category.kind != kind) continue;
            if (hasFilter && keccak256(bytes(cred.investorType)) != filterHash) continue;
            if (isValid(tokenId)) return true;
        }
        return false;
    }

    /// @notice Resolves SPV_WHITELIST / SYNDICATE categories scoped to the SPV. Backs per-SPV
    /// offer-visibility entitlements (§16.2) and any onchain issuer gating.
    function hasValidWhitelistFor(address owner, address spv) public view returns (bool) {
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
            CredentialCategory storage category = LeXcheXBadgeStorage.getCategory(cred.categoryId);
            if (!category.exists) continue;
            if (category.kind != CategoryKind.SPV_WHITELIST && category.kind != CategoryKind.SYNDICATE) continue;
            if (category.scope != spv) continue;
            if (isValid(tokenId)) return true;
        }
        return false;
    }

    /// @notice U.S. state of residence/organization for USStateOfResidenceCondition; zero for non-U.S. holders.
    function getUsState(address owner) public view returns (bytes2) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, ATTR_US_STATE);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).usState : bytes2(0);
    }

    /// @notice Entity beneficial-owner count for HolderCapCondition's §3(c)(1)(A) look-through; 0 when absent.
    function getBeneficialOwnerCount(address owner) public view returns (uint32) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, ATTR_BO_COUNT);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).beneficialOwnerCount : 0;
    }

    /// @notice Physical country jurisdiction from the owner's authoritative credential; empty when none.
    function getInvestorJurisdiction(address owner) public view returns (string memory) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, ATTR_INVESTOR_JURISDICTION);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).investorJurisdiction : "";
    }

    /// @notice §3(c)(1)(A) look-through classification from the owner's authoritative credential; empty when
    /// none. Decoupled from the physical investorJurisdiction (which CFIUS/blue-sky consume).
    function getRegulatoryJurisdiction(address owner) public view returns (string memory) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, ATTR_REGULATORY_JURISDICTION);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).regulatoryJurisdiction : "";
    }

    /// @notice True when the owner is a U.S. investor for the ICA look-through. Conservative: U.S. if either the
    /// regulatory look-through or the physical domicile is U.S., so a U.S.-domiciled party can never be
    /// declassified out of the count.
    function isUSInvestor(address owner) public view returns (bool) {
        return _isUSJurisdiction(getRegulatoryJurisdiction(owner)) || _isUSJurisdiction(getInvestorJurisdiction(owner));
    }

    /// @notice Seasoning reference for the UI (§11.1B): earliest valid issuance of the given kind.
    /// The seasoning policy (30 vs 45 days) stays at the UI layer; this only supplies the timestamp.
    function earliestValidIssuance(address owner, CategoryKind kind) public view returns (uint64) {
        uint64 earliest = 0;
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
            if (!isValid(tokenId)) continue;
            if (LeXcheXBadgeStorage.getCategory(cred.categoryId).kind != kind) continue;
            if (earliest == 0 || cred.issuanceDate < earliest) earliest = cred.issuanceDate;
        }
        return earliest;
    }

    // ── Carried over from LeXcheX v1 (interface-compatible reads, §0.10) ─────

    /// @notice v1-compatible read: true when the owner holds any valid credential
    function hasValidLexCheX(address owner) public view returns (bool) {
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            if (isValid(tokenOfOwnerByIndex(owner, i))) return true;
        }
        return false;
    }

    function getTokenIdsByOwner(address owner) public view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    /// @notice First token ID owned by an address (v1 getAccreditationByOwner-style getter)
    function getCredentialByOwner(address owner) public view returns (uint256) {
        require(balanceOf(owner) > 0, "No tokens owned by this address");
        return tokenOfOwnerByIndex(owner, 0);
    }

    function getCredential(uint256 tokenId) public view returns (Credential memory) {
        return LeXcheXBadgeStorage.getCredential(tokenId);
    }

    /// @dev Disambiguates balanceOf, declared by both ERC721Upgradeable and ILexChexBadge.
    function balanceOf(address owner)
        public
        view
        override(ERC721Upgradeable, IERC721, ILexChexBadge)
        returns (uint256)
    {
        return super.balanceOf(owner);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Soulbound enforcement (§0.1)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Reverts on any transfer where from != 0 && to != 0 (mint and burn only), identical to the
    /// existing LexChex_SoulBound() pattern
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert LexChexBadge_SoulBound();
        }
        return super._update(to, tokenId, auth);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // tokenURI (§0.8) — per-category title/description; sensitive attributes
    // (usState, beneficialOwnerCount, evidenceHash) are NOT rendered
    // ─────────────────────────────────────────────────────────────────────────

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        Credential memory cred = LeXcheXBadgeStorage.getCredential(tokenId);
        CredentialCategory memory category = LeXcheXBadgeStorage.getCategory(cred.categoryId);
        return LeXcheXBadgeRender.tokenURI(tokenId, cred, category, isValid(tokenId));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev The owner's authoritative credential for `attributeMask`: the most recent (by lastUpdated — a
    /// correction or recertification wins; ties → higher tokenId) valid credential whose category governs every
    /// requested attribute, so an unrelated credential can neither answer the attribute nor shadow one that does.
    function _mostRecentValidWith(address owner, uint256 attributeMask) internal view returns (uint256 tokenId, bool found) {
        uint64 latest = 0;
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 candidate = tokenOfOwnerByIndex(owner, i);
            if (!isValid(candidate)) continue;
            Credential storage cred = LeXcheXBadgeStorage.getCredential(candidate);
            // filter only categories governing ALL attributes selected by attributeMask
            if ((LeXcheXBadgeStorage.getCategory(cred.categoryId).governedAttributes & attributeMask) != attributeMask) continue;
            if (!found || cred.lastUpdated > latest || (cred.lastUpdated == latest && candidate > tokenId)) {
                latest = cred.lastUpdated;
                tokenId = candidate;
                found = true;
            }
        }
    }

    /// @dev Enforces the category's required-attribute flags on a credential being written
    function _validateRequiredAttributes(CredentialCategory storage category, Credential memory cred) internal view {
        if (category.requiresEvidenceHash && cred.evidenceHash == bytes32(0)) {
            revert LexChexBadge_MissingEvidenceHash();
        }
        bool isUS = _isUSJurisdiction(cred.investorJurisdiction);
        if (category.requiresUsState && isUS && cred.usState == bytes2(0)) {
            revert LexChexBadge_MissingUsState();
        }
        // Keep the attribute clean for USStateOfResidenceCondition: non-U.S. holders carry no state
        if (!isUS && cred.usState != bytes2(0)) {
            revert LexChexBadge_UsStateNotAllowedForNonUS();
        }
        if (category.requiresBeneficialOwnerCount && !_isIndividual(cred.investorType) && cred.beneficialOwnerCount == 0) {
            revert LexChexBadge_MissingBeneficialOwnerCount();
        }
    }

    function _isUSJurisdiction(string memory jurisdiction) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(jurisdiction));
        return h == keccak256("US") || h == keccak256("USA") || h == keccak256("United States");
    }

    function _isIndividual(string memory investorType) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(investorType));
        return h == keccak256("Individual") || h == keccak256("individual");
    }

    /// @dev Issuer = the layer operator's BorgAuth admin (or above)
    function _isIssuer(address account) internal view returns (bool) {
        return AUTH.userRoles(account) >= AUTH.ADMIN_ROLE();
    }

    /// @dev Only owner can upgrade it
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

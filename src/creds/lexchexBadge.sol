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

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./storage/lexchexBadgeStorage.sol";
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
    using Strings for uint256;

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

        // Preserve the seasoning anchor and category link
        cred.categoryId = existing.categoryId;
        cred.issuanceDate = existing.issuanceDate;
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
        emit CredentialAttributesUpdated(tokenId, usState, beneficialOwnerCount);
    }

    /// @notice Revocation: failed re-KYC, discovered bad-actor status, relocation without recertification,
    /// sanctions hits. Reason string recorded and emitted.
    function void(uint256 tokenId, string memory reason) external onlyOwner {
        Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
        if (cred.issuanceDate == 0) revert LexChexBadge_TokenDoesNotExist();
        cred.voided = reason;
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

    /// @notice U.S. state attribute for USStateOfResidenceCondition; zero for non-U.S. holders.
    /// Sourced from the owner's most recent valid credential carrying the attribute.
    function getUsState(address owner) public view returns (bytes2) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, _HAS_US_STATE);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).usState : bytes2(0);
    }

    /// @notice Entity beneficial-owner count for HolderCapCondition's §3(c)(1)(A) look-through; 0 when absent.
    function getBeneficialOwnerCount(address owner) public view returns (uint32) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, _HAS_BO_COUNT);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).beneficialOwnerCount : 0;
    }

    /// @notice Country jurisdiction from the owner's most recent valid credential; empty string when none.
    function getInvestorJurisdiction(address owner) public view returns (string memory) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, _ANY);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).investorJurisdiction : "";
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
        string memory title = category.exists ? category.name : "LeXcheX Credential";

        string memory image = generateSVGImage(title, cred);

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "',
                            title,
                            " #",
                            tokenId.toString(),
                            '", "description": "',
                            category.exists ? category.description : "Soulbound credential issued on the LeXcheX Badge registry.",
                            '",',
                            '"image": "data:image/svg+xml;base64,',
                            Base64.encode(bytes(image)),
                            '", "attributes": [',
                            '{"trait_type": "Name", "value": "',
                            cred.investorName,
                            '"},',
                            '{"trait_type": "Entity Type", "value": "',
                            cred.investorType,
                            '"},',
                            '{"trait_type": "Jurisdiction", "value": "',
                            cred.investorJurisdiction,
                            '"},',
                            '{"trait_type": "Status", "value": "',
                            isValid(tokenId) ? "Valid" : "Invalid",
                            '"},',
                            '{"trait_type": "Expiry", "value": "',
                            timestampToDate(cred.expiryDate),
                            '"}',
                            "]}"
                        )
                    )
                )
            )
        );
    }

    function generateSVGImage(string memory title, Credential memory cred) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="1000" height="650">',
                '<rect width="100%" height="100%" fill="#191a18"/>',
                generateMetaLeXLogo(),
                generateSVGBody(title, cred),
                "</svg>"
            )
        );
    }

    function generateMetaLeXLogo() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg x="880" y="570" width="61" height="30" viewBox="0 0 61 30" fill="none" xmlns="http://www.w3.org/2000/svg">',
                '<path d="M29.5488 0C30.5107 0 31.291 0.779753 31.291 1.74121V11.957C31.291 12.543 30.9957 13.0902 30.5059 13.4121L6.69629 29.0605C6.41221 29.2472 6.07921 29.3467 5.73926 29.3467H1.74121C0.779536 29.3465 0 28.5668 0 27.6055V19.9648C8.27261e-05 19.3799 0.293816 18.8339 0.782227 18.5117L28.415 0.288086C28.6996 0.100412 29.0331 0 29.374 0H29.5488ZM54.7832 0.000976562C55.745 0.000976562 56.5243 0.77984 56.5244 1.74121V11.957C56.5244 12.543 56.23 13.0902 55.7402 13.4121L31.9307 29.0605C31.6465 29.2473 31.3137 29.3467 30.9736 29.3467H26.9756C26.0139 29.3466 25.2344 28.5669 25.2344 27.6055V19.9648C25.2345 19.38 25.5282 18.8338 26.0166 18.5117L53.6494 0.288086C53.934 0.100488 54.2675 0.000976562 54.6084 0.000976562H54.7832ZM58.9521 15.54C59.825 14.9532 60.9997 15.5783 61 16.6299V27.792C60.9999 28.6506 60.3033 29.3467 59.4443 29.3467H48.5459C47.687 29.3466 46.9903 28.6505 46.9902 27.792V24.3594C46.9902 23.842 47.2484 23.3582 47.6777 23.0693L58.9521 15.54Z" fill="#DAFF00"/>',
                "</svg>"
            )
        );
    }

    function generateSVGBody(string memory title, Credential memory cred) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<rect x="0" y="83" width="1000px" height="50px" fill="url(#linGrad)"></rect>',
                '<text x="500" y="126" text-anchor="middle" font-family="Georgia" font-size="48" fill="url(#textGrad)">',
                title,
                "</text>",
                '<text x="500" y="226" text-anchor="middle" font-family="Georgia" font-size="25" fill="#f2f2f2">THIS SOULBOUND CREDENTIAL IS HELD BY</text>',
                '<text x="500" y="266" text-anchor="middle" font-family="Georgia" font-size="25" fill="#f2f2f2">',
                cred.investorName,
                "</text>",
                generateDefs(),
                '<rect width="100%" height="100%" fill="url(#grad1)" />',
                '<text x="150" y="360" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6">JURISDICTION</text>',
                '<text x="495" y="355" font-family="Georgia" font-size="30" fill="url(#textGrad)">',
                cred.investorJurisdiction,
                "</text>",
                '<rect x="380" y="363" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                '<text x="150" y="450" font-family="Georgia" font-size="30" fill="#f2f2f2" opacity=".6">GOOD UNTIL</text>',
                '<text x="495" y="440" font-family="Georgia" font-size="30" fill="url(#textGrad)">',
                timestampToDate(cred.expiryDate),
                "</text>",
                '<rect x="380" y="453" width="470px" height="5px" fill="#f2f2f2" opacity=".24"></rect>',
                '<text x="325" y="570" font-family="Georgia" font-size="17" fill="#f2f2f2" opacity=".6">Non-transferable. Soul-bound. Verified on-chain.</text>',
                '<text x="210" y="600" font-family="Georgia" font-size="15" fill="#f2f2f2" opacity=".24">',
                bytes32ToHexString(cred.agreementId),
                "</text>"
            )
        );
    }

    function generateDefs() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<defs>",
                '<radialGradient id="grad1" cx="50%" cy="50%" r="50%" fx="50%" fy="50%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.07" />',
                '<stop offset="100%" style="stop-color:#191a18; stop-opacity:.07" />',
                "</radialGradient>",
                '<linearGradient id="linGrad">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:.4" />',
                '<stop offset="20%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="80%" style="stop-color:#daff00; stop-opacity:0" />',
                '<stop offset="100%" style="stop-color:#daff00; stop-opacity:.4" />',
                "</linearGradient>",
                '<linearGradient id="textGrad" x1="0%" y1="0%" x2="0%" y2="100%">',
                '<stop offset="0%" style="stop-color:#daff00; stop-opacity:1" />',
                '<stop offset="100%" style="stop-color:#F2F8CB; stop-opacity:1" />',
                "</linearGradient>",
                "</defs>"
            )
        );
    }

    function timestampToDate(uint256 timestamp) internal pure returns (string memory) {
        uint256 day = ((timestamp / 86400) % 31) + 1;
        uint256 month = ((timestamp / 2629743) % 12) + 1;
        uint256 year = (timestamp / 31556926) + 1970;
        return string(
            abi.encodePacked(
                Strings.toString(month), "/", Strings.toString(day), "/", Strings.toString(year)
            )
        );
    }

    function bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = bytes1(
                uint8(uint256(uint8(value[i] >> 4)) + (uint256(uint8(value[i] >> 4)) < 10 ? 48 : 87))
            );
            str[i * 2 + 1] = bytes1(
                uint8(uint256(uint8(value[i] & 0x0f)) + (uint256(uint8(value[i] & 0x0f)) < 10 ? 48 : 87))
            );
        }
        return string(abi.encodePacked("0x", string(str)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────

    uint8 private constant _ANY = 0;
    uint8 private constant _HAS_US_STATE = 1;
    uint8 private constant _HAS_BO_COUNT = 2;

    /// @dev Most recent (highest issuanceDate) valid credential of `owner` carrying the requested attribute
    function _mostRecentValidWith(address owner, uint8 attribute) internal view returns (uint256 tokenId, bool found) {
        uint64 latest = 0;
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 candidate = tokenOfOwnerByIndex(owner, i);
            if (!isValid(candidate)) continue;
            Credential storage cred = LeXcheXBadgeStorage.getCredential(candidate);
            if (attribute == _HAS_US_STATE && cred.usState == bytes2(0)) continue;
            if (attribute == _HAS_BO_COUNT && cred.beneficialOwnerCount == 0) continue;
            if (!found || cred.issuanceDate >= latest) {
                latest = cred.issuanceDate;
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

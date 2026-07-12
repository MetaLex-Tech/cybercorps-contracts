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

All rights reserved.*/

pragma solidity 0.8.28;

import "../../interfaces/IERC5484.sol";

/// @notice Kind of credential a category attests to. Conditions filter on this without hardcoding
/// category ids (see ILexChexBadge.hasValidCredentialOfKind).
enum CategoryKind {
    KYC_AML,
    ACCREDITED_INVESTOR,
    QUALIFIED_PURCHASER,
    QIB,
    NON_US_PERSON,
    BAD_ACTOR_CLEAR,
    SPV_WHITELIST,
    SYNDICATE,
    CUSTOM
}

/// @notice Issuer-defined credential category (schema) keyed by a bytes32 categoryId.
struct CredentialCategory {
    string name;                        // human-readable category name (rendered as certificate title)
    string description;                 // rendered in tokenURI metadata
    CategoryKind kind;
    uint64 defaultValidityDuration;     // seconds; drives expiryDate at mint when the credential's own is unset
    bool requiresUsState;               // credential must carry usState when the holder is US-jurisdiction
    bool requiresBeneficialOwnerCount;  // entity credentials must carry the §3(c)(1)(A) look-through count
    bool requiresEvidenceHash;          // credential must anchor an offchain diligence record
    IERC5484.BurnAuth burnAuth;         // per-category ERC-5484 burn auth (OwnerOnly default, IssuerOnly for whitelists)
    address scope;                      // SPV cyberCORP address for SPV_WHITELIST / SYNDICATE; zero otherwise
    bool active;                        // false = retired: no new issuance, outstanding credentials unaffected
    bool exists;
}

/// @notice Per-token credential record; superset of the legacy LeXcheX Accreditation so v1 semantics carry over.
struct Credential {
    bytes32 categoryId;                 // links to the category registry
    string investorName;
    string investorType;                // Individual / entity subtype; conditions filter on it
    string investorJurisdiction;        // country jurisdiction (ISO 3166-1 alpha-2 recommended, "US" for U.S.)
    bytes2 usState;                     // §4.1.3A: U.S. state of residence/organization; zero for non-U.S. holders
    uint32 beneficialOwnerCount;        // §4.1.3A: entity holders only; §3(c)(1)(A) look-through count
    uint64 issuanceDate;                // validity anchor; also the seasoning reference (§11.1B)
    uint64 expiryDate;                  // isValid fails after it
    string voided;                      // non-empty = voided, with reason
    bytes32 agreementId;                // CyberAgreementRegistry attestation underlying the credential
    bytes32 evidenceHash;               // hash of the offchain diligence record (audit anchor)
    bytes extensionData;                // forward-compatible blob for future attributes
}

/// @title LeXcheXBadgeStorage - namespaced storage for the LeXcheXBadge credential registry
/// @author MetaLeX Labs, Inc.
library LeXcheXBadgeStorage {
    bytes32 constant STORAGE_POSITION = keccak256("metalex.lexchexbadge.storage.v1");

    struct LeXcheXBadgeData {
        mapping(uint256 => Credential) credentials;         // per-token records
        mapping(bytes32 => CredentialCategory) categories;  // category registry
        bytes32[] categoryIds;                              // enumeration of registered categories
        uint256 supply;                                     // next token id / total minted
    }

    function badgeStorage() internal pure returns (LeXcheXBadgeData storage s) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            s.slot := position
        }
    }

    // ── Credentials ──────────────────────────────────────────────────────────

    function getCredential(uint256 tokenId) internal view returns (Credential storage) {
        return badgeStorage().credentials[tokenId];
    }

    function setCredential(uint256 tokenId, Credential memory cred) internal {
        badgeStorage().credentials[tokenId] = cred;
    }

    function deleteCredential(uint256 tokenId) internal {
        delete badgeStorage().credentials[tokenId];
    }

    // ── Categories ───────────────────────────────────────────────────────────

    function getCategory(bytes32 categoryId) internal view returns (CredentialCategory storage) {
        return badgeStorage().categories[categoryId];
    }

    function setCategory(bytes32 categoryId, CredentialCategory memory category) internal {
        LeXcheXBadgeData storage s = badgeStorage();
        if (!s.categories[categoryId].exists) {
            s.categoryIds.push(categoryId);
        }
        s.categories[categoryId] = category;
    }

    function getCategoryIds() internal view returns (bytes32[] memory) {
        return badgeStorage().categoryIds;
    }

    // ── Supply ───────────────────────────────────────────────────────────────

    function getSupply() internal view returns (uint256) {
        return badgeStorage().supply;
    }

    function incrementSupply() internal returns (uint256) {
        LeXcheXBadgeData storage s = badgeStorage();
        uint256 current = s.supply;
        s.supply = current + 1;
        return current;
    }
}

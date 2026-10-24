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

// The K_* fact-keys, presets, events and errors are declared in ILexChexBadge.sol so every reader shares them.
import {InvestorType} from "../../interfaces/ILexChexBadge.sol";

/// @notice Per-token credential record. Immutable once minted (revoke by voiding, never by editing or burning).
/// `asserts` is the sole source of truth: a field is authoritative only when its key is asserted.
struct Credential {
    uint256 asserts;                    // K_* fact-keys this credential attests; the authority axis
    address issuer;                     // who minted it; consumers filter on this to pick whose word they take
    string investorName;                // who the credential names; display/audit only, no fact-key asserts it
    string investorJurisdiction;        // value for K_INVESTOR_JURISDICTION ("US"/"USA"/"United States" all read US)
    // value for K_LOOKTHROUGH_JURISDICTION — §3(c)(1)(A) ICA look-through classification, decoupled from the
    // physical investorJurisdiction: an offshore entity with any U.S. beneficial owner is treated as U.S. here
    // (regulatory point of view) even though its domicile stays foreign for CFIUS / blue-sky purposes.
    string lookThroughJurisdiction;
    InvestorType investorType;          // value for K_INVESTOR_TYPE
    bytes2 usState;                     // value for K_US_STATE
    uint32 beneficialOwnerCount;        // value for K_BO_COUNT
    // The SPV this credential is about. Any key may carry one and every read can filter on it;
    // it is mandatory for SCOPED_KEYS.
    address scope;
    uint64 issuanceDate;                // mint time; recency key (max) and §11.1B seasoning reference (min); immutable
    uint64 expiryDate;                  // isValid fails after it
    string voided;                      // non-empty = voided, with reason
    bytes32 agreementId;                // CyberAgreementRegistry attestation underlying the credential
    bytes32 evidenceHash;               // hash of the offchain diligence record (audit anchor)
    bytes data;                         // value for K_DATA — generic programmable payload; the badge stores it
                                        // but never interprets it (downstream programs read it via getData)
    string[] nationalityOut;            // value for K_NATIONALITY_OUT — the countries where the holder is not a national
}

/// @title LeXcheXBadgeStorage - namespaced storage for the LeXcheXBadge credential registry
/// @author MetaLeX Labs, Inc.
library LeXcheXBadgeStorage {
    bytes32 constant STORAGE_POSITION = keccak256("metalex.lexchexbadge.storage.v1");

    struct LeXcheXBadgeData {
        mapping(uint256 => Credential) credentials;         // per-token records (append-only; never deleted)
        uint256 supply;                                     // next token id / total minted
        // What each issuer is allowed to say. mint rejects any asserted key outside the mask, so several
        // operators can share one deployment without each of them being able to write every fact.
        mapping(address => uint256) issuerKeys;             // issuer => K_* fact-keys it may assert
        // Active set = the holder's non-voided, not-yet-swept credentials. Compliance reads scan THIS (bounded)
        // instead of the full ERC-721 enumeration; void() evicts at once and sweep() evicts expired. Soulbound +
        // never-burned ⇒ the holder is stable, so a per-holder list + 1-based position index gives O(1) swap-pop.
        mapping(address => uint256[]) activeTokens;         // holder => active token ids
        mapping(uint256 => uint256) activePos;              // id => 1-based idx in activeTokens[holder]; 0 = inactive
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

    // ── Active set (active-only) ───────────────────────────────────────────────

    function getActiveTokens(address holder) internal view returns (uint256[] storage) {
        return badgeStorage().activeTokens[holder];
    }

    /// @dev Track a freshly-minted token in the holder's active set.
    function addActive(address holder, uint256 tokenId) internal {
        LeXcheXBadgeData storage s = badgeStorage();
        s.activeTokens[holder].push(tokenId);
        s.activePos[tokenId] = s.activeTokens[holder].length;
    }

    /// @dev Evict a voided/expired token from the active set. Idempotent (no-op if absent).
    /// `holder` MUST be the token's owner — `activePos` is a global id→index map, so a mismatched pair would
    /// index into the wrong holder's array. Callers derive it from ownership, never from an argument.
    /// @return removed True when the token was still in the active set, so callers can count real evictions.
    function removeActive(address holder, uint256 tokenId) internal returns (bool removed) {
        LeXcheXBadgeData storage s = badgeStorage();
        removed = _swapPop(s.activeTokens[holder], s.activePos, tokenId);
    }

    function _swapPop(uint256[] storage arr, mapping(uint256 => uint256) storage pos, uint256 tokenId)
        private
        returns (bool)
    {
        uint256 p = pos[tokenId];
        if (p == 0) return false;
        uint256 i = p - 1;
        uint256 lastId = arr[arr.length - 1];
        arr[i] = lastId;
        pos[lastId] = i + 1;
        arr.pop();
        pos[tokenId] = 0;
        return true;
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

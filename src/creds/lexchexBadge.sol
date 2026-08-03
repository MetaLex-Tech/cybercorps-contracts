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
/// @notice One soulbound credential registry covering all credentialing and whitelisting in the cyberTRADE
/// spec: KYC/AML, accredited investor, qualified purchaser, QIB, bad-actor negative attestation, per-SPV
/// whitelist and syndicate entitlements — plus the §4.1.3A credential attributes (U.S. state of
/// residence/organization and entity beneficial-owner count).
/// @dev One deployment = one credentialing layer under one operator's BorgAuth (§4.1.3A layer model).
/// Pure state: no per-trade compliance logic (conditions do that), no offer-visibility enforcement, no KYC
/// itself, no delegation — credentials attach to the verified wallet only.
///
/// Spec
/// - A credential's `asserts` (K_* fact-keys) is the sole authority axis: a field answers a read only when
///   its key is asserted; VALUE keys require a non-empty field, SCOPE keys require `scope` (the SPV).
/// - Credentials are IMMUTABLE once minted: change a fact by minting a newer credential (most-recent valid
///   wins), and revoke by voiding. There is no in-place edit.
/// - Changing a fact is not the same as retracting one. No credential can say a fact stopped being true, and
///   one that just drops the key leaves the old credential answering. To retract, void the credential that
///   carries the fact — `supersede` voids and re-issues in one call so half of it cannot be forgotten.
/// - Compliance reads scan the holder's ACTIVE SET (non-voided, not-yet-swept credentials), so scan cost is
///   bounded rather than O(all-ever-minted): void() evicts at once; the permissionless sweep(holder) evicts
///   expired ones (reads are view and cannot evict), and sweepTokens(ids) drains a set in calldata-bounded
///   batches so one that outgrew a single sweep is never stuck. The full ERC-721 enumeration (incl.
///   voided/expired) is retained for audit and returned by getTokenIdsByOwner.
///
/// Unknown / empty values
/// - A raw value getter returns the field's empty value (0, "", bytes2(0)) when no valid credential asserts the
///   fact — never reverts — so downstream conditions read defaults just like the pre-redesign badge did.
/// - Empty is reported, never interpreted. This contract does not decide whether an unestablished fact should
///   fail open or closed — that direction is regime-specific and opposite between callers (an ICA look-through
///   wants unknown to read U.S.; a CFIUS screen wants unknown to read foreign), so each condition applies its
///   own rule to the raw value. See LookThroughPolicy for the §3(c)(1)(A) reading.
/// - One getter is an exception: getEffectiveBeneficialOwnerCount() takes getInvestorType() into account because
///   BO is undefined when investor is an individual
///
/// Credential catalogue — what each fact carries and which body of law reads it. DO NOT cross-wire.
///
/// | Fact-key                     | Read                             | Outcome domain              | Serves                   |
/// |------------------------------|----------------------------------|-----------------------------|--------------------------|
/// | K_INVESTOR_TYPE              | getInvestorType                  | UNSET / INDIVIDUAL / ENTITY | —                        |
/// | K_INVESTOR_JURISDICTION      | getInvestorJurisdiction          | EMPTY / country code        | CFIUS/FIRRMA; blue sky   |
/// | K_LOOKTHROUGH_JURISDICTION   | getLookThroughJurisdiction       | EMPTY / country code        | ICA §3(c)(1)(A)          |
/// | K_US_STATE                   | getUsState                       | EMPTY / state code          | blue sky                 |
/// | K_BO_COUNT & K_INVESTOR_TYPE | getEffectiveBeneficialOwnerCount | 0 / >0                      | ICA §3(c)(1)(A)          |
/// | K_ACCREDITED / K_QP / K_QIB  | hasValidCredentialOf             | absent / asserted           | Reg D; Rule 144A         |
/// | K_NON_US                     | hasValidCredentialOf             | absent / asserted           | Reg S                    |
/// | K_SPV_WHITELIST              | hasValidWhitelistFor             | absent / scoped to an SPV   | offer visibility (§16.2) |
/// | K_SYNDICATE                  | hasValidSyndicateFor             | absent / scoped to an SPV   | issuer circle (§4.1.3A)  |
///
/// Invariants
/// - Tokens are deliberately NOT burnable — revocation is void-only, so every credential (voided, expired, or
///   superseded) is retained on-chain for audit. Void is one-way.
/// - `categoryId` is a free-form issuer label carried for off-chain bookkeeping, never interpreted on-chain
///   (category schemas live off-chain, not in this contract).
/// - `data` is a generic programmable payload gated by
///   K_DATA that the badge stores but never interprets — downstream programs read the authoritative value via
///   getData.
contract LeXcheXBadge is
    Initializable,
    ERC721EnumerableUpgradeable,
    UUPSUpgradeable,
    BorgAuthACL,
    ILexChexBadge
{
    uint256 public constant VERSION = 2;

    // Credential state lives in LeXcheXBadgeStorage's own slot; this only reserves room for future variables
    // declared directly on the contract.
    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        __ERC721_init("LeXcheX Badge", "LXB");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Lifecycle entry points (§0.5) — append-only; never edited or burned
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Issues an immutable credential. Validates that every asserted fact-key carries its value (or
    /// scope), stamps issuanceDate, and requires a future expiry. To change a fact later, mint a newer
    /// credential asserting the changed key (most-recent valid wins); to revoke, void.
    function mint(address to, Credential memory cred) public onlyAdmin returns (uint256 tokenId) {
        _validate(cred);
        if (cred.expiryDate <= block.timestamp) revert LexChexBadge_InvalidExpiry();
        cred.issuanceDate = uint64(block.timestamp);
        cred.voided = "";

        tokenId = LeXcheXBadgeStorage.getSupply();
        _mint(to, tokenId);
        LeXcheXBadgeStorage.setCredential(tokenId, cred);
        LeXcheXBadgeStorage.addActive(to, tokenId, cred.categoryId);
        LeXcheXBadgeStorage.incrementSupply();

        emit CredentialIssued(to, tokenId, cred);
        emit Issued(address(0), to, tokenId, BurnAuth.Neither); // tokens are never burnable
    }

    /// @notice Replaces a credential: voids `staleTokenId` and issues `cred` to the same holder in one call.
    /// @dev How to retract a fact. Minting a corrected credential is not enough — the old one keeps answering
    /// until it is voided, so a holder who emigrates would keep their old U.S. state. Both steps happen here
    /// so a correction cannot be issued half-finished.
    function supersede(
        uint256 staleTokenId,
        Credential memory cred,
        string memory reason
    ) external onlyAdmin returns (uint256 tokenId) {
        address holder = _requireOwned(staleTokenId);
        void(staleTokenId, reason);
        return mint(holder, cred);
    }

    /// @notice Revocation: failed re-KYC, discovered bad-actor status, relocation, sanctions hits. The
    /// credential is retained (never burned) with the reason recorded, so the record survives for audit.
    function void(uint256 tokenId, string memory reason) public onlyAdmin {
        if (bytes(reason).length == 0) revert LexChexBadge_MissingVoidReason();
        Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
        if (cred.issuanceDate == 0) revert LexChexBadge_TokenDoesNotExist();
        address holder = _requireOwned(tokenId);
        cred.voided = reason;
        LeXcheXBadgeStorage.removeActive(holder, tokenId, cred.categoryId); // evict from the active set at once
        emit CredentialVoided(holder, tokenId, reason);
    }

    /// @notice Permissionless keeper hook: evict the holder's EXPIRED credentials from the active set so read
    /// scans stay bounded. Voided credentials are evicted at void() time; expiry is handled here (reads are
    /// view and cannot mutate, so expiry eviction is deferred to this sweep). Records are retained for audit.
    /// @dev Scans the holder's whole active set in one transaction. Use sweepTokens for a set large enough
    /// that a full scan would not fit in a block.
    function sweep(address holder) public {
        uint256[] storage ids = LeXcheXBadgeStorage.getActiveTokens(holder);
        uint256 i;
        while (i < ids.length) {
            uint256 id = ids[i];
            Credential storage cred = LeXcheXBadgeStorage.getCredential(id);
            if (block.timestamp > cred.expiryDate) {
                LeXcheXBadgeStorage.removeActive(holder, id, cred.categoryId); // swap-pop → re-check index i
            } else {
                ++i;
            }
        }
    }

    /// @notice Sweep several holders in one keeper transaction.
    function sweepHolders(address[] calldata holders) external {
        for (uint256 i = 0; i < holders.length; i++) {
            sweep(holders[i]);
        }
    }

    /// @notice Permissionless keeper hook that evicts the NAMED expired credentials, in a batch bounded by its
    /// own calldata rather than by the holder's history. This is what keeps the active set drainable: `sweep`
    /// must scan a holder's entire set in one transaction, so a set that outgrew the block gas limit could
    /// never be shrunk (and a partly-scanned `sweep` reverts, saving nothing). Each batch here stands on its
    /// own, so an oversized set drains over successive calls. Keepers pick the ids off `getActiveTokenIds` and
    /// `expiryDate` offchain.
    /// @dev Only EXPIRED credentials are evictable, so an untrusted caller can never drop a valid credential
    /// and suppress a compliance fact. The holder is derived from the token (soulbound and never burned, so
    /// ownership is authoritative) — a batch therefore cannot touch a set the token does not belong to.
    /// Unknown, unexpired and already-evicted ids are skipped so a stale batch stays harmless.
    /// @return evicted How many of `tokenIds` this call actually removed from an active set.
    function sweepTokens(uint256[] calldata tokenIds) external returns (uint256 evicted) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            address holder = _ownerOf(tokenId);
            if (holder == address(0)) continue;
            Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
            if (block.timestamp <= cred.expiryDate) continue;
            if (LeXcheXBadgeStorage.removeActive(holder, tokenId, cred.categoryId)) ++evicted;
        }
    }

    /// @inheritdoc IERC5484
    /// @dev Tokens are deliberately non-burnable (void-only), so burn authority is always Neither.
    function burnAuth(uint256) public pure override returns (BurnAuth) {
        return BurnAuth.Neither;
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

    /// @notice True when the owner holds a valid credential carrying the free-form issuer label `categoryId`.
    /// The label is never interpreted by this contract; this is a plain match for issuer-tier gates (e.g.
    /// Legion custom tiers) that live outside the K_* fact-keys. Index-backed: scans only same-label tokens.
    function hasValidCredential(address owner, bytes32 categoryId) public view returns (bool) {
        uint256[] storage ids = LeXcheXBadgeStorage.getLabelTokens(owner, categoryId);
        for (uint256 i = 0; i < ids.length; i++) {
            if (isValid(ids[i])) return true;
        }
        return false;
    }

    /// @notice True when the owner holds a valid credential asserting `kindKey` (a K_* status/kind fact-key).
    /// Serves the LexChex parameterizations (accredited / QP / QIB / bad-actor-clear / non-U.S. person).
    function hasValidCredentialOf(address owner, uint256 kindKey) public view returns (bool) {
        (, bool found) = _mostRecentValidWith(owner, kindKey);
        return found;
    }

    /// @notice True when the owner holds a valid credential granting scoped entitlement `scopeKey` for `spv`.
    /// An entitlement answers only for the SPV it names, so one SPV's membership never leaks to another. Any
    /// valid credential carrying the key and scope admits — a second grant of the same entitlement says the
    /// same thing, so there is no recency contest. Scans the (bounded) active set.
    function hasValidScopedCredentialOf(address owner, uint256 scopeKey, address spv) public view returns (bool) {
        uint256[] storage ids = LeXcheXBadgeStorage.getActiveTokens(owner);
        for (uint256 i = 0; i < ids.length; i++) {
            Credential storage cred = LeXcheXBadgeStorage.getCredential(ids[i]);
            if ((cred.asserts & scopeKey) != 0 && cred.scope == spv && isValid(ids[i])) return true;
        }
        return false;
    }

    /// @notice Admission to one SPV's offers: backs per-SPV offer-visibility entitlements (§16.2) and any
    /// onchain issuer gating.
    function hasValidWhitelistFor(address owner, address spv) public view returns (bool) {
        return hasValidScopedCredentialOf(owner, K_SPV_WHITELIST, spv);
    }

    /// @notice A seat in the issuer's private circle within one SPV (§4.1.3A). Read apart from the whitelist
    /// so an issuer can restrict a trade to the circle without admission to the SPV standing in for it.
    function hasValidSyndicateFor(address owner, address spv) public view returns (bool) {
        return hasValidScopedCredentialOf(owner, K_SYNDICATE, spv);
    }

    /// @notice Individual vs. entity from the owner's authoritative credential; UNSET when unestablished. Only
    /// an entity can have beneficial owners to look through, so this qualifies the §3(c)(1)(A) count.
    function getInvestorType(address owner) public view returns (InvestorType) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, K_INVESTOR_TYPE);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).investorType : InvestorType.UNSET;
    }

    /// @notice U.S. state of residence/organization for USStateOfResidenceCondition; empty when unestablished.
    function getUsState(address owner) public view returns (bytes2) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, K_US_STATE);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).usState : bytes2(0);
    }

    /// @notice Beneficial-owner count for the §3(c)(1)(A) look-through; 0 when unestablished (callers decide
    /// how to treat a zero — e.g. count as one holder).
    function getEffectiveBeneficialOwnerCount(address owner) public view returns (uint32) {
        if (getInvestorType(owner) == InvestorType.INDIVIDUAL) return 1;
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, K_BO_COUNT);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).beneficialOwnerCount : 0;
    }

    /// @notice Generic programmable payload from the owner's authoritative credential; empty when none. The
    /// badge never interprets it — downstream programs/conditions do, gated by K_DATA.
    function getData(address owner) public view returns (bytes memory) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, K_DATA);
        if (!found) return "";
        return LeXcheXBadgeStorage.getCredential(tokenId).data;
    }

    /// @notice Physical country jurisdiction from the owner's authoritative credential; empty when none.
    function getInvestorJurisdiction(address owner) public view returns (string memory) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, K_INVESTOR_JURISDICTION);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).investorJurisdiction : "";
    }

    /// @notice §3(c)(1)(A) look-through classification from the owner's authoritative credential; empty when
    /// none. An offshore entity with any U.S. beneficial owner reads U.S. here (regulatory view) while its
    /// physical investorJurisdiction stays foreign for CFIUS/blue-sky. Decoupled from investorJurisdiction.
    function getLookThroughJurisdiction(address owner) public view returns (string memory) {
        (uint256 tokenId, bool found) = _mostRecentValidWith(owner, K_LOOKTHROUGH_JURISDICTION);
        return found ? LeXcheXBadgeStorage.getCredential(tokenId).lookThroughJurisdiction : "";
    }

    /// @notice Seasoning reference for the UI (§11.1B): earliest valid issuance asserting `kindKey`; 0 when none.
    /// The seasoning policy (30 vs 45 days) stays at the UI layer; this only supplies the timestamp.
    function earliestValidIssuance(address owner, uint256 kindKey) public view returns (uint64) {
        if (kindKey == 0) return 0; // the empty key answers no fact; see _mostRecentValidWith

        uint64 earliest = 0;
        uint256[] storage ids = LeXcheXBadgeStorage.getActiveTokens(owner);
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            if (!isValid(tokenId)) continue;
            Credential storage cred = LeXcheXBadgeStorage.getCredential(tokenId);
            if ((cred.asserts & kindKey) != kindKey) continue;
            if (earliest == 0 || cred.issuanceDate < earliest) earliest = cred.issuanceDate;
        }
        return earliest;
    }

    // ── Carried over from LeXcheX v1 (interface-compatible reads, §0.10) ─────

    /// @notice v1-compatible read: true when the owner holds any valid credential (scans the active set)
    function hasValidLexCheX(address owner) public view returns (bool) {
        uint256[] storage ids = LeXcheXBadgeStorage.getActiveTokens(owner);
        for (uint256 i = 0; i < ids.length; i++) {
            if (isValid(ids[i])) return true;
        }
        return false;
    }

    /// @notice ALL token ids owned (incl. voided/expired), via ERC-721 enumeration — the full audit record.
    function getTokenIdsByOwner(address owner) public view returns (uint256[] memory) {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    /// @notice The holder's active-set token ids (non-voided, not-yet-swept) — what compliance reads scan.
    function getActiveTokenIds(address owner) public view returns (uint256[] memory) {
        return LeXcheXBadgeStorage.getActiveTokens(owner);
    }

    /// @notice v1-compatible read (getAccreditationByOwner-style): a valid credential of the owner, lowest
    /// token id first. Voided and expired records are kept for audit but are not credentials, so an owner
    /// left with only those has none.
    function getCredentialByOwner(address owner) public view returns (uint256) {
        uint256 balance = balanceOf(owner);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            if (isValid(tokenId)) return tokenId;
        }
        revert LexChexBadge_NoValidCredential();
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

    /// @dev Issuance is the only move a credential makes: no transfer, and no burn either, since the record
    /// must survive revocation and the sweeps read the holder from ownership. Checked here rather than left
    /// to there being no burn function, so an upgrade that adds one cannot erase a credential.
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        if (_ownerOf(tokenId) != address(0)) {
            revert LexChexBadge_SoulBound();
        }
        return super._update(to, tokenId, auth);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // tokenURI (§0.8) — sensitive attributes (usState, beneficialOwnerCount,
    // evidenceHash) are NOT rendered
    // ─────────────────────────────────────────────────────────────────────────

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        Credential memory cred = LeXcheXBadgeStorage.getCredential(tokenId);
        return LeXcheXBadgeRender.tokenURI(tokenId, cred, isValid(tokenId));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev The owner's authoritative credential for `key`: the most recent (by issuanceDate — a superseding
    /// credential wins; ties → higher tokenId) valid credential that asserts every requested fact-key, so an
    /// unrelated credential can neither answer the fact nor shadow one that does. Scans the (bounded) active set;
    /// expired-but-not-yet-swept entries are skipped by isValid.
    function _mostRecentValidWith(address owner, uint256 key) internal view returns (uint256 tokenId, bool found) {
        // reject empty key early
        if (key == 0) return (0, false);

        uint64 latest = 0;
        uint256[] storage ids = LeXcheXBadgeStorage.getActiveTokens(owner);
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 candidate = ids[i];
            if (!isValid(candidate)) continue;
            Credential storage cred = LeXcheXBadgeStorage.getCredential(candidate);
            if ((cred.asserts & key) != key) continue; // asserts every requested key
            if (!found || cred.issuanceDate > latest || (cred.issuanceDate == latest && candidate > tokenId)) {
                latest = cred.issuanceDate;
                tokenId = candidate;
                found = true;
            }
        }
    }

    /// @dev `asserts` is the sole source of truth: reject empty/unknown bits, require a value for each asserted
    /// VALUE key and a scope for whitelist/syndicate keys. Category schemas are off-chain; nothing here reads a
    /// category. Status keys carry no value — asserting them is the assertion.
    function _validate(Credential memory cred) internal pure {
        uint256 a = cred.asserts;
        if (a == 0 || (a & ~ALL_KEYS) != 0) revert LexChexBadge_BadAsserts();
        if ((a & K_INVESTOR_TYPE) != 0 && cred.investorType == InvestorType.UNSET) revert LexChexBadge_MissingValue(K_INVESTOR_TYPE);
        if ((a & K_INVESTOR_JURISDICTION) != 0 && bytes(cred.investorJurisdiction).length == 0) revert LexChexBadge_MissingValue(K_INVESTOR_JURISDICTION);
        if ((a & K_LOOKTHROUGH_JURISDICTION) != 0 && bytes(cred.lookThroughJurisdiction).length == 0) revert LexChexBadge_MissingValue(K_LOOKTHROUGH_JURISDICTION);
        if ((a & K_US_STATE) != 0 && cred.usState == bytes2(0)) revert LexChexBadge_MissingValue(K_US_STATE);
        if ((a & K_BO_COUNT) != 0 && cred.beneficialOwnerCount == 0) revert LexChexBadge_MissingValue(K_BO_COUNT);
        // Only an entity has beneficial owners, and the type must be asserted on the same credential to be
        // authoritative. A count on a natural person would inflate the §3(c)(1)(A) tally.
        if ((a & K_BO_COUNT) != 0 && ((a & K_INVESTOR_TYPE) == 0 || cred.investorType != InvestorType.ENTITY)) {
            revert LexChexBadge_BoCountRequiresEntity();
        }
        if ((a & K_DATA) != 0 && cred.data.length == 0) revert LexChexBadge_MissingValue(K_DATA);
        if ((a & SCOPED_KEYS) != 0 && cred.scope == address(0)) revert LexChexBadge_MissingScope();
    }

    /// @dev Only owner can upgrade it
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

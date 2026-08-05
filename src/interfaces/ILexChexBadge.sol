// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./IERC5484.sol";
import {Credential} from "../creds/storage/lexchexBadgeStorage.sol";

// Fact-keys — a credential's `asserts` bitmask is the sole authority axis. VALUE keys carry a payload in the
// matching Credential field; STATUS keys carry no payload (asserting the key IS the truth); SCOPE keys require
// Credential.scope (the SPV entitled). Each group owns a bit block (VALUE 0-15, STATUS 16-31, SCOPE 32+) so a
// new key joins its own kind without reshuffling, and a key's group is legible from its position.
uint256 constant K_INVESTOR_TYPE           = 1 << 0;   // Individual / entity
uint256 constant K_INVESTOR_JURISDICTION   = 1 << 1;   // physical country of residence/organization
uint256 constant K_LOOKTHROUGH_JURISDICTION = 1 << 2;   // §3(c)(1)(A) look-through classification
uint256 constant K_US_STATE                = 1 << 3;   // U.S. state of residence/organization
uint256 constant K_BO_COUNT                = 1 << 4;   // entity §3(c)(1)(A) look-through count
uint256 constant K_DATA                    = 1 << 5;   // generic programmable payload (Credential.data bytes blob)

uint256 constant K_ACCREDITED      = 1 << 16;
uint256 constant K_QP              = 1 << 17;          // qualified purchaser
uint256 constant K_QIB             = 1 << 18;          // qualified institutional buyer
uint256 constant K_BAD_ACTOR_CLEAR = 1 << 19;          // Rule 506(d) disqualification cleared
uint256 constant K_NON_US          = 1 << 20;          // Reg S (§6.5): the holder is not a U.S. person

uint256 constant STATUS_KEYS = K_ACCREDITED | K_QP | K_QIB | K_BAD_ACTOR_CLEAR | K_NON_US;

// SCOPE keys. A whitelist admits the holder to one SPV's offers (§16.2); a syndicate seats them in that
// issuer's private circle (§4.1.3A). Separate grants an issuer makes for separate reasons, so neither key
// ever satisfies the other, and each names the SPV it entitles in Credential.scope.
uint256 constant K_SPV_WHITELIST = 1 << 32;
uint256 constant K_SYNDICATE     = 1 << 33;

uint256 constant SCOPED_KEYS = K_SPV_WHITELIST | K_SYNDICATE;

uint256 constant ALL_KEYS = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_US_STATE
    | K_BO_COUNT | K_DATA | K_ACCREDITED | K_QP | K_QIB | K_BAD_ACTOR_CLEAR | K_NON_US | SCOPED_KEYS;

// Presets: recommended `asserts` per badge purpose (issuer guidance only — OR in extras as needed).
uint256 constant PRESET_KYC_AML             = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
uint256 constant PRESET_US_RESIDENCY        = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_US_STATE;
uint256 constant PRESET_ENTITY_LOOKTHROUGH  = K_INVESTOR_TYPE | K_LOOKTHROUGH_JURISDICTION | K_BO_COUNT;
uint256 constant PRESET_ACCREDITED          = K_ACCREDITED;
uint256 constant PRESET_QUALIFIED_PURCHASER = K_QP;
uint256 constant PRESET_QIB                 = K_QIB;
uint256 constant PRESET_BAD_ACTOR_CLEAR     = K_BAD_ACTOR_CLEAR;
uint256 constant PRESET_NON_US              = K_NON_US;
uint256 constant PRESET_SPV_WHITELIST       = K_SPV_WHITELIST;
uint256 constant PRESET_SYNDICATE           = K_SYNDICATE;

/// @notice Value for K_INVESTOR_TYPE. UNSET is the empty value: a credential asserting the key must name one of
/// the real types, and a holder with no such credential reads UNSET.
enum InvestorType {
    UNSET,
    INDIVIDUAL,
    ENTITY
}

/// @title ILexChexBadge - read/lifecycle interface for the LeXcheXBadge credential registry
/// @author MetaLeX Labs, Inc.
/// @notice The credential substrate the cyberTRADE threshold conditions read. One deployment = one
/// credentialing layer under one operator's BorgAuth (Legion, MetaLeX canonical, or another operator).
/// @dev A credential's `asserts` bitmask (the K_* fact-keys declared above) is the sole authority axis.
/// Credentials are immutable once minted: supersede by minting a newer one (recency wins) and revoke by
/// voiding — there is no in-place edit and no burn. Value getters return the field's empty value (0, "",
/// bytes2(0)) when the holder has no valid credential asserting the fact. Empty is reported, never interpreted:
/// whether an unestablished fact should fail open or closed is each condition's own decision.
interface ILexChexBadge is IERC5484 {
    // Events (indexer surface: Ponder ingests these for /api/offers eligibility and the admin panel §8.7)
    event CredentialIssued(address indexed owner, uint256 indexed tokenId, Credential cred);
    event CredentialVoided(address indexed owner, uint256 indexed tokenId, string reason);
    /// @notice A sweep dropped an expired credential from the holder's active set. Housekeeping, not a status
    /// change: the credential stopped counting back at its expiryDate, which may be long before this event.
    /// Read it to track active-set size (the keeper's workload) and to confirm a sweep transaction did work.
    event CredentialSwept(address indexed owner, uint256 indexed tokenId);

    error LexChexBadge_SoulBound();
    error LexChexBadge_TokenDoesNotExist();
    error LexChexBadge_InvalidExpiry();
    error LexChexBadge_BadAsserts();
    error LexChexBadge_MissingValue(uint256 key);
    error LexChexBadge_MissingScope();
    error LexChexBadge_MissingVoidReason();
    error LexChexBadge_BoCountRequiresEntity();
    error LexChexBadge_NoValidCredential();

    // ── Lifecycle ────────────────────────────────────────────────────────────
    function mint(address to, Credential memory cred) external returns (uint256 tokenId);
    function void(uint256 tokenId, string memory reason) external;
    /// @notice Voids `staleTokenId` and issues `cred` to the same holder in one call. How to retract a fact:
    /// a new credential alone cannot, since the old one keeps answering until voided.
    function supersede(uint256 staleTokenId, Credential memory cred, string memory reason)
        external
        returns (uint256 tokenId);
    /// @notice Permissionless keeper hook: evict the holder's expired credentials from the active set.
    function sweep(address holder) external;
    /// @notice Sweep several holders in one keeper transaction.
    function sweepHolders(address[] calldata holders) external;
    /// @notice Evict the named expired credentials in a batch bounded by its own calldata, so an active set too
    /// large for a one-transaction `sweep` still drains over successive calls. Only expired ids are evictable.
    function sweepTokens(uint256[] calldata tokenIds) external returns (uint256 evicted);

    // ── Validity reads (issued, not voided, not expired) ─────────────────────
    function isValid(uint256 tokenId) external view returns (bool);
    /// @notice True when the owner holds a valid credential carrying the free-form issuer label `categoryId`.
    function hasValidCredential(address owner, bytes32 categoryId) external view returns (bool);
    /// @notice True when the owner's valid credentials together assert every fact-key in `kindKey` (K_* status/
    /// kind keys). Note they do not have to live in the same badge token.
    function hasValidCredentialOf(address owner, uint256 kindKey) external view returns (bool);
    /// @notice True when the owner holds a valid credential granting scoped entitlement `scopeKey` for `spv`.
    /// An entitlement granted for another SPV never answers here.
    function hasValidScopedCredentialOf(address owner, uint256 scopeKey, address spv) external view returns (bool);
    function hasValidWhitelistFor(address owner, address spv) external view returns (bool);
    /// @notice True when the owner holds a valid syndicate seat in `spv`'s circle. Never satisfied by a
    /// whitelist credential, nor by a syndicate seat in another SPV.
    function hasValidSyndicateFor(address owner, address spv) external view returns (bool);

    // ── Attribute getters (most recent valid credential asserting the fact; empty value when none) ──
    /// Every value getter also returns `expiry`: when the credential answering the fact lapses, 0 when none
    /// answers it. A caller reading live can ignore it — the value is already validity-filtered. A caller that
    /// CACHES the value must keep it: expiry moves nothing on-chain, so there is no other way to learn the
    /// fact behind a cached answer went stale.

    /// @notice Individual vs. entity; UNSET when unestablished. Qualifies the §3(c)(1)(A) look-through count.
    function getInvestorType(address owner) external view returns (InvestorType value, uint64 expiry);
    function getUsState(address owner) external view returns (bytes2 value, uint64 expiry);
    /// @notice §3(c)(1)(A) look-through count; 0 when unestablished. An authoritative INDIVIDUAL reads 1 (a
    /// natural person is one beneficial owner), so a zero here means no count is established, never "none".
    /// That branch carries the investor-type credential's expiry, since that is what establishes the 1.
    function getEffectiveBeneficialOwnerCount(address owner) external view returns (uint32 value, uint64 expiry);
    /// @notice Generic programmable payload (bytes) the badge stores but never interprets; empty when none.
    function getData(address owner) external view returns (bytes memory value, uint64 expiry);
    function getInvestorJurisdiction(address owner) external view returns (string memory value, uint64 expiry);
    /// @notice §3(c)(1)(A) look-through classification; decoupled from investorJurisdiction.
    function getLookThroughJurisdiction(address owner) external view returns (string memory value, uint64 expiry);

    /// @notice Seasoning reference (§11.1B): when the earliest valid credential carrying ALL of `kindKey` was
    /// issued. Note all kindKey specified must live on the same badge token to qualify
    function earliestValidIssuance(address owner, uint256 kindKey) external view returns (uint64);

    // ── Carried over from LeXcheX v1 ─────────────────────────────────────────
    function hasValidLexCheX(address owner) external view returns (bool);
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);
    /// @notice Active-set token ids (non-voided, not-yet-swept) — what compliance reads scan.
    function getActiveTokenIds(address owner) external view returns (uint256[] memory);
    function getCredentialByOwner(address owner) external view returns (uint256 tokenId);
    function getCredential(uint256 tokenId) external view returns (Credential memory);
    function balanceOf(address owner) external view returns (uint256);
}

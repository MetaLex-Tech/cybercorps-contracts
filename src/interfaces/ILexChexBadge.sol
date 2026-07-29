// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./IERC5484.sol";
import {Credential} from "../creds/storage/lexchexBadgeStorage.sol";

// Fact-keys — a credential's `asserts` bitmask is the sole authority axis. VALUE keys carry a payload in the
// matching Credential field; STATUS keys carry no payload (asserting the key IS the truth); SCOPE keys require
// Credential.scope (the SPV entitled). Free bit ranges are left between the groups so issuers/upgrades can add
// keys without reshuffling.
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

// One scoped-entitlement key covers per-SPV whitelist and syndicate alike (read identically by
// hasValidWhitelistFor); the whitelist-vs-syndicate label, if any, lives in the off-chain categoryId/notes.
uint256 constant K_SPV_WHITELIST = 1 << 20;

uint256 constant ALL_KEYS = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_LOOKTHROUGH_JURISDICTION | K_US_STATE
    | K_BO_COUNT | K_DATA | K_ACCREDITED | K_QP | K_QIB | K_BAD_ACTOR_CLEAR | K_SPV_WHITELIST;

// Presets: recommended `asserts` per badge purpose (issuer guidance only — OR in extras as needed).
uint256 constant PRESET_KYC_AML             = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION;
uint256 constant PRESET_US_RESIDENCY        = K_INVESTOR_TYPE | K_INVESTOR_JURISDICTION | K_US_STATE;
uint256 constant PRESET_ENTITY_LOOKTHROUGH  = K_INVESTOR_TYPE | K_LOOKTHROUGH_JURISDICTION | K_BO_COUNT;
uint256 constant PRESET_ACCREDITED          = K_ACCREDITED;
uint256 constant PRESET_QUALIFIED_PURCHASER = K_QP;
uint256 constant PRESET_QIB                 = K_QIB;
uint256 constant PRESET_BAD_ACTOR_CLEAR     = K_BAD_ACTOR_CLEAR;
uint256 constant PRESET_SPV_WHITELIST       = K_SPV_WHITELIST;

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
/// bytes2(0)) when the holder has no valid credential asserting the fact; the `isUSLookThroughInvestor` convenience
/// getter instead resolves an unknown holder conservatively as U.S.
interface ILexChexBadge is IERC5484 {
    // Events (indexer surface: Ponder ingests these for /api/offers eligibility and the admin panel §8.7)
    event CredentialIssued(address indexed owner, uint256 indexed tokenId, Credential cred);
    event CredentialVoided(address indexed owner, uint256 indexed tokenId, string reason);

    error LexChexBadge_SoulBound();
    error LexChexBadge_TokenDoesNotExist();
    error LexChexBadge_InvalidExpiry();
    error LexChexBadge_BadAsserts();
    error LexChexBadge_MissingValue(uint256 key);
    error LexChexBadge_MissingScope();

    // ── Lifecycle ────────────────────────────────────────────────────────────
    function mint(address to, Credential memory cred) external returns (uint256 tokenId);
    function void(uint256 tokenId, string memory reason) external;
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
    /// @notice True when the owner holds a valid credential asserting `kindKey` (a K_* status/kind fact-key).
    function hasValidCredentialOf(address owner, uint256 kindKey) external view returns (bool);
    function hasValidWhitelistFor(address owner, address spv) external view returns (bool);

    // ── Attribute getters (most recent valid credential asserting the fact; empty value when none) ──
    /// @notice Individual vs. entity; UNSET when unestablished. Qualifies the §3(c)(1)(A) look-through count.
    function getInvestorType(address owner) external view returns (InvestorType);
    function getUsState(address owner) external view returns (bytes2);
    function getBeneficialOwnerCount(address owner) external view returns (uint32);
    /// @notice Generic programmable payload (bytes) the badge stores but never interprets; empty when none.
    function getData(address owner) external view returns (bytes memory);
    function getInvestorJurisdiction(address owner) external view returns (string memory);
    /// @notice §3(c)(1)(A) look-through classification; decoupled from investorJurisdiction.
    function getLookThroughJurisdiction(address owner) external view returns (string memory);
    /// @notice True when the owner counts as a U.S. investor for the ICA look-through. Conservative: U.S. if
    /// either the regulatory classification or the physical investorJurisdiction is U.S., and U.S. when
    /// jurisdiction is entirely unestablished (unknown → U.S.). Sole home for the rule.
    function isUSLookThroughInvestor(address owner) external view returns (bool);
    /// @notice Canonical U.S.-jurisdiction string test ("US"/"USA"/"United States"); shared so downstream
    /// conditions (e.g. CFIUS) don't replicate the match.
    function isUSJurisdiction(string memory jurisdiction) external pure returns (bool);

    /// @notice Seasoning reference (§11.1B): earliest valid issuance asserting `kindKey`; 0 when none.
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

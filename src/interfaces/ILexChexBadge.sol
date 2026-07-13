// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./IERC5484.sol";
import {CategoryKind, Credential, CredentialCategory} from "../creds/storage/lexchexBadgeStorage.sol";

/// @title ILexChexBadge - read/lifecycle interface for the LeXcheXBadge credential registry
/// @author MetaLeX Labs, Inc.
/// @notice The credential substrate the cyberTRADE threshold conditions read. One deployment = one
/// credentialing layer under one operator's BorgAuth (Legion, MetaLeX canonical, or another operator).
interface ILexChexBadge is IERC5484 {
    // ── Lifecycle ────────────────────────────────────────────────────────────
    function mint(address to, bytes32 categoryId, Credential memory cred) external returns (uint256 tokenId);
    function recertify(uint256 tokenId, Credential memory cred) external;
    function updateAttributes(uint256 tokenId, bytes2 usState, uint32 beneficialOwnerCount) external;
    function setRegulatoryJurisdiction(uint256 tokenId, string calldata jurisdiction) external;
    function void(uint256 tokenId, string memory reason) external;
    function burn(uint256 tokenId) external;

    // ── Category admin ───────────────────────────────────────────────────────
    function createCategory(bytes32 categoryId, CredentialCategory memory category) external;
    function updateCategory(bytes32 categoryId, CredentialCategory memory category) external;
    function retireCategory(bytes32 categoryId) external;
    function getCategory(bytes32 categoryId) external view returns (CredentialCategory memory);
    function getCategoryIds() external view returns (bytes32[] memory);

    // ── Validity reads (issued, not voided, not expired) ─────────────────────
    function isValid(uint256 tokenId) external view returns (bool);
    function hasValidCredential(address owner, bytes32 categoryId) external view returns (bool);
    function hasValidCredentialOfKind(address owner, CategoryKind kind, string memory investorTypeFilter) external view returns (bool);
    function hasValidWhitelistFor(address owner, address spv) external view returns (bool);

    // ── Attribute getters (sourced from the most recent valid credential carrying the attribute) ──
    function getUsState(address owner) external view returns (bytes2);
    function getBeneficialOwnerCount(address owner) external view returns (uint32);
    function getInvestorJurisdiction(address owner) external view returns (string memory);
    /// @notice §3(c)(1)(A) look-through classification (empty when unset); decoupled from investorJurisdiction.
    function getRegulatoryJurisdiction(address owner) external view returns (string memory);
    /// @notice True when the owner counts as a U.S. investor for the ICA look-through. Conservative: U.S. if
    /// either the regulatory classification or the physical investorJurisdiction is U.S. Sole home for the rule.
    function isUSInvestor(address owner) external view returns (bool);

    /// @notice Seasoning reference (§11.1B): earliest valid issuance of the given kind; 0 when none.
    function earliestValidIssuance(address owner, CategoryKind kind) external view returns (uint64);

    // ── Carried over from LeXcheX v1 ─────────────────────────────────────────
    function hasValidLexCheX(address owner) external view returns (bool);
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);
    function getCredentialByOwner(address owner) external view returns (uint256 tokenId);
    function getCredential(uint256 tokenId) external view returns (Credential memory);
    function balanceOf(address owner) external view returns (uint256);
}

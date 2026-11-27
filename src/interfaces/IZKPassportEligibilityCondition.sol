// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ICondition} from "./ICondition.sol";
import {IZKPassportVerifier, ProofVerificationParams} from "./IZKPassportVerifier.sol";

/// @notice Immutable passport eligibility criteria enforced by a ZKPassportEligibilityCondition instance.
/// @param allowedNationalities Sorted ISO 3166-1 alpha-3 uppercase codes permitted to pass; empty = no allowlist.
/// @param excludedNationalities Sorted ISO 3166-1 alpha-3 uppercase codes blocked from passing; empty = no exclusion list.
/// @param minimumAge Minimum age required (1..99); 0 = no age requirement.
/// @param enforceSanctions If true, enforces ZKPassport's non-strict sanctions watchlist check.
struct EligibilityRules {
    string[] allowedNationalities;
    string[] excludedNationalities;
    uint8 minimumAge;
    bool enforceSanctions;
}

interface IZKPassportEligibilityCondition is ICondition {
    function DEPLOY_VERSION() external pure returns (string memory);
    function verifier() external view returns (IZKPassportVerifier);
    function expectedDomain() external view returns (string memory);
    function expectedScope() external view returns (string memory);
    function maxValidityPeriod() external view returns (uint256);
    function devModeAllowed() external view returns (bool);
    function minimumAge() external view returns (uint8);
    function enforceSanctions() external view returns (bool);

    function getAllowedNationalities() external view returns (string[] memory);
    function getExcludedNationalities() external view returns (string[] memory);
    function getRules() external view returns (EligibilityRules memory);

    function proofExpiry(address account) external view returns (uint256);
    function uniqueIdentifierExpiry(bytes32 uniqueIdentifier) external view returns (uint256);
    function walletOfIdentifier(bytes32 uniqueIdentifier) external view returns (address);
    function identifierOfWallet(address account) external view returns (bytes32);
    function founderOverrides(address manager, address investor) external view returns (bool);

    function isEligible(address manager, address investor) external view returns (bool);

    function submitProof(ProofVerificationParams calldata params) external;
    function setFounderOverride(address manager, address investor, bool approved) external;
}

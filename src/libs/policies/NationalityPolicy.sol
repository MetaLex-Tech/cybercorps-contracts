// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ILexChexBadge, K_NATIONALITY_OUT} from "../../interfaces/ILexChexBadge.sol";
import {Credential} from "../../creds/storage/lexchexBadgeStorage.sol";

/// @title  NationalityPolicy - finds one country in the badge nationality list
/// @author MetaLeX Labs, Inc.
/// @notice K_NATIONALITY_OUT is a VALUE key. The credential records a list of countries. It does not record a yes
/// or no answer for one country. A condition must therefore read the list and find the country in it. This library
/// does that check. Thus the badge stays a simple registry, and all conditions do the same check.
/// @dev The library compares the country codes with a hash. The caller must use the same format as the issuer, for
/// example ISO alpha-2 or ISO alpha-3. The library gives only the attested facts. If there is no such credential,
/// the condition must decide what to do.
library NationalityPolicy {
    /// @notice Finds if `owner` has a valid credential that shows `owner` is not a national of `code`. The
    /// function also gives the expiry of that credential. The expiry is 0 if there is no such credential. The
    /// function accepts all issuers.
    function excludes(ILexChexBadge badge, address owner, string memory code)
        internal
        view
        returns (bool excluded, uint64 expiry)
    {
        if (address(badge) == address(0)) return (false, 0);
        (string[] memory list, uint64 listExpiry) = badge.getNationalityOut(owner);
        return _contains(list, code) ? (true, listExpiry) : (false, 0);
    }

    /// @notice The same check, but the function accepts only the credentials from `issuers`. There is no different
    /// fact-key for a different type of attestation. A condition that accepts only a ZK proof, or only its own
    /// operator, gives that issuer here.
    function excludes(ILexChexBadge badge, address owner, string memory code, address[] memory issuers)
        internal
        view
        returns (bool excluded, uint64 expiry)
    {
        if (address(badge) == address(0)) return (false, 0);
        (uint256 tokenId, bool found) = badge.getMostRecentValidWith(owner, K_NATIONALITY_OUT, issuers);
        if (!found) return (false, 0);
        Credential memory cred = badge.getCredential(tokenId);
        return _contains(cred.nationalityOut, code) ? (true, cred.expiryDate) : (false, 0);
    }

    function _contains(string[] memory list, string memory code) private pure returns (bool) {
        bytes32 target = keccak256(bytes(code));
        for (uint256 i = 0; i < list.length; i++) {
            if (keccak256(bytes(list[i])) == target) return true;
        }
        return false;
    }
}

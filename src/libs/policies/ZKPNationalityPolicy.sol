// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ILexChexBadge} from "../../interfaces/ILexChexBadge.sol";

/// @title  ZKPNationalityPolicy - reads the badge's ZKPassport nationality-exclusion fact
/// @author MetaLeX Labs, Inc.
/// @notice K_ZKP_NATIONALITY_OUT is a VALUE key: the credential records WHICH country codes were proven excluded,
/// not a bare yes/no. So a condition asking "is this wallet proven excluded from country X?" must read the list
/// and check membership. That check lives here, so the badge stays a plain registry and every condition reads it
/// the same way (rather than re-implementing the string-list scan).
/// @dev Codes are compared verbatim by hash — the caller passes the same convention the issuer recorded (e.g.
/// ISO alpha-2/alpha-3). Reports only what was proven; whether an unproven exclusion should fail open or closed
/// is the calling condition's decision.
library ZKPNationalityPolicy {
    /// @notice Whether `owner` holds a valid ZKPassport credential proving they are NOT a national of `code`, and
    /// when that answer expires (0 when no such credential exists).
    function excludes(ILexChexBadge badge, address owner, string memory code)
        internal
        view
        returns (bool excluded, uint64 expiry)
    {
        if (address(badge) == address(0)) return (false, 0);
        (string[] memory list, uint64 listExpiry) = badge.getZkpNationalityOut(owner);
        bytes32 target = keccak256(bytes(code));
        for (uint256 i = 0; i < list.length; i++) {
            if (keccak256(bytes(list[i])) == target) return (true, listExpiry);
        }
        return (false, 0);
    }
}

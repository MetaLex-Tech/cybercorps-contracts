// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ILexChexBadge, K_ACCREDITED} from "../../interfaces/ILexChexBadge.sol";

/// @title  AccreditationPolicy - accredited-investor reading of the LeXcheX badge for the holder tally
/// @author MetaLeX Labs, Inc.
/// @notice One rule for both sides of the count of holders who are not accredited: the printer books its
/// holders with it, and HolderCapCondition reads the buyer's status through the printer, which uses it too.
/// @dev An address is accredited when the registry has a valid (issued, not voided, not expired) credential
/// that asserts `K_ACCREDITED` for it. No registry means nothing is established, so not accredited.
/// The badge contract is read only; it does not change.
///
/// Both reads fail closed and do not revert. A registry that cannot answer (for example an older badge
/// implementation without these reads) gives "not accredited" and "voided", which only raise the count of
/// holders who are not accredited. A revert here would stop every mint and transfer of the printer, because
/// the tally runs inside them.
library AccreditationPolicy {
    /// @notice The most recent valid credential asserting `K_ACCREDITED` for `owner`, if any.
    function accreditedCredential(ILexChexBadge badge, address owner)
        internal
        view
        returns (bool found, uint256 credentialId)
    {
        if (address(badge) == address(0)) return (false, 0);
        // The overload with two arguments: no issuer, scope or hook filter.
        (bool ok, bytes memory ret) = address(badge).staticcall(
            abi.encodeWithSignature("getMostRecentValidWith(address,uint256)", owner, K_ACCREDITED)
        );
        if (!ok || ret.length < 64) return (false, 0);
        (credentialId, found) = abi.decode(ret, (uint256, bool));
    }

    /// @notice Whether `owner` is accredited now, under the rule above.
    function isAccredited(ILexChexBadge badge, address owner) internal view returns (bool accredited) {
        (accredited,) = accreditedCredential(badge, owner);
    }

    /// @notice Whether the issuer or an admin voided the credential (`void` or `supersede`). A voided
    /// credential keeps a non-empty reason on its record. A credential that only lapsed is not voided.
    /// No registry, or a registry that cannot answer, reads as voided.
    function isVoided(ILexChexBadge badge, uint256 credentialId) internal view returns (bool) {
        if (address(badge) == address(0)) return true;
        (bool ok, bytes memory ret) =
            address(badge).staticcall(abi.encodeWithSelector(ILexChexBadge.getCredential.selector, credentialId));
        // One dynamic tuple: word 0 is its offset (0x20); `voided` is member 11 of 15, so its offset sits in
        // word 1 + 11 of the return data, relative to the tuple start at byte 32.
        if (!ok || ret.length < 32 * 16) return true;
        uint256 off;
        assembly ("memory-safe") {
            off := mload(add(ret, mul(32, 13)))
        }
        if (off > ret.length || 32 + off + 32 > ret.length) return true;
        uint256 len;
        assembly ("memory-safe") {
            len := mload(add(add(ret, 64), off))
        }
        return len > 0;
    }
}

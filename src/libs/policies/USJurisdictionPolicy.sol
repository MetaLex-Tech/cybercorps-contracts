// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @title  USJurisdictionPolicy - reads a jurisdiction credential as U.S. or not
/// @author MetaLeX Labs, Inc.
/// @notice Shared by every condition that has to tell a U.S. jurisdiction from a foreign one, so the set of
/// accepted spellings cannot drift between them and silently move a party across a regulatory line.
/// @dev Only the spelling is shared. What an unestablished (empty) jurisdiction means is regime-specific —
/// it reads as not-U.S. here, and each consumer decides whether that is the safe answer before calling in.
library USJurisdictionPolicy {
    function isUS(string memory jurisdiction) internal pure returns (bool) {
        bytes32 h = keccak256(bytes(jurisdiction));
        return h == keccak256("US") || h == keccak256("USA") || h == keccak256("United States");
    }
}

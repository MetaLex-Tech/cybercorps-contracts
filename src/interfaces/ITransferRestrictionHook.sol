// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @title ITransferRestrictionHook
/// @notice Interface for transfer restriction hooks
interface ITransferRestrictionHook {
    /// @notice Check if a transfer is allowed
    /// @param from The address tokens are being transferred from
    /// @param to The address tokens are being transferred to
    /// @param tokenId The ID of the token being transferred
    /// @param data Additional data passed to the hook
    /// @return allowed Whether the transfer is allowed
    /// @return reason The reason if the transfer is not allowed
    function checkTransferRestriction(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external view returns (bool allowed, string memory reason);
} 
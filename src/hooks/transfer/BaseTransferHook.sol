// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "../interfaces/ITransferRestrictionHook.sol";
import "../libs/auth.sol";

/// @title BaseTransferHook
/// @notice Base contract for implementing transfer restriction hooks
/// @dev Inherit from this contract to create custom transfer restriction hooks
abstract contract BaseTransferHook is ITransferRestrictionHook, BorgAuthACL {
    // Custom errors
    error HookNotEnabled();
    error InvalidParameters();
    
    // Whether the hook is enabled
    bool public enabled;
    
    // Event for when the hook is enabled/disabled
    event HookStatusChanged(bool enabled);
    
    constructor(address _auth) BorgAuthACL(_auth) {}
    
    /// @notice Enable or disable the hook
    /// @param _enabled Whether to enable or disable the hook
    function setEnabled(bool _enabled) external onlyAdmin {
        enabled = _enabled;
        emit HookStatusChanged(_enabled);
    }
    
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
    ) public view virtual override returns (bool allowed, string memory reason) {
        if (!enabled) return (true, "");
        
        return _checkTransferRestriction(from, to, tokenId, data);
    }
    
    /// @notice Internal function to implement the actual transfer restriction logic
    /// @dev Override this function in derived contracts to implement specific restriction logic
    /// @param from The address tokens are being transferred from
    /// @param to The address tokens are being transferred to
    /// @param tokenId The ID of the token being transferred
    /// @param data Additional data passed to the hook
    /// @return allowed Whether the transfer is allowed
    /// @return reason The reason if the transfer is not allowed
    function _checkTransferRestriction(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal view virtual returns (bool allowed, string memory reason);
} 
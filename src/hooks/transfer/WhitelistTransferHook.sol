// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "./BaseTransferHook.sol";

/// @title WhitelistTransferHook
/// @notice Transfer hook that restricts transfers to whitelisted addresses
contract WhitelistTransferHook is BaseTransferHook {
    // Mapping of whitelisted addresses
    mapping(address => bool) public whitelisted;

    // Event for when addresses are added/removed from whitelist
    event WhitelistUpdated(address indexed account, bool whitelisted);

    constructor(address _auth) BaseTransferHook(_auth) {}

    /// @notice Add or remove addresses from the whitelist
    /// @param account The address to update
    /// @param _whitelisted Whether to whitelist or remove from whitelist
    function setWhitelisted(address account, bool _whitelisted) external onlyAdmin {
        whitelisted[account] = _whitelisted;
        emit WhitelistUpdated(account, _whitelisted);
    }

    /// @notice Batch add or remove addresses from the whitelist
    /// @param accounts Array of addresses to update
    /// @param _whitelisted Whether to whitelist or remove from whitelist
    function batchSetWhitelisted(address[] calldata accounts, bool _whitelisted) external onlyAdmin {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelisted[accounts[i]] = _whitelisted;
            emit WhitelistUpdated(accounts[i], _whitelisted);
        }
    }

    /// @notice Check if a transfer is allowed based on whitelist
    /// @param from The address tokens are being transferred from
    /// @param to The address tokens are being transferred to
    /// @param tokenId The ID of the token being transferred
    /// @param data Additional data passed to the hook (not used in this implementation)
    /// @return allowed Whether the transfer is allowed
    /// @return reason The reason if the transfer is not allowed
    function _checkTransferRestriction(address from, address to, uint256 tokenId, bytes memory data)
        internal
        view
        override
        returns (bool allowed, string memory reason)
    {
        // Allow transfers from whitelisted addresses to whitelisted addresses
        if (whitelisted[from] && whitelisted[to]) {
            return (true, "");
        }

        return (false, "Address not whitelisted");
    }
}

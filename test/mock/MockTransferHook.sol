// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../src/interfaces/ITransferRestrictionHook.sol";

contract MockTransferHook is ITransferRestrictionHook {
    bool private allowTransfers = true;
    bool private allowLegalTransfers = true;

    function setAllowTransfers(bool _allow) external {
        allowTransfers = _allow;
    }

    /// @dev Independent of setAllowTransfers, so a test can deny one event and permit the other.
    function setAllowLegalTransfers(bool _allow) external {
        allowLegalTransfers = _allow;
    }

    function checkTransferRestriction(
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external view returns (bool, string memory) {
        if (!allowTransfers) {
            return (false, "Transfers disabled in mock hook");
        }
        return (true, "");
    }

    function checkLegalTransferRestriction(
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external view returns (bool, string memory) {
        if (!allowLegalTransfers) {
            return (false, "Legal transfers disabled in mock hook");
        }
        return (true, "");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../src/interfaces/ITransferRestrictionHook.sol";

contract MockTransferHook is ITransferRestrictionHook {
    bool private allowTransfers = true;

    function setAllowTransfers(bool _allow) external {
        allowTransfers = _allow;
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
}

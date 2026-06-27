pragma solidity ^0.8.28;

import "./BaseTransferHook.sol";

/// @title VestingAllowlistHook
/// @notice Restriction hook for scrip that is escrowed in a vesting allocation.
///         A transfer is permitted when EITHER endpoint is a registered escrow party
///         (the granting authority, the MetaVesT controller, or a deployed allocation).
///         This lets scrip flow authority -> allocation (funding) and allocation -> recipient
///         (withdrawal of vested tokens) while blocking recipients from re-selling
///         still-restricted scrip to arbitrary third parties.
/// @dev OR semantics on the from/to addresses. CyberScrip passes the ERC20 transfer
///      `amount` in the third hook argument (named `tokenId` in the interface), so this
///      hook must key on addresses, not on that value. When the base hook is disabled it
///      short-circuits to "allowed", so the hook must stay enabled to restrict.
contract VestingAllowlistHook is BaseTransferHook {
    /// @notice Addresses whose involvement (as sender or recipient) permits a transfer.
    mapping(address => bool) public escrowParty;

    event EscrowPartyUpdated(address indexed account, bool allowed);

    function initialize(address _auth) external initializer {
        __BaseTransferHook_init(_auth);
    }

    function setEscrowParty(address account, bool allowed) external onlyAdmin {
        escrowParty[account] = allowed;
        emit EscrowPartyUpdated(account, allowed);
    }

    function batchSetEscrowParties(address[] calldata accounts, bool allowed) external onlyAdmin {
        for (uint256 i = 0; i < accounts.length; i++) {
            escrowParty[accounts[i]] = allowed;
            emit EscrowPartyUpdated(accounts[i], allowed);
        }
    }

    function _checkTransferRestriction(
        address from,
        address to,
        uint256,
        bytes memory
    ) internal view override returns (bool allowed, string memory reason) {
        if (escrowParty[from] || escrowParty[to]) {
            return (true, "");
        }
        return (false, "scrip locked: vesting escrow only");
    }
}

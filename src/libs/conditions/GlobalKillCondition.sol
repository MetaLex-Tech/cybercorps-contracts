// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "openzeppelin-contracts/interfaces/IERC165.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "./baseCondition.sol";
import "../auth.sol";
import "../../interfaces/ITransferRestrictionHook.sol";

/// @title GlobalKillCondition
/// @notice Platform-wide kill switch gating deal finalization and cert/scrip transfers.
/// @dev Any BorgAuth owner can raise their kill vote; the kill is active while any vote is raised.
/// Implements ICondition (for DealManager) and ITransferRestrictionHook (for CyberScrip / CyberCertPrinter).
contract GlobalKillCondition is BaseCondition, BorgAuthACL, ITransferRestrictionHook {
    event KillRaised(address indexed by);
    event KillLowered(address indexed by);

    mapping(address => bool) public killVotes;
    uint256 public killCount;

    constructor(address _auth) {
        initialize(_auth);
    }

    function initialize(address _auth) public initializer {
        __BorgAuthACL_init(_auth);
    }

    function raiseKill() external onlyOwner {
        if (!killVotes[msg.sender]) {
            killVotes[msg.sender] = true;
            killCount++;
            emit KillRaised(msg.sender);
        }
    }

    function lowerKill() external onlyOwner {
        if (killVotes[msg.sender]) {
            killVotes[msg.sender] = false;
            killCount--;
            emit KillLowered(msg.sender);
        }
    }

    function isKilled() public view returns (bool) {
        return killCount > 0;
    }

    function checkCondition(address, bytes4, bytes memory) public view override returns (bool) {
        return !isKilled();
    }

    function checkTransferRestriction(address, address, uint256, bytes memory)
        external
        view
        override
        returns (bool allowed, string memory reason)
    {
        if (isKilled()) return (false, "Global kill switch active");
        return (true, "");
    }
}

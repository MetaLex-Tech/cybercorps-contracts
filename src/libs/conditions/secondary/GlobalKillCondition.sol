// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "./SecondaryTradingConditionBase.sol";

/// @title  GlobalKillCondition - platform-wide finalization kill switch (closing condition)
/// @author MetaLeX Labs, Inc.
/// @notice Deployed once, platform-wide; the factory attaches it as a closing condition to every new
/// DealManager. Two admin slots — one MetaLeX, one Legion. Either admin can raise the kill flag
/// unilaterally; lowering requires two calls (one proposes, the other confirms). While raised,
/// checkCondition returns false, suspending finalization platform-wide. Raising mid-deal does not
/// unwind binding contracts; deals that expire while the kill is raised void per the standard expiry
/// path (performance excused, no breach).
/// @dev Deliberately not upgradeable and not BorgAuth-gated: the two-slot admin model IS the
/// governance surface (spec §15 open questions — max raise duration, key rotation, key-loss recovery,
/// tiered soft/hard kill — are future work).
contract GlobalKillCondition is SecondaryTradingConditionBase {
    error NotKillAdmin();
    error InvalidAdmin();
    error AlreadyKilled();
    error NotKilled();
    error NoLowerProposal();
    error ProposerCannotConfirm();

    event KillRaised(address indexed admin);
    event KillLowerProposed(address indexed admin);
    event KillLowerConfirmed(address indexed proposer, address indexed confirmer);
    event AdminRotated(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Admin slot A (MetaLeX)
    address public metalexAdmin;
    /// @notice Admin slot B (Legion)
    address public legionAdmin;

    /// @notice Kill flag: while high, finalization is blocked platform-wide
    bool public killed;
    /// @notice Admin who proposed lowering the raised flag; zero when no proposal is pending
    address public lowerProposer;

    modifier onlyKillAdmin() {
        if (msg.sender != metalexAdmin && msg.sender != legionAdmin) revert NotKillAdmin();
        _;
    }

    constructor(address _metalexAdmin, address _legionAdmin) {
        if (_metalexAdmin == address(0) || _legionAdmin == address(0)) revert InvalidAdmin();
        if (_metalexAdmin == _legionAdmin) revert InvalidAdmin();
        metalexAdmin = _metalexAdmin;
        legionAdmin = _legionAdmin;
    }

    /// @notice Raises the kill flag; either admin, unilaterally. Also cancels any pending lower proposal.
    function raiseKill() external onlyKillAdmin {
        if (killed) revert AlreadyKilled();
        killed = true;
        lowerProposer = address(0);
        emit KillRaised(msg.sender);
    }

    /// @notice First half of the two-call lowering: records the proposing admin
    function proposeLower() external onlyKillAdmin {
        if (!killed) revert NotKilled();
        lowerProposer = msg.sender;
        emit KillLowerProposed(msg.sender);
    }

    /// @notice Second half of the two-call lowering: the OTHER admin confirms and the flag drops
    function confirmLower() external onlyKillAdmin {
        if (!killed) revert NotKilled();
        address proposer = lowerProposer;
        if (proposer == address(0)) revert NoLowerProposal();
        if (msg.sender == proposer) revert ProposerCannotConfirm();
        killed = false;
        lowerProposer = address(0);
        emit KillLowerConfirmed(proposer, msg.sender);
    }

    /// @notice Each admin can rotate their own slot's key
    function rotateAdmin(address newAdmin) external onlyKillAdmin {
        if (newAdmin == address(0)) revert InvalidAdmin();
        if (newAdmin == metalexAdmin || newAdmin == legionAdmin) revert InvalidAdmin();
        if (msg.sender == metalexAdmin) {
            metalexAdmin = newAdmin;
        } else {
            legionAdmin = newAdmin;
        }
        emit AdminRotated(msg.sender, newAdmin);
    }

    /// @notice Blocks finalization while the kill flag is high. Reads live state, so a kill raised
    /// after an offer was posted (conditions are snapshotted onto offers) still bites at finalize.
    function checkCondition(IDealManager, bytes4, bytes32, bytes32) external view override returns (bool) {
        return !killed;
    }
}

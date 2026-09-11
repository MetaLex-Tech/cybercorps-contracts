// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "./SecondaryTradingConditionBase.sol";

/// @title  KillSwitchCondition - finalization kill switch (closing condition)
/// @author MetaLeX Labs, Inc.
/// @notice Emergency brake on settlement, held jointly by two independent admins (MetaLeX, Legion),
/// at two scopes: platform-wide, or a single settlement. Either admin can raise a brake alone (fast
/// response); lowering one takes both (no single key silently re-enables a trade). A brake holds
/// pending trades but does not unwind binding contracts — deals that expire while held void via the
/// standard expiry path, performance excused.
/// @dev Deliberately not upgradeable and not BorgAuth-gated: the two-admin model is the whole
/// governance surface (spec §15 open questions — max hold duration, key rotation, key-loss recovery,
/// tiered soft/hard kill — are future work).
contract KillSwitchCondition is SecondaryTradingConditionBase {
    error NotKillAdmin();
    error InvalidAdmin();
    error AlreadyKilled();
    error NotKilled();
    error NoLowerProposal();
    error ProposerCannotConfirm();
    error ProposerNotAdmin();

    event KillRaised(address indexed admin);
    event KillLowerProposed(address indexed admin);
    event KillLowerConfirmed(address indexed proposer, address indexed confirmer);
    event SettlementKillRaised(bytes32 indexed agreementId, address indexed admin);
    event SettlementKillLowerProposed(bytes32 indexed agreementId, address indexed admin);
    event SettlementKillLowerConfirmed(bytes32 indexed agreementId, address indexed proposer, address indexed confirmer);
    event AdminRotated(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Admin slot A (MetaLeX)
    address public metalexAdmin;
    /// @notice Admin slot B (Legion)
    address public legionAdmin;

    /// @notice Kill flag: while high, finalization is blocked platform-wide
    bool public killed;
    /// @notice Admin who proposed lowering the raised flag; zero when no proposal is pending
    address public lowerProposer;

    /// @notice Per-settlement kill flags: while high, finalization is blocked for that agreement only
    mapping(bytes32 => bool) public settlementKilled;
    /// @notice Admin who proposed lowering a settlement's flag; zero when no proposal is pending
    mapping(bytes32 => address) public settlementLowerProposer;

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

    /// @notice Raise the platform-wide brake; either admin, unilaterally.
    function raiseKill() external onlyKillAdmin {
        if (killed) revert AlreadyKilled();
        killed = true;
        lowerProposer = address(0);
        emit KillRaised(msg.sender);
    }

    /// @notice Propose lowering the platform-wide brake (first of two admin calls).
    function proposeLower() external onlyKillAdmin {
        if (!killed) revert NotKilled();
        lowerProposer = msg.sender;
        emit KillLowerProposed(msg.sender);
    }

    /// @notice Confirm lowering the platform-wide brake; the other admin drops it.
    function confirmLower() external onlyKillAdmin {
        if (!killed) revert NotKilled();
        address proposer = lowerProposer;
        _checkProposal(proposer);
        killed = false;
        lowerProposer = address(0);
        emit KillLowerConfirmed(proposer, msg.sender);
    }

    /// @notice Raise a single settlement's brake; either admin, unilaterally.
    function raiseSettlementKill(bytes32 agreementId) external onlyKillAdmin {
        if (settlementKilled[agreementId]) revert AlreadyKilled();
        settlementKilled[agreementId] = true;
        settlementLowerProposer[agreementId] = address(0);
        emit SettlementKillRaised(agreementId, msg.sender);
    }

    /// @notice Propose lowering a settlement's brake (first of two admin calls).
    function proposeSettlementLower(bytes32 agreementId) external onlyKillAdmin {
        if (!settlementKilled[agreementId]) revert NotKilled();
        settlementLowerProposer[agreementId] = msg.sender;
        emit SettlementKillLowerProposed(agreementId, msg.sender);
    }

    /// @notice Confirm lowering a settlement's brake; the other admin drops it.
    function confirmSettlementLower(bytes32 agreementId) external onlyKillAdmin {
        if (!settlementKilled[agreementId]) revert NotKilled();
        address proposer = settlementLowerProposer[agreementId];
        _checkProposal(proposer);
        settlementKilled[agreementId] = false;
        settlementLowerProposer[agreementId] = address(0);
        emit SettlementKillLowerConfirmed(agreementId, proposer, msg.sender);
    }

    /// @notice Each admin can rotate their own slot's key. A rotation makes a pending lower proposal
    /// from the old key unusable.
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

    /// @dev Checks a pending lower proposal before a confirm. The proposer must still hold an admin
    /// slot. The confirmer must be the other key. A rotation does not clear a pending proposal. Without
    /// the admin check, one admin can propose, rotate its own slot, then confirm with the new key.
    function _checkProposal(address proposer) private view {
        if (proposer == address(0)) revert NoLowerProposal();
        if (proposer != metalexAdmin && proposer != legionAdmin) revert ProposerNotAdmin();
        if (msg.sender == proposer) revert ProposerCannotConfirm();
    }

    /// @notice Blocks finalization while the platform-wide or this settlement's brake is raised.
    function checkCondition(IDealManager, bytes4, bytes32, bytes32 agreementId) external view override returns (bool) {
        return !killed && !settlementKilled[agreementId];
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./SecondaryTradingConditionBase.sol";
import "../../auth.sol";

/// @title  GPLPApprovalCondition - per-deal GP/LP manual approval gate
/// @author MetaLeX Labs, Inc.
/// @notice Generalizes IssuerApprovalRecertificationCondition to per-deal approval on the secondary
/// path. Optional per-SPV; attached only where governing documents impose manual approval or LP-level
/// consents (spousal consent, co-investor consents). Each DealManager's owner designates an authorized
/// approver (GP, managing member, or delegated compliance officer); the condition fails until the
/// approver has signed off on the specific deal — either the offerId (pre-approving every settlement of
/// the offer) or a specific settlementAgreementId. Silent at posting (per-deal approval only exists
/// once a settlement is in flight).
contract GPLPApprovalCondition is SecondaryTradingConditionBase, UUPSUpgradeable, BorgAuthACL {
    error InvalidDealManager();
    error InvalidDealId();
    error NotApprover();

    event ApproverUpdated(address indexed dealManager, address approver);
    event DealApprovalUpdated(address indexed dealManager, bytes32 indexed dealId, bool approved, address indexed approver);

    /// @notice Per-DealManager authorized approver
    mapping(address => address) public approvers;
    // dealManager => dealId (offerId or settlementAgreementId) => approved
    mapping(address => mapping(bytes32 => bool)) public dealApprovals;

    uint256[48] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _auth) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    /// @notice Designates the authorized approver for a DealManager; only that DealManager's BorgAuth owner
    function setApprover(address dealManager, address approver) external {
        if (dealManager == address(0)) revert InvalidDealManager();
        _requireAuthOwner(dealManager);
        approvers[dealManager] = approver;
        emit ApproverUpdated(dealManager, approver);
    }

    /// @notice Records (or withdraws) the approver's sign-off on a specific deal id. Withdrawal bites at
    /// finalize too, since threshold conditions are re-run there.
    function setDealApproval(address dealManager, bytes32 dealId, bool approved) external {
        if (dealManager == address(0)) revert InvalidDealManager();
        if (dealId == bytes32(0)) revert InvalidDealId();
        if (msg.sender != approvers[dealManager]) revert NotApprover();
        dealApprovals[dealManager][dealId] = approved;
        emit DealApprovalUpdated(dealManager, dealId, approved, msg.sender);
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32 offerId,
        bytes32 agreementId
    ) external view override returns (bool) {
        // Per-deal approval: nothing to verify until a settlement exists
        if (agreementId == bytes32(0)) return true;

        address dm = address(dealManager);
        return dealApprovals[dm][offerId] || dealApprovals[dm][agreementId];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "./SecondaryTradingConditionBase.sol";
import {SecondaryEscrow} from "../../../interfaces/ISecondaryTradeStorage.sol";

/// @title  TimeSettlementPeriodCondition - minimum delay between acceptance and finalization (closing condition)
/// @author MetaLeX Labs, Inc.
/// @notice Deployed once, platform-wide; attached by default to every DealManager, with per-DealManager
/// delay overrides. Structural defense against key-theft dumps: the enforced window between acceptance
/// and finalization is the intervention window for the Compromised Credential Transfer voidness
/// provision and the kill switch. It is also the trigger the keeper waits on before auto-finalizing.
/// Default delay is 86,400 seconds (24h) measured from acceptance (the unified pathway's start trigger —
/// under this architecture the buyer's deposit is atomic with acceptance, so acceptance and deposit
/// triggers coincide). Future QMS parameterization (Addendum E): a 45-day delay measured from the
/// offer's listing timestamp for QMS-mode SPVs — same contract, different per-DealManager delay.
/// @dev The acceptance timestamp is reconstructed as escrow.expiry - settlementWindow (acceptOffer
/// stamps expiry = acceptance + window). If the DealManager's settlement window is reconfigured while a
/// lot is in flight, the reconstruction shifts with it; owners should change the window only between
/// settlements. A DealManager's effective delay must stay below its settlement window or no lot can
/// ever finalize.
contract TimeSettlementPeriodCondition is SecondaryTradingConditionBase {
    error InvalidDealManager();
    error NotDealManagerOwner();

    event DelayOverrideUpdated(address indexed dealManager, uint256 delay);

    /// @notice Default minimum settlement delay: 24 hours from acceptance
    uint256 public constant DEFAULT_DELAY = 86_400;

    /// @notice Per-DealManager delay override in seconds; 0 = DEFAULT_DELAY
    mapping(address => uint256) public delayOverrides;

    /// @notice Sets a DealManager's delay override (0 restores the default); only that DealManager's
    /// BorgAuth owner
    function setDelayOverride(address dealManager, uint256 delay) external {
        if (dealManager == address(0)) revert InvalidDealManager();
        _requireAuthOwner(dealManager);
        delayOverrides[dealManager] = delay;
        emit DelayOverrideUpdated(dealManager, delay);
    }

    /// @notice Effective delay for a DealManager
    function delayFor(address dealManager) public view returns (uint256) {
        uint256 delay = delayOverrides[dealManager];
        return delay == 0 ? DEFAULT_DELAY : delay;
    }

    /// @notice Earliest timestamp at which a settlement lot may finalize (what a keeper waits on)
    function finalizableAt(IDealManager dealManager, bytes32 agreementId) public view returns (uint256) {
        SecondaryEscrow memory escrow = dealManager.getSecondaryEscrow(agreementId);
        uint256 acceptedAt = escrow.expiry - dealManager.getSettlementWindow();
        return acceptedAt + delayFor(address(dealManager));
    }

    function checkCondition(
        IDealManager dealManager,
        bytes4,
        bytes32,
        bytes32 agreementId
    ) external view override returns (bool) {
        // Closing conditions are only evaluated at finalize, but stay silent for a missing settlement id
        // in case a flow composes conditions independently
        if (agreementId == bytes32(0)) return true;
        return block.timestamp >= finalizableAt(dealManager, agreementId);
    }
}

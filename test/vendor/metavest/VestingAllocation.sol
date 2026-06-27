// SPDX-License-Identifier: AGPL-3.0-only
import "./BaseAllocation.sol";
import {MetaVestType} from "./lib/MetaVestDealLib.sol";

pragma solidity ^0.8.24;

contract VestingAllocation is BaseAllocation {

    /// @notice constructor for VestingAllocation
    /// @param _grantee address of the grantee
    /// @param _recipient address of the fund recipient
    /// @param _controller address of the controller
    /// @param _allocation Allocation struct containing token contract
    /// @param _milestones array of Milestone structs with conditions and awards
    constructor (
        address _grantee,
        address _recipient,
        address _controller,
        Allocation memory _allocation,
        Milestone[] memory _milestones
    ) BaseAllocation(
        _grantee,
        _recipient,
        _controller
    ) {
        // perform input validation
        if (_allocation.tokenContract == address(0)) revert MetaVesT_ZeroAddress();
        if (_allocation.tokenStreamTotal == 0) revert MetaVesT_ZeroAmount();
        if (_allocation.vestingRate >  1000*1e18 || _allocation.unlockRate > 1000*1e18) revert MetaVesT_RateTooHigh();
        if (_allocation.vestingRate <  100 || _allocation.unlockRate < 100) revert MetaVesT_RateTooLow();

        // set vesting allocation variables
        allocation = _allocation;

        // manually copy milestones
        for (uint256 i; i < _milestones.length; ++i) {
            milestones.push(_milestones[i]);
        }
    }

    /// @notice returns the vesting type
    /// @return MetaVestType
    function getVestingType() external pure override returns (MetaVestType) {
        return MetaVestType.Vesting;
    }

    /// @notice returns the governing power of the VestingAllocation
    /// @return governingPower - the governing power of the VestingAllocation based on the governance setting
    function getGoverningPower() external view override returns (uint256 governingPower) {
        if(govType==GovType.all) {
            uint256 totalMilestoneAward = 0;
            for(uint256 i; i < milestones.length; ++i) {
                    totalMilestoneAward += milestones[i].milestoneAward;
            }
            governingPower = (allocation.tokenStreamTotal + totalMilestoneAward) - tokensWithdrawn;
        } else if(govType==GovType.vested) {
            uint256 amount = getVestedTokenAmount();
            governingPower = (amount > tokensWithdrawn)
                ? amount - tokensWithdrawn
                : 0;
        } else {
            uint256 amount = _min(getVestedTokenAmount(), getUnlockedTokenAmount());
            governingPower = (amount > tokensWithdrawn)
                ? amount - tokensWithdrawn
                : 0;
        }
        
        return governingPower;
    }

    /// @notice unused for VestingAllocation
    /// @dev onlyController -- must be called from the metavest controller
    /// @param _shortStopTime - the new short stop time
    function updateStopTimes(uint48 _shortStopTime) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        revert MetaVesT_ConditionNotSatisfied();
    }

    /// @notice terminates the VestingAllocation and transfers any remaining tokens to the authority
    /// @dev onlyController -- must be called from the metavest controller
    function terminate() external override onlyController nonReentrant {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        uint256 tokensToRecover = 0;
        uint256 milestonesAllocation = 0;
        for (uint256 i; i < milestones.length; ++i) {
                milestonesAllocation += milestones[i].milestoneAward;
        }
        tokensToRecover = allocation.tokenStreamTotal + milestonesAllocation - getVestedTokenAmount();
        if(tokensToRecover>IERC20M(allocation.tokenContract).balanceOf(address(this)))
            tokensToRecover = IERC20M(allocation.tokenContract).balanceOf(address(this));
        terminationTime = block.timestamp;
        safeTransfer(allocation.tokenContract, getAuthority(), tokensToRecover);
        terminated = true;
        emit MetaVesT_Terminated(grantee, tokensToRecover);
    }

    /// @notice returns the amount of tokens that are vested
    /// @return _tokensVested - the amount of tokens that are vested in decimals of the vesting token
    function getVestedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.vestingStartTime)
            return 0;
        uint256 _timeElapsedSinceVest = block.timestamp - allocation.vestingStartTime;
        if(terminated)
            _timeElapsedSinceVest = terminationTime - allocation.vestingStartTime;

           uint256 _tokensVested = (_timeElapsedSinceVest * allocation.vestingRate) + allocation.vestingCliffCredit;

            if(_tokensVested>allocation.tokenStreamTotal) 
                _tokensVested = allocation.tokenStreamTotal;
        return _tokensVested += milestoneAwardTotal;
    }

    /// @notice returns the amount of tokens that are unlocked
    /// @return _tokensUnlocked - the amount of tokens that are unlocked in decimals of the vesting token
    function getUnlockedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.unlockStartTime)
            return 0;
        uint256 _timeElapsedSinceUnlock = block.timestamp - allocation.unlockStartTime;
        uint256 _tokensUnlocked = (_timeElapsedSinceUnlock * allocation.unlockRate) + allocation.unlockingCliffCredit;

        if(_tokensUnlocked>allocation.tokenStreamTotal + milestoneAwardTotal) 
            _tokensUnlocked = allocation.tokenStreamTotal + milestoneAwardTotal;

        return _tokensUnlocked += milestoneUnlockedTotal;
    }

    /// @notice returns the amount of tokens that are withdrawable
    /// @return _tokensWithdrawable - the amount of tokens that are withdrawable in decimals of the vesting token
    function getAmountWithdrawable() public view override returns (uint256) {
        uint256 _tokensVested = getVestedTokenAmount();
        uint256 _tokensUnlocked = getUnlockedTokenAmount();
        uint256 withdrawableAmount = _min(_tokensVested, _tokensUnlocked);
        if(withdrawableAmount>tokensWithdrawn)
            return withdrawableAmount - tokensWithdrawn;
        else
            return 0;
        
    }

}

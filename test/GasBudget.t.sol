// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {GasBudget} from "./libs/GasBudget.sol";
import {Test} from "forge-std/Test.sol";

contract SlotWriter {
    mapping(uint256 => uint256) internal slots;

    function fill(uint256 count) external {
        for (uint256 i = 1; i <= count; i++) {
            slots[i] = i;
        }
    }
}

/// @notice The gas guards trust two readings: `gasleft()` includes state gas and `lastFrameGas` does not.
/// These tests fail if a Forge or spec change breaks either reading.
/// forge-config: default.isolate = true
contract GasBudgetTest is Test {
    /// EIP-8037 state gas for one new storage slot: 64 state bytes at 1,530 gas each.
    uint256 internal constant STATE_GAS_PER_NEW_SLOT = 97_920;
    /// Gas that the call itself costs outside the callee, for example the cold account access.
    uint256 internal constant CALL_OVERHEAD_MAX = 10_000;

    function test_totalMinusExecutionIsTheStateGasOfNewSlots() public {
        SlotWriter writer = new SlotWriter();
        uint256 count = 10;

        uint256 gasStart = gasleft();
        writer.fill(count);
        uint256 total = gasStart - gasleft();
        uint256 execution = GasBudget.lastExecutionGas();

        assertApproxEqAbs(total - execution, count * STATE_GAS_PER_NEW_SLOT, CALL_OVERHEAD_MAX);
    }
}

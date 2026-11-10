// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

interface IFrameGas {
    function lastFrameGas() external view returns (Vm.Gas memory);
}

/// @title  GasBudget - the gas limits one transaction must fit under Glamsterdam
/// @notice EIP-8037 splits gas in two. Execution gas has the EIP-7825 cap. State gas (new slots, accounts and
/// code) is outside that cap, but the whole transaction must still fit the block gas limit.
/// @dev Call `check` right after the measured call. The caller gives the total from two `gasleft()` readings
/// around that call. Forge charges state gas from `gasleft()`, and `lastFrameGas` reports execution gas only.
/// Run the caller with `isolate = true`. Otherwise slots that the same test created and the call clears give
/// their state gas back, and the total reads too low.
library GasBudget {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// EIP-7825 cap on the execution gas of one transaction.
    uint256 internal constant EXECUTION_GAS_LIMIT = 16_777_216;
    /// Ethereum block gas limit we expect after Glamsterdam, the same as Sepolia now.
    uint256 internal constant TX_GAS_LIMIT = 200_000_000;

    uint256 internal constant EXECUTION_GAS_LIMIT_90_PCT = EXECUTION_GAS_LIMIT * 9 / 10;
    uint256 internal constant TX_GAS_LIMIT_90_PCT = TX_GAS_LIMIT * 9 / 10;

    /// @return execution Execution gas of the last call.
    function lastExecutionGas() internal view returns (uint256 execution) {
        execution = IFrameGas(address(VM)).lastFrameGas().gasTotalUsed;
    }

    /// @notice Logs and checks the last call against both limits.
    /// @param step Label for the logs and failure messages.
    /// @param total Gas from two `gasleft()` readings around the last call.
    function check(string memory step, uint256 total) internal view {
        uint256 execution = lastExecutionGas();
        console2.log(step, total);
        console2.log(string.concat(step, " execution"), execution);
        require(
            execution <= EXECUTION_GAS_LIMIT_90_PCT,
            string.concat(
                step,
                " execution gas exceeds 90% of the EIP-7825 cap: ",
                VM.toString(execution),
                " > ",
                VM.toString(EXECUTION_GAS_LIMIT_90_PCT)
            )
        );
        require(
            total <= TX_GAS_LIMIT_90_PCT,
            string.concat(
                step,
                " total gas exceeds 90% of the block gas limit: ",
                VM.toString(total),
                " > ",
                VM.toString(TX_GAS_LIMIT_90_PCT)
            )
        );
    }
}

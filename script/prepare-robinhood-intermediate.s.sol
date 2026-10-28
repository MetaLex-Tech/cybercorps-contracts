// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BootstrapRobinhoodScript} from "./bootstrap-robinhood.s.sol";
import {console2} from "forge-std/Script.sol";

/// @notice Key-free rehearsal only. Invoke --sig "prepare()" without --broadcast.
/// @dev Uses the pinned historical sender; local Safe impersonation does not establish signer control.
contract PrepareRobinhoodIntermediateScript is BootstrapRobinhoodScript {
    function prepare() external {
        Config memory config = Config({
            stable: vm.envAddress("ROBINHOOD_STABLE"),
            feeRecipient: vm.envAddress("ROBINHOOD_FEE_RECIPIENT"),
            primaryFeeBps: vm.envUint("ROBINHOOD_PRIMARY_FEE_BPS"),
            freshDeployment: vm.envBool("ROBINHOOD_FRESH_DEPLOYMENT")
        });
        runWithArgs(HISTORICAL_OWNER, config);
        simulateSafeBatch(config);
        string memory path = string.concat(
            "script/res/gnosis-batch-bootstrap-robinhood-", vm.toString(block.chainid), ".simulation.json"
        );
        vm.writeFile(path, safeBatchJson());
        console2.log("SIMULATION ONLY - do not import into Safe:", path);
    }
}

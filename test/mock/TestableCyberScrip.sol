// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../src/CyberScrip.sol";

contract TestableCyberScrip is CyberScrip {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}



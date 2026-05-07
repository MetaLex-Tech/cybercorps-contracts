// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../../src/CyberScrip.sol";

contract TestableCyberScrip is CyberScrip {
    function unrestrictedMint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}



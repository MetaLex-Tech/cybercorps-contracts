// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IRoundManager} from "../src/interfaces/IRoundManager.sol";

contract ManualAllocationForkTest is Test {
    // Contract addresses provided by user
    address public constant CALLER = 0x3B12Bfc36931155A8Dc26c6636D0C888E9a3F55C;
    address public constant ROUND_MANAGER = 0x0612811285D9797E1E7fFcee2d3191C7154552f8;
    
    // Agreement ID provided by user
    bytes32 public constant AGREEMENT_ID = 0x72F1689D3F127129857D1867C30ADAEDF4428527510FD4EA98221FA6B4BA132F;

    function setUp() public {
        vm.createSelectFork("base_sepolia");
    }

    function test_manualAllocate() public {
        // Prank the authorized caller
        vm.startPrank(CALLER);

        // Call allocate(agreementId, amount) on the RoundManager
        // Note: This expects the contract to be deployed at the address on the network being tested (fork or mainnet)
        uint256 tokenId = IRoundManager(ROUND_MANAGER).allocate(AGREEMENT_ID, 1000000000000000000);

        console.log("Allocation successful. Token ID:", tokenId);

        vm.stopPrank();
    }
}


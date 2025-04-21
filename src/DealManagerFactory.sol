//create a factory for deploying a deal manager
pragma solidity 0.8.28;

import "./DealManager.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract DealManagerFactory {
    error InvalidSalt();
    error DeploymentFailed();

    function deployDealManager(bytes32 salt) public returns (address) {
        if (salt == bytes32(0)) revert InvalidSalt();

        // Get the creation bytecode for DealManager
        bytes memory bytecode = type(DealManager).creationCode;
        
        // Deploy using CREATE2
        address dealManager = Create2.deploy(0, salt, bytecode);
        
        if(dealManager == address(0)) revert DeploymentFailed();
        
        return dealManager;
    }

    // Helper function to compute the address before deployment
    function computeDealManagerAddress(bytes32 salt) public view returns (address) {
        bytes memory bytecode = type(DealManager).creationCode;
        return Create2.computeAddress(salt, keccak256(bytecode));
    }
}


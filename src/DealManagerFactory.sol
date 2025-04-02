//create a factory for deploying a deal manager
pragma solidity 0.8.28;

import "./DealManager.sol";

contract DealManagerFactory {
    function deployDealManager() public returns (address) {
        DealManager dealManager = new DealManager();
        return address(dealManager);
    }
}

pragma solidity 0.8.28;

interface IDealManagerFactory {
    function deployDealManager() external returns (address);
}

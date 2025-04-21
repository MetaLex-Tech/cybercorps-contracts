pragma solidity 0.8.28;

interface IDealManagerFactory {
    function deployDealManager(bytes32 salt) external returns (address);
    function computeDealManagerAddress(bytes32 salt) external view returns (address);
}

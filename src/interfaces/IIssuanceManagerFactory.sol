//create an interface to deploy issuance managers
pragma solidity 0.8.28;

interface IIssuanceManagerFactory {
    function deployIssuanceManager(bytes32 salt) external returns (address issuanceManagerAddress);
}

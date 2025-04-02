//create a factory to deploy issuance managers
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./IssuanceManager.sol";

contract IssuanceManagerFactory {
    address public issuanceManagerImplementation;

    constructor(address _issuanceManagerImplementation) {
        issuanceManagerImplementation = _issuanceManagerImplementation;
    }

    function deployIssuanceManager(bytes32 salt) public returns (address issuanceManagerAddress) {        // Deploy IssuanceManager with CREATE2
        bytes memory issuanceManagerBytecode = type(IssuanceManager).creationCode;
        bytes32 issuanceManagerSalt = keccak256(abi.encodePacked("issuanceManager", salt));
        issuanceManagerAddress = Create2.deploy(0, issuanceManagerSalt, issuanceManagerBytecode);
    }
}

//factory for deploying a single cybercorp
pragma solidity 0.8.28;

import "./CyberCorp.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract CyberCorpSingleFactory {

    constructor() {
    }   

    function deployCyberCorpSingle(
        bytes32 salt,
        address authAddress,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend
    ) public returns (address cyberCorpAddress) {
            // Deploy CyberCorp with CREATE2
            bytes memory cyberCorpBytecode = abi.encodePacked(
                type(CyberCorp).creationCode,
            abi.encode(
                authAddress,
                companyName,
                companyJurisdiction,
                companyContactDetails,
                defaultDisputeResolution,
                defaultLegend
            )
        );
        bytes32 cyberCorpSalt = keccak256(abi.encodePacked("cyberCorp", salt));
        cyberCorpAddress = Create2.deploy(0, cyberCorpSalt, cyberCorpBytecode);
    }

}
    
    

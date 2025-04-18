
pragma solidity 0.8.28;

import "../CyberCorpConstants.sol";

interface ICyberCorpSingleFactory {
    function deployCyberCorpSingle(
        bytes32 salt,
        address authAddress,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend,
        address issuanceManager,
        address _companyPayable,
        CompanyOfficer memory _officer
    ) external returns (address cyberCorpAddress);
}   




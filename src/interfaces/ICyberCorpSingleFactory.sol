
pragma solidity 0.8.28;

interface ICyberCorpSingleFactory {
    function deployCyberCorpSingle(
        bytes32 salt,
        address authAddress,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend
    ) external returns (address cyberCorpAddress);
}   


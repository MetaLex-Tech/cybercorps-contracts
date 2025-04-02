pragma solidity 0.8.28;

interface ICyberCorp {
    function initialize(address _issuanceManager, address _auth) external;
    function cyberCORPName() external view returns (string memory);
    function cyberCORPJurisdiction() external view returns (string memory);
    function companyContactDetails() external view returns (string memory);
    function defaultDisputeResolution() external view returns (string memory);
    function defaultLegend() external view returns (string memory);
    function companyPayable() external view returns (address);
}

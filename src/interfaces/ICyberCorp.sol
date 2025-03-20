pragma solidity 0.8.28;

interface ICyberCorp {
    function initialize(address _issuanceManager, address _auth) external;
    function companyName() external view returns (string memory);
    function companyJurisdiction() external view returns (string memory);
    function companyContactDetails() external view returns (string memory);
    function defaultDisputeResolution() external view returns (string memory);
    function defaultLegend() external view returns (string memory);
    function companyPayable() external view returns (address);
}


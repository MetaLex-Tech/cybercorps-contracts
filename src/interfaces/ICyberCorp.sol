pragma solidity 0.8.28;

interface ICyberCorp {
    function initialize(address _issuanceManager, address _auth) external;
    function cyberCORPName() external view returns (string memory);
    function cyberCORPJurisdiction() external view returns (string memory);
    function cyberCORPContactDetails() external view returns (string memory);
    function defaultDisputeResolution() external view returns (string memory);
    function defaultLegend() external view returns (string memory);
    function companyPayable() external view returns (address);
    function companyOfficers() external view returns (address[] memory);
    function cyberCORPType() external view returns (string memory);
    
}


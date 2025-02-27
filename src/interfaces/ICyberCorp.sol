pragma solidity 0.8.28;

interface ICyberCorp {
    function companyName() external view returns (string memory);
    function companyJurisdiction() external view returns (string memory);
    function companyContactDetails() external view returns (string memory);
    function defaultDisputeResolution() external view returns (string memory);
    function defaultLegend() external view returns (string memory);
}

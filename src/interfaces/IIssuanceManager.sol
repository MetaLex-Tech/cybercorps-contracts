pragma solidity 0.8.28;

//Adapter interface for custom auth roles. Allows extensibility for different auth protocols i.e. hats.
interface IIssuanceManager {
    function convert(uint256 tokenId, address convertTo, uint256 stockAmount) external;
    function upgradeImplementation(address _newImplementation) external;
    function getBeaconImplementation() external view returns (address);
    function setCompanyDetails(string calldata _companyName, string calldata _companyJurisdiction, string calldata _companyContactDetails, string calldata _defaultDisputeResolution, string calldata _defaultLegend) external;
    function companyName() external view returns (string memory);
}
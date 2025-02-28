pragma solidity 0.8.28;

import "./libs/auth.sol";
import "./IssuanceManager.sol";

contract CyberCorp is BorgAuthACL {

    // Company details
    string public companyName;
    string public companyJurisdiction;
    string public companyContactDetails;
    string public defaultDisputeResolution;
    string public defaultLegend;
    address public issuanceManager;

    constructor(BorgAuth _auth, string memory _companyName, string memory _companyJurisdiction, string memory _companyContactDetails, string memory _defaultDisputeResolution, string memory _defaultLegend) BorgAuthACL(_auth) {
        companyName = _companyName;
        companyJurisdiction = _companyJurisdiction;
        companyContactDetails = _companyContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;
    }

    function setCompanyDetails(string memory _companyName, string memory _companyJurisdiction, string memory _companyContactDetails, string memory _defaultDisputeResolution, string memory _defaultLegend) external onlyOwner() {
        companyName = _companyName;
        companyJurisdiction = _companyJurisdiction;
        companyContactDetails = _companyContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;
    }

    function createIssuanceManager(address _optionalAuth) external onlyOwner() {
        if (_optionalAuth == address(0)) {
            issuanceManager = address(new IssuanceManager(address(this), AUTH));
        } else {
            issuanceManager = address(new IssuanceManager(address(this), BorgAuth(_optionalAuth)));
        }
    }

    function isCompanyOfficer(address _address) external view returns (bool) {
        return (AUTH.userRoles(_address) >= AUTH.OWNER_ROLE());
    }

}
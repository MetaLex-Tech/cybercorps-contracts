pragma solidity 0.8.28;

import "./libs/auth.sol";
import "./IssuanceManager.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract CyberCorp is BorgAuthACL {

    // cyberCORP details
    string public cyberCORPName; //this should be the legal name of the entity, including any designation such as "Inc." or "LLC" etc. 
    string public cyberCORPType; //this should be the legal entity type, for example, "corporation" or "limited liability company" 
    string public cyberCORPJurisdiction; //this should be the jurisdiction of incorporation of the entity, e.g. "Delaware"
    string public cyberCORPContactDetails; 
    string public defaultDisputeResolution;
    string public defaultLegend; //default legend (relating to transferability restrictions etc.) for NFT certs 
    address public issuanceManager;

    UpgradeableBeacon public beacon;
    address public cyberCertPrinterImplementation;

    constructor(BorgAuth _auth, string memory _cyberCORPName, string memory _cyberCORPJurisdiction, string memory _cyberCORPContactDetails, string memory _defaultDisputeResolution, string memory _defaultLegend) {
        cyberCORPName = _cyberCORPName;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;
    }

    function initialize(address _issuanceManager, address _auth) external onlyOwner() {
        issuanceManager = _issuanceManager;
          __BorgAuthACL_init(_auth);
    }

    function setcyberCORPDetails(string memory _cyberCORPName, string memory _cyberCORPJurisdiction, string memory _cyberCORPContactDetails, string memory _defaultDisputeResolution, string memory _defaultLegend) external onlyOwner() {
        cyberCORPName = _cyberCORPName;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;
    }

    function createIssuanceManager(address _optionalAuth) external onlyOwner() {
            issuanceManager = address(new IssuanceManager());
            if(_optionalAuth != address(0)) {
                IssuanceManager(issuanceManager).initialize(address(AUTH), address(this), cyberCertPrinterImplementation);
            } else {
                IssuanceManager(issuanceManager).initialize(_optionalAuth, address(this), cyberCertPrinterImplementation);
            }
    }

    function iscyberCORPOfficer(address _address) external view returns (bool) {
        return (AUTH.userRoles(_address) >= AUTH.OWNER_ROLE());
    }

    function _getBytecode() private view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(sourceCodeBytes, abi.encode(beacon, ""));
    }

}

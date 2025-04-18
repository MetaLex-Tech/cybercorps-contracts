// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.0;

import "./libs/auth.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./interfaces/IIssuanceManager.sol";

contract CyberCorp is Initializable, UUPSUpgradeable, BorgAuthACL {
    // cyberCORP details
    string public cyberCORPName; //this should be the legal name of the entity, including any designation such as "Inc." or "LLC" etc. 
    string public cyberCORPType; //this should be the legal entity type, for example, "corporation" or "limited liability company" 
    string public cyberCORPJurisdiction; //this should be the jurisdiction of incorporation of the entity, e.g. "Delaware"
    string public cyberCORPContactDetails; 
    string public defaultDisputeResolution;
    string public defaultLegend; //default legend (relating to transferability restrictions etc.) for NFT certs 
    address public issuanceManager;
    address public companyPayable;

    CompanyOfficer[] public companyOfficers;

    UpgradeableBeacon public beacon;
    address public cyberCertPrinterImplementation;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    }

    function initialize(
        address _auth,
        string memory _cyberCORPName,
        string memory _cyberCORPJurisdiction,
        string memory _cyberCORPContactDetails,
        string memory _defaultDisputeResolution,
        string memory _defaultLegend,
        address _issuanceManager,
        address _companyPayable,
        CompanyOfficer memory _officer
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        
        cyberCORPName = _cyberCORPName;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;
        issuanceManager = _issuanceManager;
        companyPayable = _companyPayable;
        companyOfficers.push(_officer);
    }

    function setcyberCORPDetails(
        string memory _cyberCORPName,
        string memory _cyberCORPJurisdiction,
        string memory _cyberCORPContactDetails,
        string memory _defaultDisputeResolution,
        string memory _defaultLegend
    ) external onlyOwner() {
        cyberCORPName = _cyberCORPName;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;
    }

    function setIssuanceManager(address _issuanceManager) external onlyOwner() {
        issuanceManager = _issuanceManager;
    }

    function iscyberCORPOfficer(address _address) external view returns (bool) {
        return (AUTH.userRoles(_address) >= AUTH.OWNER_ROLE());
    }

    function _getBytecode() private view returns (bytes memory bytecode) {
        bytes memory sourceCodeBytes = type(BeaconProxy).creationCode;
        bytecode = abi.encodePacked(sourceCodeBytes, abi.encode(beacon, ""));
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

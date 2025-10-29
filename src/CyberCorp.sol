/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
o88o     o8888o                                                                                       
                                                                                                      
                                                                                                      
                                                                                                      
ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
`88.       .888'             .o8             `888'                   `8888    d8'                     
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                      
                                                                                                      
                                                                                                      
  .oooooo.                .o8                            .oooooo.                                     
 d8P'  `Y8b              "888                           d8P'  `Y8b                                    
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
             .o..P'                                                                     888           
             `Y8P'                                                                     o888o          
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system, 
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import "./libs/auth.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./storage/CyberCorpStorage.sol";

/// @title CyberCorp
/// @notice Main contract representing a corporation's on-chain presence and management
/// @dev Implements UUPS upgradeable pattern and BorgAuth access control
contract CyberCorp is Initializable, BorgAuthACL, UUPSUpgradeable {
    using CyberCorpStorage for CyberCorpStorage.StorageData;

    string public constant DEPLOY_VERSION = "1"; // For version-tracking on all deployment and future upgrades

    event CyberCORPDetailsUpdated(string cyberCORPName, string cyberCORPType, string cyberCORPJurisdiction, string cyberCORPContactDetails, string defaultDisputeResolution);
    event OfficerAdded(address indexed officer, uint256 index);
    event OfficerRemoved(address indexed officer, uint256 index);
    event CompanyPayableUpdated(address indexed companyPayable, address indexed oldCompanyPayable);

    error NotRefImplementation();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the CyberCorp contract with essential details
    /// @param _auth Address of the BorgAuth ACL contract
    /// @param _cyberCORPName Legal name of the entity
    /// @param _cyberCORPType Legal type of the entity
    /// @param _cyberCORPJurisdiction Jurisdiction of incorporation
    /// @param _cyberCORPContactDetails Contact information
    /// @param _defaultDisputeResolution Default dispute resolution mechanism
    /// @param _issuanceManager Address of the issuance manager
    /// @param _companyPayable Address for receiving payments
    /// @param _officer Initial company officer details
    function initialize(
        address _auth,
        string memory _cyberCORPName,
        string memory _cyberCORPType,
        string memory _cyberCORPJurisdiction,
        string memory _cyberCORPContactDetails,
        string memory _defaultDisputeResolution,
        address _issuanceManager,
        address _companyPayable,
        CompanyOfficer memory _officer,
        address _upgradeFactory,
        address _roundManager
    ) public initializer {
        __BorgAuthACL_init(_auth);

        CyberCorpStorage.StorageData storage s = CyberCorpStorage.getStorageData();
        s.cyberCORPName = _cyberCORPName;
        s.cyberCORPType = _cyberCORPType;
        s.cyberCORPJurisdiction = _cyberCORPJurisdiction;
        s.cyberCORPContactDetails = _cyberCORPContactDetails;
        s.defaultDisputeResolution = _defaultDisputeResolution;
        s.issuanceManager = _issuanceManager;
        s.companyPayable = _companyPayable;
        s.companyOfficers.push(_officer);
        s.upgradeFactory = _upgradeFactory;
        s.roundManager = _roundManager;
    }

    /// @notice Updates the corporation's basic details
    /// @dev Only callable by owner
    /// @param _cyberCORPName New legal name
    /// @param _cyberCORPType New entity type
    /// @param _cyberCORPJurisdiction New jurisdiction
    /// @param _cyberCORPContactDetails New contact details
    /// @param _defaultDisputeResolution New dispute resolution mechanism
    function setcyberCORPDetails(
        string memory _cyberCORPName,
        string memory _cyberCORPType,
        string memory _cyberCORPJurisdiction,
        string memory _cyberCORPContactDetails,
        string memory _defaultDisputeResolution
    ) external onlyOwner() {
        CyberCorpStorage.StorageData storage s = CyberCorpStorage.getStorageData();
        s.cyberCORPName = _cyberCORPName;
        s.cyberCORPType = _cyberCORPType;
        s.cyberCORPJurisdiction = _cyberCORPJurisdiction;
        s.cyberCORPContactDetails = _cyberCORPContactDetails;
        s.defaultDisputeResolution = _defaultDisputeResolution;

        emit CyberCORPDetailsUpdated(s.cyberCORPName, s.cyberCORPType, s.cyberCORPJurisdiction, s.cyberCORPContactDetails, s.defaultDisputeResolution);
    }

    /// @notice Updates the issuance manager address
    /// @dev Only callable by owner
    /// @param _issuanceManager New issuance manager contract address
    function setIssuanceManager(address _issuanceManager) external onlyOwner() {
        CyberCorpStorage.getStorageData().issuanceManager = _issuanceManager;
    }

    /// @notice Updates the deal manager address
    /// @dev Only callable by owner
    /// @param _dealManager New deal manager contract address
    function setDealManager(address _dealManager) external onlyOwner() {
        CyberCorpStorage.getStorageData().dealManager = _dealManager;
    }

    /// @notice Updates the round manager address
    /// @dev Only callable by owner
    /// @param _roundManager New round manager contract address
    function setRoundManager(address _roundManager) external onlyOwner() {
        CyberCorpStorage.getStorageData().roundManager = _roundManager;
    }

    /// @notice Checks if an address belongs to a company officer
    /// @param _address Address to check
    /// @return bool True if the address belongs to an officer
    function isCyberCORPOfficer(address _address) external view returns (bool) {
        return (AUTH.userRoles(_address) >= AUTH.OWNER_ROLE());
    }

    /// @notice Adds a new officer to the company
    /// @dev Only callable by owner, sets officer role to 200
    /// @param _officer Officer details including address and role
    function addOfficer(CompanyOfficer memory _officer) external onlyOwner() {
        CyberCorpStorage.StorageData storage s = CyberCorpStorage.getStorageData();
        s.companyOfficers.push(_officer);
        AUTH.updateRole(_officer.eoa, 200);
        emit OfficerAdded(_officer.eoa, s.companyOfficers.length - 1);
    }

    /// @notice Removes an officer by their address
    /// @dev Only callable by owner, revokes officer role
    /// @param _address Address of the officer to remove
    function removeOfficer(address _address) external onlyOwner() {
        CyberCorpStorage.StorageData storage s = CyberCorpStorage.getStorageData();
        AUTH.updateRole(_address, 0);
        for (uint256 i = 0; i < s.companyOfficers.length; i++) {
            if (s.companyOfficers[i].eoa == _address) {
                s.companyOfficers[i] = s.companyOfficers[s.companyOfficers.length - 1];
                s.companyOfficers.pop();
                emit OfficerRemoved(_address, i);
                break;
            }
        }
    }

    /// @notice Removes an officer by their index in the officers array
    /// @dev Only callable by owner, revokes officer role
    /// @param _index Index of the officer to remove
    function removeOfficerAt(uint256 _index) external onlyOwner() {
        CyberCorpStorage.StorageData storage s = CyberCorpStorage.getStorageData();
        require(_index < s.companyOfficers.length, "Index out of bounds");
        address officerEOA = s.companyOfficers[_index].eoa;
        AUTH.updateRole(officerEOA, 0);
        s.companyOfficers[_index] = s.companyOfficers[s.companyOfficers.length - 1];
        s.companyOfficers.pop();
        emit OfficerRemoved(officerEOA, _index);
    }

    function setCompanyPayable(address _companyPayable) external onlyOwner() {
        CyberCorpStorage.StorageData storage s = CyberCorpStorage.getStorageData();
        address oldCompanyPayable = s.companyPayable;
        s.companyPayable = _companyPayable;
        emit CompanyPayableUpdated(s.companyPayable, oldCompanyPayable);
    }

    // ========================
    // Getter / Setter
    // ========================

    function cyberCORPName() external returns (string memory) {
        return CyberCorpStorage.getStorageData().cyberCORPName;
    }

    function cyberCORPType() external returns (string memory) {
        return CyberCorpStorage.getStorageData().cyberCORPType;
    }

    function cyberCORPJurisdiction() external returns (string memory) {
        return CyberCorpStorage.getStorageData().cyberCORPJurisdiction;
    }

    function cyberCORPContactDetails() external returns (string memory) {
        return CyberCorpStorage.getStorageData().cyberCORPContactDetails;
    }

    function defaultDisputeResolution() external returns (string memory) {
        return CyberCorpStorage.getStorageData().defaultDisputeResolution;
    }

    function companyPayable() external returns (address) {
        return CyberCorpStorage.getStorageData().companyPayable;
    }

    function issuanceManager() external returns (address) {
        return CyberCorpStorage.getStorageData().issuanceManager;
    }

    function dealManager() external returns (address) {
        return CyberCorpStorage.getStorageData().dealManager;
    }

    function upgradeFactory() external returns (address) {
        return CyberCorpStorage.getStorageData().upgradeFactory;
    }

    function companyOfficers(uint256 i) external returns (CompanyOfficer memory) {
        return CyberCorpStorage.getStorageData().companyOfficers[i];
    }

    function roundManager() external returns (address) {
        return CyberCorpStorage.getStorageData().roundManager;
    }

    // ========================
    // UUPSUpgradeable
    // ========================

    /// @notice UUPS upgrade authorization
    /// @dev MetaLeX releases new versions through the factory's reference implementation,
    /// and the CyberCorp owner can decide if or when he wants to perform the upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        if(
            ICyberCorpSingleFactory(
                CyberCorpStorage.getStorageData().upgradeFactory
            ).getRefImplementation() != newImplementation) {
            revert NotRefImplementation();
        }
    }
}

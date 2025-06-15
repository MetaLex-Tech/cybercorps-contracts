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
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./interfaces/IIssuanceManager.sol";

/// @title CyberCorp
/// @notice Main contract representing a corporation's on-chain presence and management
/// @dev Implements UUPS upgradeable pattern and BorgAuth access control
contract CyberCorp is Initializable, BorgAuthACL {
    // cyberCORP details
    /// @notice Legal name of the entity, including designation (e.g., "Inc." or "LLC")
    string public cyberCORPName;
    /// @notice Legal entity type (e.g., "corporation" or "limited liability company")
    string public cyberCORPType;
    /// @notice Jurisdiction of incorporation (e.g., "Delaware")
    string public cyberCORPJurisdiction;
    /// @notice Contact information for the corporation
    string public cyberCORPContactDetails;
    /// @notice Default dispute resolution mechanism for agreements
    string public defaultDisputeResolution;
    /// @notice Address that can receive payments on behalf of the company
    address public companyPayable;
    /// @notice Address of the issuance manager contract
    address public issuanceManager;
    /// @notice Address of the deal manager contract
    address public dealManager;
    /// @notice Implementation address for the CyberCertPrinter contract
    address public cyberCertPrinterImplementation;

    address public upgradeFactory;
    /// @notice Array of company officers with their roles and details
    CompanyOfficer[] public companyOfficers;
    /// @notice Array of company directors with their roles and details
    CompanyDirector[] public companyDirectors;
    /// @notice Board information for the corporation
    BoardInfo public boardInfo;


    event CyberCORPDetailsUpdated(string cyberCORPName, string cyberCORPType, string cyberCORPJurisdiction, string cyberCORPContactDetails, string defaultDisputeResolution);
    event OfficerAdded(address indexed officer, uint256 index);
    event OfficerRemoved(address indexed officer, uint256 index);
    event DirectorAdded(address indexed director, uint256 index);
    event DirectorRemoved(address indexed director, uint256 index);
    event BoardInfoUpdated(uint256 seats, string votingRule, address chairman, address boardSafe);
    event CompanyPayableUpdated(address indexed companyPayable, address indexed oldCompanyPayable);

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
        address _upgradeFactory
    ) public initializer {
        __BorgAuthACL_init(_auth);

        cyberCORPName = _cyberCORPName;
        cyberCORPType = _cyberCORPType;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        issuanceManager = _issuanceManager;
        companyPayable = _companyPayable;
        companyOfficers.push(_officer);
        upgradeFactory = _upgradeFactory;
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
        cyberCORPName = _cyberCORPName;
        cyberCORPType = _cyberCORPType;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;

        emit CyberCORPDetailsUpdated(cyberCORPName, cyberCORPType, cyberCORPJurisdiction, cyberCORPContactDetails, defaultDisputeResolution);
    }

    /// @notice Updates the issuance manager address
    /// @dev Only callable by owner
    /// @param _issuanceManager New issuance manager contract address
    function setIssuanceManager(address _issuanceManager) external onlyOwner() {
        issuanceManager = _issuanceManager;
    }

    /// @notice Updates the deal manager address
    /// @dev Only callable by owner
    /// @param _dealManager New deal manager contract address
    function setDealManager(address _dealManager) external onlyOwner() {
        dealManager = _dealManager;
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
        companyOfficers.push(_officer);
        AUTH.updateRole(_officer.eoa, 200);
        emit OfficerAdded(_officer.eoa, companyOfficers.length - 1);
    }

    /// @notice Removes an officer by their address
    /// @dev Only callable by owner, revokes officer role
    /// @param _address Address of the officer to remove
    function removeOfficer(address _address) external onlyOwner() {
        AUTH.updateRole(_address, 0);
        for (uint256 i = 0; i < companyOfficers.length; i++) {
            if (companyOfficers[i].eoa == _address) {
                companyOfficers[i] = companyOfficers[companyOfficers.length - 1];
                companyOfficers.pop();
                emit OfficerRemoved(_address, i);
                break;
            }
        }
    }

    /// @notice Removes an officer by their index in the officers array
    /// @dev Only callable by owner, revokes officer role
    /// @param _index Index of the officer to remove
    function removeOfficerAt(uint256 _index) external onlyOwner() {
        require(_index < companyOfficers.length, "Index out of bounds");
        address officerEOA = companyOfficers[_index].eoa;
        AUTH.updateRole(officerEOA, 0);
        companyOfficers[_index] = companyOfficers[companyOfficers.length - 1];
        companyOfficers.pop();
        emit OfficerRemoved(officerEOA, _index);
    }

    /// @notice Adds a new director to the board
    /// @dev Only callable by owner, sets director role to 200
    /// @param _director Director details including address and role
    function addDirector(CompanyDirector memory _director) external onlyOwner() {
        companyDirectors.push(_director);
        AUTH.updateRole(_director.eoa, 200);
        emit DirectorAdded(_director.eoa, companyDirectors.length - 1);
    }

    /// @notice Removes a director by their address
    /// @dev Only callable by owner, revokes director role
    /// @param _address Address of the director to remove
    function removeDirector(address _address) external onlyOwner() {
        AUTH.updateRole(_address, 0);
        for (uint256 i = 0; i < companyDirectors.length; i++) {
            if (companyDirectors[i].eoa == _address) {
                companyDirectors[i] = companyDirectors[companyDirectors.length - 1];
                companyDirectors.pop();
                emit DirectorRemoved(_address, i);
                break;
            }
        }
    }

    /// @notice Removes a director by index
    /// @dev Only callable by owner, revokes director role
    /// @param _index Index of the director to remove
    function removeDirectorAt(uint256 _index) external onlyOwner() {
        require(_index < companyDirectors.length, "Index out of bounds");
        address directorEOA = companyDirectors[_index].eoa;
        AUTH.updateRole(directorEOA, 0);
        companyDirectors[_index] = companyDirectors[companyDirectors.length - 1];
        companyDirectors.pop();
        emit DirectorRemoved(directorEOA, _index);
    }

    /// @notice Sets board information
    /// @param _seats Number of board seats
    /// @param _votingRule Voting rule description
    /// @param _chairman Address of the board chairman (0 if none)
    /// @param _boardSafe Address of the gnosis safe used for votes
    function setBoardInfo(
        uint256 _seats,
        string memory _votingRule,
        address _chairman,
        address _boardSafe
    ) external onlyOwner() {
        boardInfo = BoardInfo({
            seats: _seats,
            votingRule: _votingRule,
            chairman: _chairman,
            boardSafe: _boardSafe
        });
        emit BoardInfoUpdated(_seats, _votingRule, _chairman, _boardSafe);
    }

    function setCompanyPayable(address _companyPayable) external onlyOwner() {
        address oldCompanyPayable = companyPayable;
        companyPayable = _companyPayable;
        emit CompanyPayableUpdated(companyPayable, oldCompanyPayable);
    }
}

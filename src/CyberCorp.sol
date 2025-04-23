/*    .o.                                                                                         
     .888.                                                                                        
    .8"888.                                                                                       
   .8' `888.                                                                                      
  .88ooo8888.                                                                                     
 .8'     `888.                                                                                    
o88o     o8888o                                                                                   
                                                                                                  
                                                                                                  
                                                                                                  
ooo        ooooo               .             oooo                                                 
`88.       .888'             .o8             `888                                                 
 888b     d'888   .ooooo.  .o888oo  .oooo.    888   .ooooo.  oooo    ooo                          
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888  d88' `88b  `88b..8P'                           
 8  `888'   888  888ooo888   888    .oP"888   888  888ooo888    Y888'                             
 8    Y     888  888    .o   888 . d8(  888   888  888    .o  .o8"'88b                            
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888o `Y8bod8P' o88'   888o                          
                                                                                                  
                                                                                                  
                                                                                                  
  .oooooo.                .o8                            .oooooo.                                 
 d8P'  `Y8b              "888                           d8P'  `Y8b                                
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.  
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b 
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
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
    address public companyPayable;
    string public defaultLegend; //default legend (relating to transferability restrictions etc.) for NFT certs 
    address public issuanceManager;
    address public dealManager;
    address public cyberCertPrinterImplementation;
    CompanyOfficer[] public companyOfficers;

    event CyberCORPDetailsUpdated(string cyberCORPName, string cyberCORPType, string cyberCORPJurisdiction, string cyberCORPContactDetails, string defaultDisputeResolution, string defaultLegend);


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
        string memory _cyberCORPType,
        string memory _cyberCORPJurisdiction,
        string memory _cyberCORPContactDetails,
        string memory _defaultDisputeResolution,
        string memory _defaultLegend
    ) external onlyOwner() {
        cyberCORPName = _cyberCORPName;
        cyberCORPType = _cyberCORPType;
        cyberCORPJurisdiction = _cyberCORPJurisdiction;
        cyberCORPContactDetails = _cyberCORPContactDetails;
        defaultDisputeResolution = _defaultDisputeResolution;
        defaultLegend = _defaultLegend;

        emit CyberCORPDetailsUpdated(cyberCORPName, cyberCORPType, cyberCORPJurisdiction, cyberCORPContactDetails, defaultDisputeResolution, defaultLegend);
    }

    function setIssuanceManager(address _issuanceManager) external onlyOwner() {
        issuanceManager = _issuanceManager;
    }

    function setDealManager(address _dealManager) external onlyOwner() {
        dealManager = _dealManager;
    }

    function isCyberCORPOfficer(address _address) external view returns (bool) {
        return (AUTH.userRoles(_address) >= AUTH.OWNER_ROLE());
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

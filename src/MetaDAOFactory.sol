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

import "./interfaces/IIssuanceManagerFactory.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./interfaces/IDealManagerFactory.sol";
import "./interfaces/IDealManager.sol";
import "./interfaces/IRoundManagerFactory.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/ICyberAgreementRegistry.sol";
import "./CyberCorpConstants.sol";
import "./storage/CyberCertPrinterStorage.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IRoundManagerInit {
    function initialize(
        address _auth,
        address _corp,
        address _dealRegistry,
        address _issuanceManager,
        address _upgradeFactory
    ) external;
}

contract MetaDAOFactory is UUPSUpgradeable, BorgAuthACL, IERC721Receiver {
    using Strings for string;
    
    error InvalidSalt();

    address public registryAddress;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public dealManagerFactory;
    address public roundManagerFactory;
    address public uriBuilder;
    //store an escrowed signature hash for metaDAO
    bytes public metaDAOSignatureHash;
    address public stable;
    // stored MetaDAO officer details used in agreements
    CompanyOfficer public metaDAOOfficer;

    // Parent corp (MetaDAO) deployment record
    address public parentCorp;
    address public parentAuth;
    address public parentIssuanceManager;
    address public parentDealManager;
    address public parentRoundManager;
    bool public parentCorpCreated;

    //adjust storage gap based on new variable
    uint256[38] private __gap; // keep storage gap similar to CyberCorpFactory

    struct CyberCertData {
        string name;
        string symbol;
        string uri;
        SecurityClass securityClass;
        SecuritySeries securitySeries;
        address extension;
        string[] defaultLegend;
    }

    event MetaCorpDeployed(
        address indexed cyberCorp,
        address indexed auth,
        address indexed issuanceManager,
        address dealManager,
        address roundManager,
        address certPrinter,
        uint256 certTokenId,
        address ownerEOA
    );

    event ParentCorpCreated(
        address indexed corp,
        address indexed auth,
        address indexed issuanceManager,
        address dealManager,
        address roundManager
    );

    error GlobalOrPartyValuesMismatch();
    error OfficerValuesMismatch();

    function initialize(
        address _auth,
        address _registryAddress,
        address _issuanceManagerFactory,
        address _cyberCorpSingleFactory,
        address _dealManagerFactory,
        address _roundManagerFactory,
        address _uriBuilder,
        address _stable
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        registryAddress = _registryAddress;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        dealManagerFactory = _dealManagerFactory;
        roundManagerFactory = _roundManagerFactory;
        uriBuilder = _uriBuilder;
        stable = _stable;
    }

    function setMetaDAOSignatureHash(bytes memory _metaDAOSignatureHash) public onlyOwner {
        metaDAOSignatureHash = _metaDAOSignatureHash;
    }

    function setStable(address _stable) public onlyOwner {
        stable = _stable;
    }

    function setMetaDAOOfficer(CompanyOfficer memory _officer) public onlyOwner {
        metaDAOOfficer = _officer;
    }

    function setMetaDAOOfficerEOA(address _eoa) public onlyOwner {
        metaDAOOfficer.eoa = _eoa;
    }

    function setMetaDAOOfficerName(string memory _name) public onlyOwner {
        metaDAOOfficer.name = _name;
    }

    function setMetaDAOOfficerContact(string memory _contact) public onlyOwner {
        metaDAOOfficer.contact = _contact;
    }

    function setMetaDAOOfficerTitle(string memory _title) public onlyOwner {
        metaDAOOfficer.title = _title;
    }

    function deployMetaCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer
    )
        public
        returns (
            address cyberCorpAddress,
            address authAddress,
            address issuanceManagerAddress,
            address dealManagerAddress,
            address roundManagerAddress
        )
    {
        if (salt == bytes32(0)) revert InvalidSalt();


//fix event
        emit MetaCorpDeployed(cyberCorpAddress, authAddress, issuanceManagerAddress, dealManagerAddress, roundManagerAddress, address(0), 0, _officer.eoa);
    }



    // Allow this factory to receive ERC721 tokens via safeTransferFrom/safeMint
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}



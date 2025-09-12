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
import "./CyberCorpConstants.sol";
import "./storage/CyberCertPrinterStorage.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IRoundManagerInitMeta {
    function initialize(
        address _auth,
        address _corp,
        address _dealRegistry,
        address _issuanceManager,
        address _upgradeFactory
    ) external;
}

contract MetaDAOFactory is UUPSUpgradeable, BorgAuthACL {
    error InvalidSalt();

    address public registryAddress;
    address public cyberCertPrinterImplementation;
    address public cyberCert20Implementation;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public dealManagerFactory;
    address public roundManagerFactory;
    address public uriBuilder;

    uint256[44] private __gap; // keep storage gap similar to CyberCorpFactory

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

    function initialize(
        address _auth,
        address _registryAddress,
        address _cyberCertPrinterImplementation,
        address _cyberCert20Implementation,
        address _issuanceManagerFactory,
        address _cyberCorpSingleFactory,
        address _dealManagerFactory,
        address _roundManagerFactory,
        address _uriBuilder
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        registryAddress = _registryAddress;
        cyberCertPrinterImplementation = _cyberCertPrinterImplementation;
        cyberCert20Implementation = _cyberCert20Implementation;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        dealManagerFactory = _dealManagerFactory;
        roundManagerFactory = _roundManagerFactory;
        uriBuilder = _uriBuilder;
    }

    function deployMetaCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer,
        CyberCertData memory _certData,
        CertificateDetails memory _details,
        bytes memory singlePartySignature
    )
        public
        returns (
            address cyberCorpAddress,
            address authAddress,
            address issuanceManagerAddress,
            address dealManagerAddress,
            address roundManagerAddress,
            address certPrinterAddress,
            uint256 certTokenId
        )
    {
        if (salt == bytes32(0)) revert InvalidSalt();

        // Deploy BorgAuth with CREATE2
        bytes memory authBytecode = type(BorgAuth).creationCode;
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.deploy(0, authSalt, abi.encodePacked(authBytecode, abi.encode(address(this))));

        // Bootstrap roles: give officer a high role for immediate access
        BorgAuth(authAddress).updateRole(_officer.eoa, 200);

        // Deploy IssuanceManager via factory
        issuanceManagerAddress = IIssuanceManagerFactory(issuanceManagerFactory).deployIssuanceManager(salt);

        // Deploy CyberCorp via single factory
        cyberCorpAddress = ICyberCorpSingleFactory(cyberCorpSingleFactory).deployCyberCorpSingle(salt);

        // Initialize CyberCorp
        ICyberCorp(cyberCorpAddress).initialize(
            authAddress,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            issuanceManagerAddress,
            _companyPayable,
            _officer,
            cyberCorpSingleFactory,
            address(0)
        );

        // Allow corp to administer
        BorgAuth(authAddress).updateRole(cyberCorpAddress, 200);

        // Deploy and initialize DealManager
        dealManagerAddress = IDealManagerFactory(dealManagerFactory).deployDealManager(salt);
        ICyberCorp(cyberCorpAddress).setDealManager(dealManagerAddress);

        // Initialize IssuanceManager
        IIssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            cyberCertPrinterImplementation,
            uriBuilder,
            issuanceManagerFactory,
            cyberCert20Implementation
        );

        // Initialize DealManager
        IDealManager(dealManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            registryAddress,
            issuanceManagerAddress,
            dealManagerFactory
        );

        // Deploy and initialize RoundManager
        roundManagerAddress = IRoundManagerFactory(roundManagerFactory).deployRoundManager(salt);
        IRoundManagerInitMeta(roundManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            registryAddress,
            issuanceManagerAddress,
            roundManagerFactory
        );
        ICyberCorp(cyberCorpAddress).setRoundManager(roundManagerAddress);

        // Grant contract roles
        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);
        BorgAuth(authAddress).updateRole(roundManagerAddress, 99);

        // Create certificate printer and assign a single-party certificate to owner's EOA
        ICyberCertPrinter certPrinter = ICyberCertPrinter(
            IIssuanceManager(issuanceManagerAddress).createCertPrinter(
                _certData.defaultLegend,
                string.concat(companyName, " ", _certData.name),
                _certData.symbol,
                _certData.uri,
                _certData.securityClass,
                _certData.securitySeries,
                _certData.extension
            )
        );
        certPrinterAddress = address(certPrinter);

        // Embed the provided signature into extensionData so it travels with the certificate
        CertificateDetails memory detailsWithSig = _details;
        detailsWithSig.extensionData = singlePartySignature;

        certTokenId = IIssuanceManager(issuanceManagerAddress).createCertAndAssign(
            certPrinterAddress,
            _officer.eoa,
            detailsWithSig
        );

        emit MetaCorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            roundManagerAddress,
            certPrinterAddress,
            certTokenId,
            _officer.eoa
        );
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}



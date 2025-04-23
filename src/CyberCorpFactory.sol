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

import "./interfaces/IIssuanceManagerFactory.sol";
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/IDealManagerFactory.sol";
import "./interfaces/IDealManager.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/ICyberAgreementFactory.sol";
import "./interfaces/ICyberAgreementRegistry.sol";
import "./CyberCorpConstants.sol";
import "./libs/auth.sol";

contract CyberCorpFactory is BorgAuthACL {
    error InvalidSalt();
    error DeploymentFailed();

    address public registryAddress;
    address public cyberCertPrinterImplementation;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public cyberAgreementFactory;
    address public dealManagerFactory;
    address public uriBuilder;
    address public stable;// = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;//base main net 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    event CyberCorpDeployed(
        address indexed cyberCorp,
        address indexed auth,
        address indexed issuanceManager,
        address dealManager,
        string companyName
    );

    event AgreementDeployed(
        address indexed agreementFactory,
        address indexed agreement,
        address indexed lexscrow,
        bytes32 salt
    );

    constructor(address _registryAddress, address _cyberCertPrinterImplementation, address _issuanceManagerFactory, address _cyberCorpSingleFactory, address _dealManagerFactory, address _uriBuilder) {
        registryAddress = _registryAddress;
        cyberCertPrinterImplementation = _cyberCertPrinterImplementation;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        dealManagerFactory = _dealManagerFactory;
        uriBuilder = _uriBuilder;

    }

    function initialize(
        address _auth
    ) external initializer {
        // Initialize BorgAuthACL
        __BorgAuthACL_init(_auth);
    }

    function deployCyberCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        string memory defaultLegend,
        address _companyPayable,
        CompanyOfficer memory _officer
    ) public returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address dealManagerAddress) {
        if (salt == bytes32(0)) revert InvalidSalt();

        // Deploy BorgAuth with CREATE2
        bytes memory authBytecode = type(BorgAuth).creationCode;
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.deploy(0, authSalt, authBytecode);

        // Initialize BorgAuth
        BorgAuth(authAddress).initialize();
        BorgAuth(authAddress).updateRole(_officer.eoa, 200);

        issuanceManagerAddress = IIssuanceManagerFactory(issuanceManagerFactory).deployIssuanceManager(salt);

        cyberCorpAddress = ICyberCorpSingleFactory(cyberCorpSingleFactory).deployCyberCorpSingle(salt, authAddress, companyName, companyJurisdiction, companyContactDetails, defaultDisputeResolution, defaultLegend, issuanceManagerAddress, _companyPayable, _officer);
        BorgAuth(authAddress).updateRole(cyberCorpAddress, 200);
        //deploy deal manager
        dealManagerAddress = IDealManagerFactory(dealManagerFactory).deployDealManager(salt);
        ICyberCorp(cyberCorpAddress).setDealManager(dealManagerAddress);
        // Initialize IssuanceManager
        IIssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            cyberCertPrinterImplementation,
            uriBuilder
        );

        //update role for issuance manager
        IDealManager(dealManagerAddress).initialize(authAddress, cyberCorpAddress, registryAddress, issuanceManagerAddress);
        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);

        emit CyberCorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            companyName
        );
    }

    function deployCyberCorpAndCreateOffer(
        uint256 salt,
        string memory companyName,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer,
        string memory certName,
        string memory certSymbol,
        string memory certificateUri,
        SecurityClass securityClass,
        SecuritySeries securitySeries,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[][] memory _partyValues,
        bytes memory signature,
        CertificateDetails memory _details,
        address[] memory conditions,
        string[] memory _defaultLegend,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address dealManagerAddress, address certPrinterAddress, bytes32 id) {

        //create bytes32 salt
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        //set this officer's eoa to the sender
        _officer.eoa = msg.sender;

        (cyberCorpAddress, authAddress, issuanceManagerAddress, dealManagerAddress) = deployCyberCorp(
            corpSalt,
            companyName,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            "",
            _companyPayable,
            _officer
        );

        //string[] memory defaultLegend = new string[](0);
        ICyberCertPrinter certPrinter = ICyberCertPrinter(IIssuanceManager(issuanceManagerAddress).createCertPrinter(_defaultLegend, string.concat(companyName, " ", certName), certSymbol, certificateUri, securityClass, securitySeries));
        certPrinterAddress = address(certPrinter);

        // Create and sign deal
        uint256 certId;
        (id, certId) = IDealManager(dealManagerAddress).proposeAndSignDeal(
            certPrinterAddress,
            stable,
            _paymentAmount,
            _templateId,
            salt,
            _globalValues,
            _parties,
            _details,
            msg.sender,
            signature,
            _partyValues,
            conditions,
            secretHash,
            expiry
        );

    }

    function setStable(address _stable) external onlyOwner {
        stable = _stable;
    }
}

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
import "./libs/auth.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/IDealManagerFactory.sol";
import "./interfaces/IDealManager.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./interfaces/ICyberCertPrinter.sol";
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
        string cyberCORPName,
        string cyberCORPType,
        string cyberCORPContactDetails,
        string cyberCORPJurisdiction,
        string defaultDisputeResolution
    );

    event AgreementDeployed(
        address indexed agreementFactory,
        address indexed agreement,
        address indexed lexscrow,
        bytes32 salt
    );

    event DealManagerFactoryUpdated(
        address indexed dealManagerFactory,
        address oldDealFactory
    );

    //create an event when IssuanceManagerFactory is updated
    event IssuanceManagerFactoryUpdated(
        address indexed issuanceManagerFactory,
        address oldIssuanceFactory
    );

    event CyberCorpSingleFactoryUpdated(
        address indexed cyberCorpSingleFactory,
        address oldCyberCorpFactory
    );

    event CyberAgreementFactoryUpdated(
        address indexed cyberAgreementFactory,
        address oldCyberAgreementFactory
    );

    constructor(
        address _auth,
        address _registryAddress,
        address _cyberCertPrinterImplementation,
        address _issuanceManagerFactory,
        address _cyberCorpSingleFactory,
        address _dealManagerFactory,
        address _uriBuilder
    ) {
        initialize(_auth, _registryAddress, _cyberCertPrinterImplementation, _issuanceManagerFactory, _cyberCorpSingleFactory, _dealManagerFactory, _uriBuilder);
    }

    function initialize(
        address _auth,
        address _registryAddress,
        address _cyberCertPrinterImplementation,
        address _issuanceManagerFactory,
        address _cyberCorpSingleFactory,
        address _dealManagerFactory,
        address _uriBuilder
    ) public initializer {
        // Initialize BorgAuthACL
        __BorgAuthACL_init(_auth);

        registryAddress = _registryAddress;
        cyberCertPrinterImplementation = _cyberCertPrinterImplementation;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        dealManagerFactory = _dealManagerFactory;
        uriBuilder = _uriBuilder;
    }

    function deployCyberCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer
    ) public returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address dealManagerAddress) {
        if (salt == bytes32(0)) revert InvalidSalt();

        // Deploy BorgAuth with CREATE2 with new param address owner
        bytes memory authBytecode = type(BorgAuth).creationCode;
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.deploy(0, authSalt, abi.encodePacked(authBytecode, abi.encode(address(this))));

        // Initialize BorgAuth
       // BorgAuth(authAddress).initialize();
        BorgAuth(authAddress).updateRole(_officer.eoa, 200);

        issuanceManagerAddress = IIssuanceManagerFactory(issuanceManagerFactory).deployIssuanceManager(salt);

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
            cyberCorpSingleFactory
        );
        
        BorgAuth(authAddress).updateRole(cyberCorpAddress, 200);
        //deploy deal manager
        dealManagerAddress = IDealManagerFactory(dealManagerFactory).deployDealManager(salt);
        ICyberCorp(cyberCorpAddress).setDealManager(dealManagerAddress);
        // Initialize IssuanceManager
        IIssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            cyberCertPrinterImplementation,
            uriBuilder,
            issuanceManagerFactory
        );

        //update role for issuance manager
        IDealManager(dealManagerAddress).initialize(authAddress, cyberCorpAddress, registryAddress, issuanceManagerAddress, dealManagerFactory);
        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);

        emit CyberCorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            companyName,
            companyType,
            companyContactDetails,
            companyJurisdiction,
            defaultDisputeResolution
        );
    }

    function deployCyberCorpAndCreateOffer(
        uint256 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer,
        string[] memory certName,
        string[] memory certSymbol,
        string[] memory certificateUri,
        SecurityClass[] memory securityClass,
        SecuritySeries[] memory securitySeries,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[][] memory _partyValues,
        bytes memory signature,
        CertificateDetails[] memory _details,
        address[] memory conditions,
        string[][] memory _defaultLegend,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (address cyberCorpAddress, address authAddress, address issuanceManagerAddress, address dealManagerAddress, address[] memory certPrinterAddress, bytes32 id, uint256[] memory certIds) {

        //create bytes32 salt
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        //set this officer's eoa to the sender
        _officer.eoa = msg.sender;

        (cyberCorpAddress, authAddress, issuanceManagerAddress, dealManagerAddress) = deployCyberCorp(
            corpSalt,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            _companyPayable,
            _officer
        );

        certPrinterAddress = new address[](_details.length);
        //string[] memory defaultLegend = new string[](0);
        for(uint256 i = 0; i < _details.length; i++) {
            ICyberCertPrinter certPrinter = ICyberCertPrinter(IIssuanceManager(issuanceManagerAddress).createCertPrinter(_defaultLegend[i], string.concat(companyName, " ", certName[i]), certSymbol[i], certificateUri[i], securityClass[i], securitySeries[i]));
            certPrinterAddress[i] = address(certPrinter);
        }

        // Create and sign deal
        certIds = new uint256[](_details.length);
        (id, certIds) = IDealManager(dealManagerAddress).proposeAndSignDeal(
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

    function setIssuanceManagerFactory(address _issuanceManagerFactory) external onlyOwner {
        address oldIssuanceFactory = issuanceManagerFactory;
        issuanceManagerFactory = _issuanceManagerFactory;
        emit IssuanceManagerFactoryUpdated(issuanceManagerFactory, oldIssuanceFactory);
    }

    function setCyberCorpSingleFactory(address _cyberCorpSingleFactory) external onlyOwner {
        address oldCyberCorpFactory = cyberCorpSingleFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        emit CyberCorpSingleFactoryUpdated(cyberCorpSingleFactory, oldCyberCorpFactory);
    }

    function setCyberAgreementFactory(address _cyberAgreementFactory) external onlyOwner {
        address oldCyberAgreementFactory = cyberAgreementFactory;
        cyberAgreementFactory = _cyberAgreementFactory;
        emit CyberAgreementFactoryUpdated(cyberAgreementFactory, oldCyberAgreementFactory);
    }

    function setDealManagerFactory(address _dealManagerFactory) external onlyOwner {
        address oldDealFactory = dealManagerFactory;
        dealManagerFactory = _dealManagerFactory;
        emit DealManagerFactoryUpdated(dealManagerFactory, oldDealFactory);
    }
    
}

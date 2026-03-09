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

interface ICyberCorpLocal {
    function issuanceManager() external view returns (address);
}

contract PumpCoFactory is UUPSUpgradeable, BorgAuthACL, IERC721Receiver {
    using Strings for string;
    
    error InvalidSalt();
    error RoundManagerAlreadyExists();

    address public registryAddress;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public dealManagerFactory;
    address public roundManagerFactory;
    address public uriBuilder;
    //store an escrowed signature hash for parent corp
    bytes public pumpCoSignatureHash;
    // stored PumpCo officer details used in agreements
    CompanyOfficer public pumpCoOfficer;

    // Parent corp (PumpCo) deployment record
    address public pumpCorp;
    address public parentAuth;
    address public parentIssuanceManager;
    address public parentDealManager;
    address public parentRoundManager;
    bool public pumpCorpCreated;

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

    event CorpDeployed(
        address indexed cyberCorp,
        address indexed auth,
        address indexed issuanceManager,
        address dealManager,
        address roundManager,
        string cyberCORPName,
        string cyberCORPType,
        string cyberCORPContactDetails,
        string cyberCORPJurisdiction,
        string defaultDisputeResolution,
        address _companyPayable,
        address certPrinter,
        uint256 certTokenId,
        address ownerEOA
    );

    event PumpCorpCreated(
        address indexed corp,
        address indexed auth,
        address indexed issuanceManager,
        address dealManager,
        address roundManager
    );

    event IssuanceManagerFactoryUpdated(
        address indexed issuanceManagerFactory,
        address oldIssuanceFactory
    );

    event CyberCorpSingleFactoryUpdated(
        address indexed cyberCorpSingleFactory,
        address oldCyberCorpFactory
    );

    event DealManagerFactoryUpdated(
        address indexed dealManagerFactory,
        address oldDealFactory
    );

    event RoundManagerFactoryUpdated(
        address indexed roundManagerFactory,
        address oldRoundManagerFactory
    );

    event UriBuilderUpdated(address indexed uriBuilder, address oldUriBuilder);
    event RegistryAddressUpdated(address indexed registryAddress, address oldRegistryAddress);

    error GlobalOrPartyValuesMismatch();
    error OfficerValuesMismatch();

    function initialize(
        address _auth,
        address _registryAddress,
        address _issuanceManagerFactory,
        address _cyberCorpSingleFactory,
        address _dealManagerFactory,
        address _roundManagerFactory,
        address _uriBuilder
    ) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);

        registryAddress = _registryAddress;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        dealManagerFactory = _dealManagerFactory;
        roundManagerFactory = _roundManagerFactory;
        uriBuilder = _uriBuilder;
    }

    function setPumpCoSignatureHash(bytes memory _pumpCoSignatureHash) public onlyOwner {
        pumpCoSignatureHash = _pumpCoSignatureHash;
    }

    function setPumpCoOfficer(CompanyOfficer memory _officer) public onlyOwner {
        pumpCoOfficer = _officer;
    }

    function setPumpCoOfficerEOA(address _eoa) public onlyOwner {
        pumpCoOfficer.eoa = _eoa;
    }

    function setPumpCoOfficerName(string memory _name) public onlyOwner {
        pumpCoOfficer.name = _name;
    }

    function setPumpCoOfficerContact(string memory _contact) public onlyOwner {
        pumpCoOfficer.contact = _contact;
    }

    function setPumpCoOfficerTitle(string memory _title) public onlyOwner {
        pumpCoOfficer.title = _title;
    }

    function setIssuanceManagerFactory(address _issuanceManagerFactory) external onlyOwner {
        address old = issuanceManagerFactory;
        issuanceManagerFactory = _issuanceManagerFactory;
        emit IssuanceManagerFactoryUpdated(_issuanceManagerFactory, old);
    }

    function setCyberCorpSingleFactory(address _cyberCorpSingleFactory) external onlyOwner {
        address old = cyberCorpSingleFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        emit CyberCorpSingleFactoryUpdated(_cyberCorpSingleFactory, old);
    }

    function setDealManagerFactory(address _dealManagerFactory) external onlyOwner {
        address old = dealManagerFactory;
        dealManagerFactory = _dealManagerFactory;
        emit DealManagerFactoryUpdated(_dealManagerFactory, old);
    }

    function setRoundManagerFactory(address _roundManagerFactory) external onlyOwner {
        address old = roundManagerFactory;
        roundManagerFactory = _roundManagerFactory;
        emit RoundManagerFactoryUpdated(_roundManagerFactory, old);
    }

    function setUriBuilder(address _uriBuilder) external onlyOwner {
        address old = uriBuilder;
        uriBuilder = _uriBuilder;
        emit UriBuilderUpdated(_uriBuilder, old);
    }

    function setRegistryAddress(address _registryAddress) external onlyOwner {
        address old = registryAddress;
        registryAddress = _registryAddress;
        emit RegistryAddressUpdated(_registryAddress, old);
    }

    function deployCorp(
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

        // Deploy BorgAuth with CREATE2 with new param address owner
        bytes memory authBytecode = type(BorgAuth).creationCode;
        bytes32 authSalt = keccak256(abi.encodePacked("auth", salt));
        authAddress = Create2.deploy(
            0,
            authSalt,
            abi.encodePacked(authBytecode, abi.encode(address(this)))
        );

        // Initialize BorgAuth
        // BorgAuth(authAddress).initialize();
        BorgAuth(authAddress).updateRole(_officer.eoa, 200);

        issuanceManagerAddress = IIssuanceManagerFactory(issuanceManagerFactory)
            .deployIssuanceManager(salt);

        cyberCorpAddress = ICyberCorpSingleFactory(cyberCorpSingleFactory)
            .deployCyberCorpSingle(salt);

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

        BorgAuth(authAddress).updateRole(cyberCorpAddress, 200);
        //deploy deal manager
        dealManagerAddress = IDealManagerFactory(dealManagerFactory)
            .deployDealManager(salt);
        ICyberCorp(cyberCorpAddress).setDealManager(dealManagerAddress);

        IIssuanceManager(issuanceManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            uriBuilder,
            issuanceManagerFactory
        );

        // Initialize DealManager
        IDealManager(dealManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            registryAddress,
            issuanceManagerAddress,
            dealManagerFactory
        );

        // TODO WIP: review needed (start)
        // Deploy and initialize RoundManager
        roundManagerAddress = deployAndInitializeRoundManager(salt, cyberCorpAddress);

        // Authorize peripheral contracts for the cyber corp. It is ok to do it here on behalf of the corp
        // because the corp has just been created by us.
        // In contrast, if any of the peripheral contract is being retrofitted to an existing corp,
        // they would have to authorize it themselves for security reasons.

        // Set RoundManager on the corp
        ICyberCorp(cyberCorpAddress).setRoundManager(roundManagerAddress);
        // TODO WIP: review needed (end)

        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);
        BorgAuth(authAddress).updateRole(roundManagerAddress, 99);

        emit CorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            roundManagerAddress,
            companyName,
            companyType,
            companyContactDetails,
            companyJurisdiction,
            defaultDisputeResolution,
            _companyPayable,
            address(0), // certPrinter
            0, // certTokenId
            _officer.eoa // ownerEOA
        );
    }

    // Admin-only, one-time creation of the parent corp
    // TODO WIP: do we need this?
    function createPumpCorp(
        bytes32 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable
    ) external onlyOwner returns (
        address corp,
        address auth,
        address issuance,
        address dealMgr,
        address roundMgr
    ) {
        if (pumpCorpCreated) revert("PumpCorpAlreadyCreated");
        CompanyOfficer memory officer = pumpCoOfficer;
        if (officer.eoa == address(0)) revert("PumpCoOfficerNotSet");

        (
            corp,
            auth,
            issuance,
            dealMgr,
            roundMgr
        ) = deployCorp(
            salt,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            _companyPayable,
            officer
        );

        pumpCorp = corp;
        parentAuth = auth;
        parentIssuanceManager = issuance;
        parentDealManager = dealMgr;
        parentRoundManager = roundMgr;
        pumpCorpCreated = true;

        emit PumpCorpCreated(corp, auth, issuance, dealMgr, roundMgr);
    }

    function deployCyberCorpAndCreateRound(
        uint256 salt,
        SecuritySeries seriesType,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer,
        string[] memory legalDetails,
        bytes[] memory extensionData,
        RM_CyberCertData[] memory certData,
        bytes32 templateId,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        string[] memory roundPartyValues,
        bytes memory escrowedSignature,
        RoundType roundType,
        address[] memory conditions,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 startTime,
        uint256 endTime,
        bool publicRound,
        bool allowTimedOffers
    )
        external
        returns (
            address cyberCorpAddress,
            address authAddress,
            address issuanceManagerAddress,
            address dealManagerAddress,
            address roundManagerAddress,
            bytes32 roundId
        )
    {
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        (
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            roundManagerAddress
        ) = deployCyberCorp(
            corpSalt,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            _companyPayable,
            _officer
        );

        // Deploy RoundManager via its factory
        bytes32 rmSalt = keccak256(abi.encodePacked("round", salt));


        // Create round with provided round type using RoundLib
        {
            Round memory draft = RoundLib
                .draft()
                .setTickets(
                    seriesType,
                    roundType,
                    publicRound,
                    allowTimedOffers,
                    raiseCap,
                    minTicket,
                    maxTicket,
                    paymentToken,
                    pricePerUnit,
                    valuation,
                    startTime,
                    endTime
                )
                .setAgreement(
                    templateId,
                    _officer.eoa,
                    _officer.name,
                    _officer.title,
                    legalDetails,
                    roundPartyValues,
                    extensionData,
                    conditions,
                    escrowedSignature
                );
            roundId = IRoundManagerInterface(roundManagerAddress).createRound(
                draft,
                certData
            );
        }
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
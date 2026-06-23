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
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
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

contract ParentCoFactory is UUPSUpgradeable, BorgAuthACL, IERC721Receiver {
    using Strings for string;
    using ECDSA for bytes32;
    
    error InvalidSalt();
    error RoundManagerAlreadyExists();

    address public registryAddress;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public dealManagerFactory;
    address public roundManagerFactory;
    address public uriBuilder;
    //store an escrowed signature hash for parent corp
    bytes public parentCoSignatureHash;
    address public stable;
    // stored ParentCo officer details used in agreements
    CompanyOfficer[] public parentCoOfficers;

    // EIP-712
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public ESCROW_AUTHORIZATION_TYPEHASH;

    // Parent corp (ParentCo) deployment record
    address public parentCorp;
    address public parentAuth;
    address public parentIssuanceManager;
    address public parentDealManager;
    address public parentRoundManager;
    bool public parentCorpCreated;

    //adjust storage gap based on new variable
    uint256[39] private __gap; // keep storage gap similar to CyberCorpFactory

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

    event RoundManagerDeployed(address indexed cyberCorp, address indexed roundManager);

    event UriBuilderUpdated(address indexed uriBuilder, address oldUriBuilder);
    event RegistryAddressUpdated(address indexed registryAddress, address oldRegistryAddress);

    error GlobalOrPartyValuesMismatch();
    error OfficerValuesMismatch();
    error UnauthorizedEscrowSigner();

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

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ParentCoFactory"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
        ESCROW_AUTHORIZATION_TYPEHASH = keccak256("EscrowAuthorization(string name,string contact)");
    }

    function setParentCoSignatureHash(bytes memory _parentCoSignatureHash) public onlyOwner {
        parentCoSignatureHash = _parentCoSignatureHash;
    }

    function setStable(address _stable) public onlyOwner {
        stable = _stable;
    }

    function setParentCoOfficers(CompanyOfficer[] memory _officers) public onlyOwner {
        delete parentCoOfficers;
        for (uint256 i = 0; i < _officers.length; i++)
            parentCoOfficers.push(_officers[i]);
    }

    /// @notice Authorization should include everything used to escrow-sign:
    /// - escrow contract (implicit)
    /// - EOA (implicit)
    /// - name (explicit)
    /// - contact (explicit)
    function escrowAuthorizationHash(string memory name, string memory contact) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(
                    ESCROW_AUTHORIZATION_TYPEHASH,
                    keccak256(bytes(name)),
                    keccak256(bytes(contact))
                ))
            )
        );
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

        if (ICyberCorp(cyberCorpAddress).roundManager() != address(0)) {
            revert RoundManagerAlreadyExists();
        }

        roundManagerAddress = IRoundManagerFactory(roundManagerFactory).deployRoundManager(salt);

        IRoundManagerInit(roundManagerAddress).initialize(
            address(BorgAuthACL(cyberCorpAddress).AUTH()),
            cyberCorpAddress,
            registryAddress,
            ICyberCorpLocal(cyberCorpAddress).issuanceManager(),
            roundManagerFactory
        );

        ICyberCorp(cyberCorpAddress).setRoundManager(roundManagerAddress);

        emit RoundManagerDeployed(cyberCorpAddress, roundManagerAddress);

        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);
        BorgAuth(authAddress).updateRole(roundManagerAddress, 99);

        emit CorpDeployed(cyberCorpAddress, authAddress, issuanceManagerAddress, dealManagerAddress, roundManagerAddress, address(0), 0, _officer.eoa);
    }

    // Admin-only, one-time creation of the  parent corp
    function createParentCorp(
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
        if (parentCorpCreated) revert("ParentCorpAlreadyCreated");
        CompanyOfficer memory officer = parentCoOfficers[0];
        if (officer.eoa == address(0)) revert("ParentCoOfficerNotSet");

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

        // Add the remaining officers
        for (uint256 i = 1; i < parentCoOfficers.length; i++) {
            ICyberCorp(corp).addOfficer(parentCoOfficers[i]);
        }

        parentCorp = corp;
        parentAuth = auth;
        parentIssuanceManager = issuance;
        parentDealManager = dealMgr;
        parentRoundManager = roundMgr;
        parentCorpCreated = true;

        emit ParentCorpCreated(corp, auth, issuance, dealMgr, roundMgr);
    }

    function deployCorpContractFor(
        uint256 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer, // PC always has only one officer
        bytes32 _segCoTemplateId,
        bytes32 _boardConsentTempateId,
        string[] memory _globalValues,
        string[] memory _partyValues,
        bytes memory signature,
        address deployer
    )
        external
        returns (
            address cyberCorpAddress,
            address authAddress,
            address issuanceManagerAddress,
            address dealManagerAddress,
            address roundManagerAddress,
            address[] memory certPrinterAddress,
            bytes32 id,
            uint256[] memory certIds
        )
    {
        // Resolve which officer pre-signed the escrow authorization
        CompanyOfficer memory signingOfficer;
        bool signerFound;
        for (uint256 i = 0; i < parentCoOfficers.length; i++) {
            address escrowSigner = escrowAuthorizationHash(
                parentCoOfficers[i].name,
                parentCoOfficers[i].contact
            ).recover(parentCoSignatureHash);
            if (parentCoOfficers[i].eoa == escrowSigner) {
                signingOfficer = parentCoOfficers[i];
                signerFound = true;
                break;
            }
        }
        if (!signerFound) revert UnauthorizedEscrowSigner();

        // Check: validate key fields

        if (_partyValues.length < 2
            || !_partyValues[0].equal(_officer.name)
            || !_partyValues[1].equal(_officer.contact)
            || !_globalValues[2].equal(companyName)
            || !_globalValues[3].equal(companyType)
            || !_globalValues[4].equal(companyJurisdiction)
            || !_globalValues[5].equal(companyContactDetails)
        ) {
            revert GlobalOrPartyValuesMismatch();
        }

        if (_officer.eoa != deployer) {
            revert OfficerValuesMismatch();
        }

        // Effect: construct parties
        address[] memory partiesOverride = new address[](2);
        partiesOverride[0] = signingOfficer.eoa;
        partiesOverride[1] = deployer;

        string[][] memory partyValuesOverride = new string[][](2);
        partyValuesOverride[0] = new string[](2);
        partyValuesOverride[0][0] = signingOfficer.name;
        partyValuesOverride[0][1] = signingOfficer.contact;
        partyValuesOverride[1] = _partyValues;

        //create bytes32 salt
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        (
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            roundManagerAddress
        ) = deployCorp(
            corpSalt,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            _companyPayable,
            _officer
        );

        //both parties sign one agreement
        bytes32 agreementId = ICyberAgreementRegistry(registryAddress).createContract(
            _segCoTemplateId,
            salt,
            _globalValues,
            partiesOverride,
            partyValuesOverride,
            bytes32(0),
            address(this),
            block.timestamp + 7 days
        );

        ICyberAgreementRegistry(registryAddress).signContractFor(deployer, agreementId, partyValuesOverride[1], signature, false, "");

        ICyberAgreementRegistry(registryAddress).signContractWithEscrow(
            signingOfficer.eoa,
            agreementId,
            partyValuesOverride[0],
            parentCoSignatureHash,
            false,
            ""
        );

        //parent company sign the meeting notes (single-party)
        address[] memory meetingNotesParties = new address[](1);
        meetingNotesParties[0] = partiesOverride[0];
        string[][] memory meetingNotesPartyValues = new string[][](1);
        meetingNotesPartyValues[0] = partyValuesOverride[0];
        bytes32 meetingNotesId = ICyberAgreementRegistry(registryAddress).createContract(
            _boardConsentTempateId,
            salt,
            _globalValues,
            meetingNotesParties,
            meetingNotesPartyValues,
            bytes32(0),
            address(this),
            block.timestamp + 7 days
        );

        ICyberAgreementRegistry(registryAddress).signContractWithEscrow(
            signingOfficer.eoa,
            meetingNotesId,
            meetingNotesPartyValues[0],
            parentCoSignatureHash,
            false,
            ""
        );
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
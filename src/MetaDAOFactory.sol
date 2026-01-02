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
        // Initialize IssuanceManager
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

        roundManagerAddress = IRoundManagerFactory(roundManagerFactory).deployRoundManager(salt);

        // Initialize RoundManager
        IRoundManagerInit(roundManagerAddress).initialize(
            authAddress,
            cyberCorpAddress,
            registryAddress,
            issuanceManagerAddress,
            roundManagerFactory
        );

        // Set RoundManager on the corp
        ICyberCorp(cyberCorpAddress).setRoundManager(roundManagerAddress);

        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);
        BorgAuth(authAddress).updateRole(roundManagerAddress, 99);

//fix event
        emit MetaCorpDeployed(cyberCorpAddress, authAddress, issuanceManagerAddress, dealManagerAddress, roundManagerAddress, address(0), 0, _officer.eoa);
    }

    // Admin-only, one-time creation of the MetaDAO parent corp
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
        CompanyOfficer memory officer = metaDAOOfficer;
        if (officer.eoa == address(0)) revert("MetaDAOOfficerNotSet");

        (
            corp,
            auth,
            issuance,
            dealMgr,
            roundMgr
        ) = deployMetaCorp(
            salt,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            _companyPayable,
            officer
        );

        parentCorp = corp;
        parentAuth = auth;
        parentIssuanceManager = issuance;
        parentDealManager = dealMgr;
        parentRoundManager = roundMgr;
        parentCorpCreated = true;

        emit ParentCorpCreated(corp, auth, issuance, dealMgr, roundMgr);
    }

    function deployMetaDAOContractFor(
        uint256 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer,
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
        partiesOverride[0] = metaDAOOfficer.eoa;
        partiesOverride[1] = deployer;

        string[][] memory partyValuesOverride = new string[][](2);
        partyValuesOverride[0] = new string[](2);
        partyValuesOverride[0][0] = metaDAOOfficer.name;
        partyValuesOverride[0][1] = metaDAOOfficer.contact;
        partyValuesOverride[1] = _partyValues;

        //create bytes32 salt
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        (
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            roundManagerAddress
        ) = deployMetaCorp(
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
            _partyValues,
            bytes32(0),
            address(this),
            block.timestamp + 7 days
        );

        ICyberAgreementRegistry(registryAddress).signContractFor(deployer, agreementId, _partyValues[1], signature, false, "");

        ICyberAgreementRegistry(registryAddress).signContractWithEscrow(
            metaDAOOfficer.eoa,
            agreementId,
            _partyValues[0],
            metaDAOSignatureHash,
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
            metaDAOOfficer.eoa,
            meetingNotesId,
            meetingNotesPartyValues[0],
            metaDAOSignatureHash,
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



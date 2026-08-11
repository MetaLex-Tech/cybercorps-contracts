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
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/ICyberCorpSingleFactory.sol";
import "./interfaces/IDealManagerFactory.sol";
import "./interfaces/IDealManager.sol";
import "./interfaces/IRoundManagerFactory.sol";
import {IRoundManager as IRoundManagerInterface} from "./interfaces/IRoundManager.sol";
import "./interfaces/ILedgerEntryToken.sol";
import "./CyberCorpConstants.sol";
import "./storage/LedgerEntryTokenStorage.sol";
import {CyberCertData as RM_CyberCertData} from "./storage/RoundManagerStorage.sol";
import {Round, RoundType, RoundLib} from "./libs/RoundLib.sol";

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

library PumpCorpFactoryLib {
    bytes32 constant FACTORY_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant OFFICER_TYPEHASH = keccak256(
        "CompanyOfficer(address eoa,string name,string contact,string title)"
    );
    bytes32 constant CERT_DATA_TYPEHASH = keccak256(
        "CyberCertData(string name,string symbol,string uri,uint8 securityClass,uint8 securitySeries,address extension,string[] defaultLegend)"
    );
    bytes32 constant ROUND_SUPPLEMENTAL_TYPEHASH = keccak256(
        "RoundSupplementalData(bytes32 corpSalt,address companyPayable,bool publicRound,bool allowTimedOffers,bool restrictEndTimeReduction,CompanyOfficer officer,string companyName,string companyType,string companyJurisdiction,string companyContactDetails,string defaultDisputeResolution,bytes[] extensionData,string[] roundPartyValues,string[] legalDetails,CyberCertData[] certData,address[] conditionAddresses)CompanyOfficer(address eoa,string name,string contact,string title)CyberCertData(string name,string symbol,string uri,uint8 securityClass,uint8 securitySeries,address extension,string[] defaultLegend)"
    );

    /// @notice EIP-712 helper for encoding an array of addresses
    /// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#definition-of-encodedata
    function hashAddresses(address[] memory addrs) internal pure returns (bytes32) {
        bytes32[] memory padded = new bytes32[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            padded[i] = bytes32(uint256(uint160(addrs[i])));
        }
        return keccak256(abi.encodePacked(padded));
    }

    function hashStringArray(string[] memory data) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            hashes[i] = keccak256(bytes(data[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashBytesArray(bytes[] memory data) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            hashes[i] = keccak256(data[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashCertData(RM_CyberCertData memory cd) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            CERT_DATA_TYPEHASH,
            keccak256(bytes(cd.name)),
            keccak256(bytes(cd.symbol)),
            keccak256(bytes(cd.uri)),
            cd.securityClass,
            cd.securitySeries,
            cd.extension,
            hashStringArray(cd.defaultLegend)
        ));
    }

    function hashCertDataArray(RM_CyberCertData[] memory data) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            hashes[i] = hashCertData(data[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }
}

contract PumpCorpFactory is UUPSUpgradeable, BorgAuthACL {
    using Strings for string;
    using RoundLib for Round;
    error InvalidSalt();
    error RoundManagerAlreadyExists();
    error GlobalOrPartyValuesMismatch();
    error InvalidMetadataSignature();

    address public registryAddress;
    address public issuanceManagerFactory;
    address public cyberCorpSingleFactory;
    address public dealManagerFactory;
    address public roundManagerFactory;
    address public uriBuilder;
    address public lexchexAuth;

    // adjust storage gap based on new variable
    uint256[42] private __gap;

    struct CyberCertData {
        string name;
        string symbol;
        string uri;
        SecurityClass securityClass;
        SecuritySeries securitySeries;
        address extension;
        string[] defaultLegend;
    }

    event CyberCorpDeployed(
        address indexed cyberCorp,
        address indexed auth,
        address indexed issuanceManager,
        address dealManager,
        string cyberCORPName,
        string cyberCORPType,
        string cyberCORPContactDetails,
        string cyberCORPJurisdiction,
        string defaultDisputeResolution,
        address _companyPayable
    );

    event DealManagerFactoryUpdated(
        address indexed dealManagerFactory,
        address oldDealFactory
    );

    event RoundManagerDeployed(
        address indexed cyberCorp,
        address indexed roundManager
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

    event RoundManagerFactoryUpdated(
        address indexed roundManagerFactory,
        address oldRoundManagerFactory
    );

    event UriBuilderUpdated(
        address indexed uriBuilder,
        address oldUriBuilder
    );

    event RegistryAddressUpdated(
        address indexed registryAddress,
        address oldRegistryAddress
    );

    event LexchexAuthUpdated(address indexed lexchexAuth, address oldLexchexAuth);

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
        // Initialize BorgAuthACL
        __BorgAuthACL_init(_auth);

        registryAddress = _registryAddress;
        issuanceManagerFactory = _issuanceManagerFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        dealManagerFactory = _dealManagerFactory;
        roundManagerFactory = _roundManagerFactory;
        uriBuilder = _uriBuilder;

        // Set default LeXcheX AUTH if not already set
        if (lexchexAuth == address(0)) {
            lexchexAuth = 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2;
        }
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

        // Deploy and initialize RoundManager
        roundManagerAddress = deployAndInitializeRoundManager(salt, cyberCorpAddress);

        // Authorize peripheral contracts for the cyber corp. It is ok to do it here on behalf of the corp
        // because the corp has just been created by us.
        // In contrast, if any of the peripheral contract is being retrofitted to an existing corp,
        // they would have to authorize it themselves for security reasons.

        // Set RoundManager on the corp
        ICyberCorp(cyberCorpAddress).setRoundManager(roundManagerAddress);

        BorgAuth(authAddress).updateRole(issuanceManagerAddress, 99);
        BorgAuth(authAddress).updateRole(dealManagerAddress, 99);
        BorgAuth(authAddress).updateRole(roundManagerAddress, 99);
        BorgAuth(authAddress).setRoleManager(cyberCorpAddress);
        ICyberCorp(cyberCorpAddress).activateBoardGovernance();

        emit CyberCorpDeployed(
            cyberCorpAddress,
            authAddress,
            issuanceManagerAddress,
            dealManagerAddress,
            companyName,
            companyType,
            companyContactDetails,
            companyJurisdiction,
            defaultDisputeResolution,
            _companyPayable
        );
    }

    function _verifySupplementalSignature(
        bytes32 corpSalt,
        address companyPayable,
        bool publicRound,
        bool allowTimedOffers,
        bool restrictEndTimeReduction,
        CompanyOfficer memory officer,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        bytes[] memory extensionData,
        string[] memory roundPartyValues,
        string[] memory legalDetails,
        RM_CyberCertData[] memory certData,
        address[] memory conditionAddresses,
        bytes memory signature
    ) internal view {
        bytes32 domainSep = keccak256(abi.encode(
            PumpCorpFactoryLib.FACTORY_DOMAIN_TYPEHASH,
            keccak256(bytes("PumpCorpFactory")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
        bytes32 officerHash = keccak256(abi.encode(
            PumpCorpFactoryLib.OFFICER_TYPEHASH,
            officer.eoa,
            keccak256(bytes(officer.name)),
            keccak256(bytes(officer.contact)),
            keccak256(bytes(officer.title))
        ));
        bytes32 structHash = keccak256(abi.encode(
            PumpCorpFactoryLib.ROUND_SUPPLEMENTAL_TYPEHASH,
            corpSalt,
            companyPayable,
            publicRound,
            allowTimedOffers,
            restrictEndTimeReduction,
            officerHash,
            keccak256(bytes(companyName)),
            keccak256(bytes(companyType)),
            keccak256(bytes(companyJurisdiction)),
            keccak256(bytes(companyContactDetails)),
            keccak256(bytes(defaultDisputeResolution)),
            PumpCorpFactoryLib.hashBytesArray(extensionData),
            PumpCorpFactoryLib.hashStringArray(roundPartyValues),
            PumpCorpFactoryLib.hashStringArray(legalDetails),
            PumpCorpFactoryLib.hashCertDataArray(certData),
            PumpCorpFactoryLib.hashAddresses(conditionAddresses)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        if (ECDSA.recover(digest, signature) != officer.eoa) revert InvalidMetadataSignature();
    }

    // TODO WIP: currently not in use. Will need metasig support
    function deployCyberCorpAndCreateOffer(
        uint256 salt,
        string memory companyName,
        string memory companyType,
        string memory companyJurisdiction,
        string memory companyContactDetails,
        string memory defaultDisputeResolution,
        address _companyPayable,
        CompanyOfficer memory _officer,
        CyberCertData[] memory _certData,
        bytes32 _templateId,
        address paymentToken,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[][] memory _partyValues,
        bytes memory signature,
        CertificateDetails[] memory _details,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
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
        //create bytes32 salt
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        //set this officer's eoa to the sender
        _officer.eoa = msg.sender;

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

        certPrinterAddress = new address[](_certData.length);

        for (uint256 i = 0; i < _certData.length; i++) {
            ILedgerEntryToken certPrinter = ILedgerEntryToken(
                IIssuanceManager(issuanceManagerAddress).createCertPrinter(
                    _certData[i].defaultLegend,
                    string.concat(companyName, " ", _certData[i].name),
                    _certData[i].symbol,
                    _certData[i].uri,
                    _certData[i].securityClass,
                    _certData[i].securitySeries,
                    _certData[i].extension
                )
            );
            certPrinterAddress[i] = address(certPrinter);
        }

        // Create and sign deal
        certIds = new uint256[](_certData.length);
        (id, certIds) = IDealManager(dealManagerAddress).proposeAndSignDeal(
            certPrinterAddress,
            paymentToken,
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

    function deployCyberCorpAndCreateRoundFor(
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
        bytes memory metadataSignature,
        RoundType roundType,
        address[] memory conditions,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        uint256 startTime,
        uint256 endTime,
        bool publicRound,
        bool allowTimedOffers,
        bool restrictEndTimeReduction
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
        // Validation

        //  share the same partyFields structures as following:
        if (roundPartyValues.length < 2
            || !roundPartyValues[0].equal(_officer.name)
            || roundPartyValues[1].parseAddress() != _officer.eoa
        ) {
            revert GlobalOrPartyValuesMismatch();
        }

        // Create corp

        //create bytes32 salt
        bytes32 corpSalt = keccak256(abi.encodePacked(salt));

        _verifySupplementalSignature(
            corpSalt,
            _companyPayable,
            publicRound,
            allowTimedOffers,
            restrictEndTimeReduction,
            _officer,
            companyName,
            companyType,
            companyJurisdiction,
            companyContactDetails,
            defaultDisputeResolution,
            extensionData,
            roundPartyValues,
            legalDetails,
            certData,
            conditions,
            metadataSignature
        );

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

        // Create round with provided round type using RoundLib
        {
            Round memory draft = RoundLib
                .draft()
                .setTickets(
                    seriesType,
                    roundType,
                    publicRound,
                    allowTimedOffers,
                    restrictEndTimeReduction,
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
                    _officer.eoa, // ensure only who signs the escrowedsignature can be the owner of the cybercorp
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

    /// @notice Deploy, initialize and grant LeXCheX access to a new RoundManager for the given cyber corp
    /// @dev For security, the cyber corp is expected to authorize the created RoundManager itself
    function deployAndInitializeRoundManager(bytes32 salt, address cyberCorpAddress) internal returns (address) {
        if (ICyberCorp(cyberCorpAddress).roundManager() != address(0)) {
            revert RoundManagerAlreadyExists();
        }

        address roundManagerAddress = IRoundManagerFactory(roundManagerFactory).deployRoundManager(salt);

        // Zero-out fees for this instance
        //IRoundManagerFactory(roundManagerFactory).setInstanceFeeOverride(roundManagerAddress, true, 0);

        // Initialize RoundManager
        IRoundManagerInit(roundManagerAddress).initialize(
            address(BorgAuthACL(cyberCorpAddress).AUTH()),
            cyberCorpAddress,
            registryAddress,
            ICyberCorpLocal(cyberCorpAddress).issuanceManager(),
            roundManagerFactory
        );

        // Add newly created RoundManager as OWNER in LeXcheX AUTH
        if (lexchexAuth != address(0)) {
            BorgAuth(lexchexAuth).updateRole(
                roundManagerAddress,
                BorgAuth(lexchexAuth).OWNER_ROLE()
            );
        }

        emit RoundManagerDeployed(
            cyberCorpAddress,
            roundManagerAddress
        );

        return roundManagerAddress;
    }

    function setIssuanceManagerFactory(
        address _issuanceManagerFactory
    ) external onlyOwner {
        address oldIssuanceFactory = issuanceManagerFactory;
        issuanceManagerFactory = _issuanceManagerFactory;
        emit IssuanceManagerFactoryUpdated(
            issuanceManagerFactory,
            oldIssuanceFactory
        );
    }

    function setCyberCorpSingleFactory(
        address _cyberCorpSingleFactory
    ) external onlyOwner {
        address oldCyberCorpFactory = cyberCorpSingleFactory;
        cyberCorpSingleFactory = _cyberCorpSingleFactory;
        emit CyberCorpSingleFactoryUpdated(
            cyberCorpSingleFactory,
            oldCyberCorpFactory
        );
    }

    function setRegistryAddress(
        address _registryAddress
    ) external onlyOwner {
        address old = registryAddress;
        registryAddress = _registryAddress;
        emit RegistryAddressUpdated(
            registryAddress,
            old
        );
    }

    function setDealManagerFactory(
        address _dealManagerFactory
    ) external onlyOwner {
        address oldDealFactory = dealManagerFactory;
        dealManagerFactory = _dealManagerFactory;
        emit DealManagerFactoryUpdated(dealManagerFactory, oldDealFactory);
    }

    function setRoundManagerFactory(
        address _roundManagerFactory
    ) external onlyOwner {
        address oldRoundManagerFactory = roundManagerFactory;
        roundManagerFactory = _roundManagerFactory;
        emit RoundManagerFactoryUpdated(
            roundManagerFactory,
            oldRoundManagerFactory
        );
    }

    function setUriBuilder(address _uriBuilder) external onlyOwner {
        address old = uriBuilder;
        uriBuilder = _uriBuilder;
        emit UriBuilderUpdated(_uriBuilder, old);
    }

    function setLexchexAuth(address _lexchexAuth) external onlyOwner {
        address old = lexchexAuth;
        lexchexAuth = _lexchexAuth;
        emit LexchexAuthUpdated(lexchexAuth, old);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}

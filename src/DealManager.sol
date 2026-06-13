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

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IIssuanceManager.sol";
import "./libs/LexScroWLite.sol";
import "./libs/auth.sol";
import "./storage/DealManagerStorage.sol";
import "./storage/DealManagerFactoryStorage.sol";
import "./storage/BorgAuthStorage.sol";
import "./storage/SecondaryTradeStorage.sol";
import "./interfaces/ICyberCorp.sol";
import "./interfaces/IDealManagerFactory.sol";
import "./interfaces/ICyberCertPrinter.sol";
import "./interfaces/ICyberAgreementRegistry.sol";

/// @title DealManager
/// @notice Manages the lifecycle of deals between parties, including creation, signing, payment, and finalization for a CyberCorp
/// @dev Implements UUPS upgradeable pattern and integrates with BorgAuth for access control
contract DealManager is Initializable, BorgAuthACL, LexScroWLite, UUPSUpgradeable, ReentrancyGuard {
    using DealManagerStorage for DealManagerStorage.DealManagerData;
    using SafeERC20 for IERC20;

    string public constant DEPLOY_VERSION = "4"; // For version-tracking on all deployment and future upgrades

    /// @notice Certificate data structure for creating new certificates
    struct CyberCertData {
        string name;
        string symbol;
        string uri;
        SecurityClass securityClass;
        SecuritySeries securitySeries;
        address extension;
        string[] defaultLegend;
    }

    error ZeroAddress();
    error CounterPartyValueMismatch();
    error AgreementConditionsNotMet();
    error DealNotPending();
    error PartyValuesLengthMismatch();
    error ConditionAlreadyExists();
    error ConditionDoesNotExist();
    error NotUpgradeFactory();
    error DealNotExpired();
    error NotRefImplementation();
    // Secondary trade errors
    error OfferNotAvailable();
    error OfferExpired();
    error OfferBelowMinThreshold();
    error IntegratorNotWhitelisted();
    error PartialFillBelowMinThreshold();
    error UnitsExceedOffer();
    error NotOfferor();
    error MissingCertPrinter();
    error NotPartyToAgreement();
    error OfferAlreadyExists();

    /// @notice Emitted when a new deal is proposed
    /// @param agreementId Unique identifier for the agreement
    /// @param certAddress Address of the certificate contract
    /// @param certId ID of the certificate
    /// @param paymentToken Address of the token used for payment
    /// @param paymentAmount Amount to be paid
    /// @param templateId ID of the template used for the agreement
    /// @param corp Address of the CyberCorp
    /// @param dealRegistry Address of the CyberAgreementRegistry
    /// @param parties Array of party addresses involved in the deal
    /// @param conditions Array of condition contract addresses
    /// @param hasSecret Whether the deal requires a secret for finalization
    event DealProposed(
        bytes32 indexed agreementId,
        address[] certAddress,
        uint256[] certId,
        address paymentToken,
        uint256 paymentAmount,
        bytes32 templateId,
        address corp,
        address dealRegistry,
        address[] parties,
        address[] conditions,
        bool hasSecret
    );

    event DealFinalized(
        bytes32 indexed agreementId,
        address indexed signer,
        address indexed corp,
        address dealRegistry,
        bool fillUnallocated
    );
    // Secondary trade events
    event OfferPosted(bytes32 indexed offerId, address indexed offeror, OfferSide side, uint256 units, uint256 consideration);
    event OfferCancelled(bytes32 indexed offerId, address indexed offeror);
    event OfferAccepted(bytes32 indexed offerId, bytes32 indexed settlementAgreementId, address indexed acceptor, uint256 units);
    event SecondaryDealFinalized(bytes32 indexed agreementId, address seller, address buyer, uint256 consideration);
    event MinTradeThresholdSet(uint256 minUnits, uint256 minConsideration, address setter);


    /// @notice Maps agreement IDs to arrays of counter party values for closed deals.
    mapping(bytes32 => string[]) public counterPartyValues;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the DealManager contract
    /// @dev Sets up the contract with required addresses and initializes parent contracts
    /// @param _auth Address of the BorgAuth contract
    /// @param _corp Address of the CyberCorp
    /// @param _dealRegistry Address of the CyberAgreementRegistry
    /// @param _issuanceManager Address of the CyberCorp's issuance manager
    function initialize(address _auth, address _corp, address _dealRegistry, address _issuanceManager, address _upgradeFactory) public initializer {
        __BorgAuthACL_init(_auth);
        
        if (_corp == address(0)) revert ZeroAddress();
        if (_dealRegistry == address(0)) revert ZeroAddress();
        if (_issuanceManager == address(0)) revert ZeroAddress();

        // Set storage values
        DealManagerStorage.setIssuanceManager(_issuanceManager);

        // Initialize LexScroWLite core addresses
        __LexScroWLite_init(_corp, _dealRegistry);
        DealManagerStorage.setUpgradeFactory(_upgradeFactory);
    }

    /// @notice Proposes a new deal
    /// @dev Creates a new agreement and certificate for the deal
    /// @param _certPrinterAddress Array of certificate printer addresses
    /// @param _paymentToken Address of the token used for payment
    /// @param _paymentAmount Amount to be paid
    /// @param _templateId ID of the agreement template to use
    /// @param _salt Random value for unique agreement ID generation
    /// @param _globalValues Array of global values for the agreement, must match the template
    /// @param _parties Array of party addresses
    /// @param _certDetails Details of the certificate to be created
    /// @param _partyValues Array of party-specific values, must match the template
    /// @param conditions Array of condition contract addresses
    /// @param secretHash Hash of the secret required for finalization (if any)
    /// @param expiry Timestamp when the deal expires
    /// @return agreementId Unique identifier for the agreement
    /// @return certIds IDs of the created certificate
    function proposeDeal(
        address[] memory _certPrinterAddress, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        uint256 _salt,
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails[] memory _certDetails,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public onlyOwner returns (bytes32 agreementId, uint256[] memory certIds) {
        agreementId = ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).createContract(_templateId, _salt, _globalValues, _parties, _partyValues, secretHash, address(this), expiry);
       
        Token[] memory corpAssets = new Token[](_certDetails.length);
        certIds = new uint256[](_certDetails.length);
        for(uint256 i = 0; i < _certDetails.length; i++) {
            certIds[i] = DealManagerStorage.getIssuanceManager().createCert(_certPrinterAddress[i], address(this), _certDetails[i]);
            corpAssets[i] = Token(TokenType.ERC721, _certPrinterAddress[i], certIds[i], 1, false);
        }

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount, true); // Will be used as fee token

        Escrow memory newEscrow = Escrow({
            agreementId: agreementId,
            counterParty: _parties[1],
            corpAssets: corpAssets,
            buyerAssets: buyerAssets,
            signature: "",
            expiry: expiry,
            status: EscrowStatus.PENDING
        });
        
        LexScrowStorage.setEscrow(agreementId, newEscrow);

        //set conditions
        for(uint256 i = 0; i < conditions.length; i++) {
            LexScrowStorage.addConditionToEscrow(agreementId, ICondition(conditions[i]));
        }

        emit DealProposed(
            agreementId,
            _certPrinterAddress,
            certIds,
            _paymentToken,
            _paymentAmount,
            _templateId,
            LexScrowStorage.getCorp(),
            LexScrowStorage.getDealRegistry(),
            _parties,
            conditions,
            secretHash > 0
        );
    }

    /// @notice Proposes and signs a deal in one transaction
    /// @dev Combines deal proposal and initial signature
    /// @param _certPrinterAddress Array of certificate printer addresses
    /// @param _paymentToken Address of the token used for payment
    /// @param _paymentAmount Amount to be paid
    /// @param _templateId ID of the agreement template to use
    /// @param _salt Random value for unique agreement ID generation
    /// @param _globalValues Array of global values for the agreement, must match the template
    /// @param _parties Array of party addresses
    /// @param _certDetails Details of the certificate to be created
    /// @param proposer Address of the deal proposer
    /// @param signature Signature of the proposer
    /// @param _partyValues Array of party-specific values, must match the template
    /// @param conditions Array of condition contract addresses
    /// @param secretHash Hash of the secret required for finalization (if any)
    /// @param expiry Timestamp when the deal expires
    /// @return agreementId Unique identifier for the agreement
    /// @return certIds IDs of the created certificate
    function proposeAndSignDeal(
        address[] memory _certPrinterAddress, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        uint256 _salt,
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails[] memory _certDetails,
        address proposer,
        bytes memory signature,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public returns (bytes32 agreementId, uint256[] memory certIds) {
        if(_partyValues.length > _parties.length) revert PartyValuesLengthMismatch();
        
        certIds = new uint256[](_certDetails.length);

        (agreementId, certIds) = proposeDeal(_certPrinterAddress, _paymentToken, _paymentAmount, _templateId, _salt, _globalValues, _parties, _certDetails, _partyValues, conditions, secretHash, expiry);
        // NOTE: proposer is expected to be listed as a party in the parties array.
        
        // Update the escrow signature
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        escrow.signature = signature;

        if(_partyValues.length > 1) {
            if(_partyValues[1].length != _partyValues[0].length) revert PartyValuesLengthMismatch();
            DealManagerStorage.setCounterPartyValues(agreementId, _partyValues[1]);
        }
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).signContractFor(proposer, agreementId, _partyValues[0], signature, false, "");
    }

    /// @notice Signs a deal and processes payment
    /// @dev Validates signature and processes payment for the deal
    /// @param signer Address of the signer
    /// @param agreementId Unique identifier for the agreement
    /// @param signature Digital Signature hash of the signer
    /// @param partyValues Array of party-specific values, must match the template
    /// @param _fillUnallocated Whether to fill unallocated slots
    /// @param name Name of the signer
    /// @param secret Secret required for finalization (if any)
    function signDealAndPay(
        address signer,
        bytes32 agreementId,
        bytes memory signature,
        string[] memory partyValues,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) public {
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId)) revert DealVoided();
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isFinalized(agreementId)) revert DealAlreadyFinalized();
        Escrow storage escrow = LexScrowStorage.getEscrow(agreementId);
        if(escrow.status != EscrowStatus.PENDING) revert DealNotPending();
        if(escrow.expiry < block.timestamp) revert DealExpired();

        string[] storage counterPartyCheck = DealManagerStorage.getCounterPartyValues(agreementId);
        if(counterPartyCheck.length > 0) {
            if (keccak256(abi.encode(counterPartyCheck)) != keccak256(abi.encode(partyValues))) revert CounterPartyValueMismatch();
        }
        else {
            DealManagerStorage.setCounterPartyValues(agreementId, partyValues);
        }
        
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated, secret);
        updateEscrow(agreementId, signer, name);
        handleCounterPartyPayment(agreementId);
    }

    /// @notice Signs and finalizes a deal in one transaction
    /// @dev Combines signing, payment, and finalization steps
    /// @param signer Address of the signer
    /// @param agreementId Unique identifier for the agreement
    /// @param partyValues Array of party-specific values, must match the template
    /// @param signature Digital Signature hash of the signer   
    /// @param _fillUnallocated Whether to fill unallocated slots
    /// @param name Name of the signer
    /// @param secret Secret required for finalization (if any)
    function signAndFinalizeDeal(
        address signer,
        bytes32 agreementId,
        string[] memory partyValues,
        bytes memory signature,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) public {
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId)) revert DealVoided();
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isFinalized(agreementId)) revert DealAlreadyFinalized();
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PENDING) revert DealNotPending();

        string[] storage counterPartyCheck = DealManagerStorage.getCounterPartyValues(agreementId);
        if(counterPartyCheck.length > 0) {
            if (keccak256(abi.encode(counterPartyCheck)) != keccak256(abi.encode(partyValues))) revert CounterPartyValueMismatch();
        } else {
            DealManagerStorage.setCounterPartyValues(agreementId, partyValues);
        }

		if (!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).hasSigned(agreementId, signer)) {
            // Not signed in registry yet; enforce local consistency and then sign
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated, secret);
		} else {
            // Already signed in registry; fetch values recorded in the registry and ensure consistency
			string[] memory registryValues = ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).getSignerValues(agreementId, signer);
			if (keccak256(abi.encode(registryValues)) != keccak256(abi.encode(partyValues))) revert CounterPartyValueMismatch();
		}

        updateEscrow(agreementId, signer, name);
        if(!conditionCheck(agreementId)) revert AgreementConditionsNotMet();
        handleCounterPartyPayment(agreementId);
        finalizeDeal(agreementId);
    }

    /// @notice Finalizes a deal
    /// @dev Checks signatures, conditions and finalizes the agreement
    /// @param agreementId Unique identifier for the agreement
    function finalizeDeal(bytes32 agreementId) public nonReentrant {
        address registry = LexScrowStorage.getDealRegistry();
        if (ICyberAgreementRegistry(registry).isVoided(agreementId)) revert DealVoided();
        if (ICyberAgreementRegistry(registry).isFinalized(agreementId)) revert DealAlreadyFinalized();
        if (!ICyberAgreementRegistry(registry).allPartiesSigned(agreementId)) revert DealNotFullySigned();

        if (SecondaryTradeStorage.hasSecondaryEscrow(agreementId)) {
            _requireActiveSecondaryEscrow(SecondaryTradeStorage.getSecondaryEscrow(agreementId));
            ICyberAgreementRegistry(registry).finalizeContract(agreementId);
            _finalizeSecondaryEscrow(agreementId);
        } else {
            if (LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PAID) revert DealNotPaid();
            if (!conditionCheck(agreementId)) revert AgreementConditionsNotMet();
            ICyberAgreementRegistry(registry).finalizeContract(agreementId);
            finalizeEscrow(agreementId);
        }
        emit DealFinalized(
            agreementId,
            msg.sender,
            LexScrowStorage.getCorp(),
            registry,
            false
        );
    }

    /// @notice Voids an expired deal
    /// @dev Voids the certificate and agreement for an expired deal
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function voidExpiredDeal(bytes32 agreementId, address signer, bytes memory signature) public nonReentrant {
        address registry = LexScrowStorage.getDealRegistry();

        if (SecondaryTradeStorage.hasSecondaryEscrow(agreementId)) {
            SecondaryEscrow storage secEscrow = SecondaryTradeStorage.getSecondaryEscrow(agreementId);
            _requireActiveSecondaryEscrow(secEscrow);
            if (block.timestamp <= secEscrow.expiry) revert DealNotExpired();
            ICyberAgreementRegistry(registry).voidContractFor(agreementId, signer, signature);
            _voidSecondaryDeal(agreementId);
        } else {
            Escrow storage deal = LexScrowStorage.getEscrow(agreementId);
            if (block.timestamp <= deal.expiry) revert DealNotExpired();
            ICyberAgreementRegistry(registry).voidContractFor(agreementId, signer, signature);
            for (uint256 i = 0; i < deal.corpAssets.length; i++) {
                if (deal.corpAssets[i].tokenType == TokenType.ERC721) {
                    DealManagerStorage.getIssuanceManager().voidCertificate(
                        deal.corpAssets[i].tokenAddress,
                        deal.corpAssets[i].tokenId
                    );
                }
            }
            if (deal.status == EscrowStatus.PAID)
                // Interaction: payment
                voidAndRefund(agreementId);
            else if (deal.status == EscrowStatus.PENDING)
                // Effect: update status
                voidEscrow(agreementId);
        }
    }

    /// @notice Revokes a pending deal
    /// @dev Can only be called for deals in pending status
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function revokeDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        if(msg.sender != signer) revert CounterPartyValueMismatch();    
        if(LexScrowStorage.getEscrow(agreementId).status == EscrowStatus.PENDING) 
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
        else
            revert DealNotPending();
    }

    /// @notice Signs to void a deal
    /// @dev If the deal is paid, initiates refund process
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function signToVoid(bytes32 agreementId, address signer, bytes memory signature) public nonReentrant {
        // Check: status
        if(msg.sender != signer) revert CounterPartyValueMismatch();

        // Effect: update status
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId) && LexScrowStorage.getEscrow(agreementId).status == EscrowStatus.PAID)
            // Interaction: payment
            voidAndRefund(agreementId);
    }

    /// @notice Refund a voided deal
    /// @dev Use this method to initiate refund if the deal agreement has been voided externally
    /// (e.g. directly to CyberAgreementRegistry without being processed by Deal Manager)
    /// @param agreementId Unique identifier for the agreement
    function refundVoidedDeal(bytes32 agreementId) public nonReentrant {
        // Interaction: Re-sync Deal Manager internal escrow to VOIDED, then refund
        voidAndRefund(agreementId);
    }

    /// @notice Adds a condition to a deal
    /// @dev Can only be called by owner for pending deals
    /// @param agreementId Unique identifier for the agreement
    /// @param condition Address of the condition contract to add
    function addCondition(bytes32 agreementId, address condition) public onlyOwner {
        //make sure the contract is still pending
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PENDING) revert DealNotPending();
        //make sure the condition is not already in the list
        ICondition[] storage conditions = LexScrowStorage.getConditionsByEscrow(agreementId);
        for(uint256 i = 0; i < conditions.length; i++) {
            if(conditions[i] == ICondition(condition)) revert ConditionAlreadyExists();
        }
        LexScrowStorage.addConditionToEscrow(agreementId, ICondition(condition));
    }

    /// @notice Removes a condition from a deal
    /// @dev Can only be called by owner for pending deals
    /// @param agreementId Unique identifier for the agreement
    /// @param index Index of the condition to remove
    function removeConditionAt(bytes32 agreementId, uint256 index) public onlyOwner {
        //make sure the contract is still pending
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PENDING) revert DealNotPending();
        //make sure the condition is in the list
        ICondition[] storage conditions = LexScrowStorage.getConditionsByEscrow(agreementId);
        if(index >= conditions.length) revert ConditionDoesNotExist();

        LexScrowStorage.removeConditionFromEscrow(agreementId, index);
    }

    /// @notice Sets the deal registry address
    /// @dev Can only be called by owner
    /// @param _dealRegistry New deal registry address
    function setDealRegistry(address _dealRegistry) public onlyOwner {
        LexScrowStorage.setDealRegistry(_dealRegistry);
    }

    /// @notice Sets the corporation address
    /// @dev Can only be called by owner
    /// @param _corp New corporation address
    function setCorp(address _corp) public onlyOwner {
        LexScrowStorage.setCorp(_corp);
    }

    /// @notice Sets the issuance manager address
    /// @dev Can only be called by owner
    /// @param _issuanceManager New issuance manager address
    function setIssuanceManager(address _issuanceManager) public onlyOwner {
        DealManagerStorage.setIssuanceManager(_issuanceManager);
    }

    /// @notice Gets the current issuance manager
    /// @return IIssuanceManager The current issuance manager contract
    function issuanceManager() public view returns (IIssuanceManager) {
        return DealManagerStorage.getIssuanceManager();
    }

    /// @notice Gets the counter party values for an agreement
    /// @param agreementId Unique identifier for the agreement
    /// @return string[] Array of counter party values
    function getCounterPartyValues(bytes32 agreementId) public view returns (string[] memory) {
        return DealManagerStorage.getCounterPartyValues(agreementId);
    }


    /// @notice Creates an offer for an existing CyberCorp
    /// @dev Creates certificate printers and proposes a deal without deploying a new CyberCorp
    /// @param _certData Array of certificate data structures
    /// @param _templateId ID of the agreement template to use
    /// @param _globalValues Array of global values for the agreement
    /// @param _parties Array of party addresses
    /// @param _paymentAmount Amount to be paid
    /// @param _partyValues Array of party-specific values
    /// @param signature Digital signature for the deal
    /// @param _details Certificate details for each certificate
    /// @param conditions Array of condition contract addresses
    /// @param secretHash Hash of secret required for finalization
    /// @param expiry Deal expiration timestamp
    /// @param stableAddress Address of the stable token for payment
    /// @param salt Salt value for unique agreement ID generation
    /// @return certPrinterAddress Array of deployed certificate printer addresses
    /// @return id Unique agreement ID
    /// @return certIds Array of certificate IDs created
    function proposeAndSignNewCertsDeal(
        uint256 salt,
        CyberCertData[] memory _certData,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        uint256 _paymentAmount,
        string[][] memory _partyValues,
        bytes memory signature,
        CertificateDetails[] memory _details,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry,
        address stableAddress
    ) external onlyOwner returns (
        address[] memory certPrinterAddress,
        bytes32 id,
        uint256[] memory certIds
    )  {
        // Get company name from the parent CyberCorp
        string memory companyName = ICyberCorp(LexScrowStorage.getCorp()).cyberCORPName();
        
        certPrinterAddress = new address[](_certData.length);
        for (uint256 i = 0; i < _certData.length; i++) {
            ICyberCertPrinter certPrinter = ICyberCertPrinter(
                DealManagerStorage.getIssuanceManager().createCertPrinter(
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
        (id, certIds) = proposeAndSignDeal(
            certPrinterAddress,
            stableAddress,
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

    /// @notice Compute fee based on ticket size
    /// @dev Currently the factory owner (MetaLeX) unilaterally set the fee ratio;
    /// in the future, it could be determined through a governance process.
    /// @return Fee amount
    function computeFee(uint256 size) public override view returns (uint256) {
        return size * IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).getDefaultFeeRatio() / DealManagerFactoryStorage.BASIS_POINTS;
    }

    /// @notice Gets the payable address for the fees
    /// @dev The factory owner (MetaLeX) unilaterally set the payable address
    /// @return Payable address for the fees
    function getPlatformPayable() public override view returns (address) {
        return IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).getPlatformPayable();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Secondary trade — threshold setters
    // ─────────────────────────────────────────────────────────────────────────

    function setMinTradeThreshold(uint256 units, uint256 consideration) external onlyAdmin {
        SecondaryTradeStorage.setMinTradeThreshold(units, consideration);
        emit MinTradeThresholdSet(units, consideration, msg.sender);
    }

    function setDefaultIntegrator(address integrator) external onlyAdmin {
        if (integrator != address(0)) {
            if (!IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).isIntegratorWhitelisted(integrator))
                revert IntegratorNotWhitelisted();
        }
        SecondaryTradeStorage.setDefaultIntegrator(integrator);
    }

    function getOffer(bytes32 offerId) external view returns (Offer memory) {
        return SecondaryTradeStorage.getOffer(offerId);
    }

    function getSecondaryEscrow(bytes32 agreementId) external view returns (SecondaryEscrow memory) {
        return SecondaryTradeStorage.getSecondaryEscrow(agreementId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Secondary trade — offer lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    // TODO implement *For()
    function postOffer(PostOfferParams calldata params) external nonReentrant returns (bytes32 offerId) {
        // validate parameters
        if (params.certPrinter == address(0)) revert MissingCertPrinter();

        // Validate integrator
        address integrator = params.integrator != address(0)
            ? params.integrator
            : SecondaryTradeStorage.getDefaultIntegrator();
        if (integrator != address(0)) {
            if (!IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).isIntegratorWhitelisted(integrator))
                revert IntegratorNotWhitelisted();
        }

        // Validate min threshold
        uint256 minUnits = SecondaryTradeStorage.getMinTradeUnits();
        if (minUnits > 0 && params.units < minUnits) revert OfferBelowMinThreshold();
        uint256 minConsid = SecondaryTradeStorage.getMinTradeConsideration();
        if (minConsid > 0 && params.consideration < minConsid) revert OfferBelowMinThreshold();

        // Generate offer ID deterministically — DealManager-internal key, not a registry record
        offerId = keccak256(abi.encode(msg.sender, params.templateId, params.salt));
        if (SecondaryTradeStorage.getOffer(offerId).offeror != address(0)) revert OfferAlreadyExists();

        // Evaluate offeror-side threshold conditions
        bytes memory offerIdData = abi.encode(offerId);
        for (uint256 i = 0; i < params.thresholdConditions.length; i++) {
            if (!ICondition(params.thresholdConditions[i]).checkCondition(address(this), msg.sig, offerIdData))
                revert AgreementConditionsNotMet();
        }

        if (params.side == OfferSide.SELL) {
            // Reserve units on the seller's cert
            ICyberCertPrinter(params.certPrinter).reserveUnits(params.tokenId, params.units);
        } else {
            // BID: pull consideration directly into contract custody
            IERC20(params.paymentToken).safeTransferFrom(msg.sender, address(this), params.consideration);
        }

        // Store offer record
        SecondaryTradeStorage.setOffer(offerId, Offer({
            spvAddress: LexScrowStorage.getCorp(),
            offeror: msg.sender,
            side: params.side,
            certPrinter: params.certPrinter,
            tokenId: params.tokenId,
            units: params.units,
            paymentToken: params.paymentToken,
            consideration: params.consideration,
            exemptionPathway: params.exemptionPathway,
            validUntil: params.validUntil,
            counterpartyRestrictions: params.counterpartyRestrictions,
            additionalTerms: params.additionalTerms,
            integrator: integrator,
            status: OfferStatus.LIVE,
            unitsAccepted: 0,
            paymentAccepted: 0,
            unitsFinalized: 0,
            offerId: offerId,
            templateId: params.templateId,
            salt: params.salt,
            globalValues: params.globalValues,
            offerorPartyValues: params.offerorPartyValues,
            offerorAgreementSig: params.offerorAgreementSig,
            openEndorsementSig: params.openEndorsementSig,
            buyerName: params.side == OfferSide.BUY ? params.buyerName : "",
            buyerHostingMode: params.side == OfferSide.BUY ? params.buyerHostingMode : 0,
            adminMultisig: params.side == OfferSide.BUY ? params.adminMultisig : address(0),
            settlementAgreementIds: new bytes32[](0)
        }));

        emit OfferPosted(offerId, msg.sender, params.side, params.units, params.consideration);
    }

    // TODO implement *For()
    /// @notice Cancels a non-terminal offer and returns its uncommitted assets to the offeror
    /// @dev Only the free pool (uncommitted units / consideration) is refunded/released. Settlements already
    /// accepted stay ACCEPTED and resolve on their own — finalized normally, or voided via the two-party
    /// voidSecondaryAgreement / expiry path; their assets stay in DealManager custody until then.
    /// @param offerId Offer to cancel
    function cancelOffer(bytes32 offerId) external nonReentrant {
        Offer storage offer = SecondaryTradeStorage.getOffer(offerId);
        if (offer.offeror != msg.sender) revert NotOfferor();
        if (_isOfferTerminal(offer.status)) revert OfferNotAvailable();

        offer.status = OfferStatus.CANCELLED;

        // Return only the free pool; committed lots stay reserved / in custody and are consumed at
        // finalize or released/refunded when their settlement is voided.
        if (offer.side == OfferSide.SELL) {
            // Release only the uncommitted units; in-flight settlement lots are consumed at finalize or released at void
            uint256 freeUnits = offer.units - offer.unitsAccepted;
            if (freeUnits > 0) {
                ICyberCertPrinter(offer.certPrinter).releaseUnits(offer.tokenId, freeUnits);
            }
        } else {
            // BUY: refund only the uncommitted portion; paymentAccepted tracks what's committed to
            // active and finalized settlements (mirrors unitsAccepted: decrements on void only)
            uint256 freePayment = offer.consideration - offer.paymentAccepted;
            if (freePayment > 0) {
                IERC20(offer.paymentToken).safeTransfer(offer.offeror, freePayment);
            }
        }

        emit OfferCancelled(offerId, msg.sender);
    }

    // TODO implement *For()
    function acceptOffer(AcceptOfferParams calldata params) external nonReentrant returns (bytes32 settlementAgreementId) {
        Offer storage offer = SecondaryTradeStorage.getOffer(params.offerId);

        if (offer.status != OfferStatus.LIVE && offer.status != OfferStatus.PARTIALLY_ACCEPTED) revert OfferNotAvailable();
        if (block.timestamp > offer.validUntil) revert OfferExpired();

        if (params.units == 0) revert PartialFillBelowMinThreshold();
        uint256 remainingUnits = offer.units - offer.unitsAccepted;
        if (params.units > remainingUnits) revert UnitsExceedOffer();

        uint256 minUnits = SecondaryTradeStorage.getMinTradeUnits();
        if (minUnits > 0 && params.units < minUnits) revert PartialFillBelowMinThreshold();

        // Create fully-signed settlement agreement via registry.
        // settlementAgreementIds.length is a push-only monotonic nonce: unique per acceptance even if prior
        // settlements are later voided (which decrements unitsAccepted but never shrinks the array).
        address registry = LexScrowStorage.getDealRegistry();
        bytes32 settlementSalt = keccak256(abi.encodePacked(offer.salt, offer.settlementAgreementIds.length));
        address[] memory settlementParties = new address[](2);
        settlementParties[0] = offer.offeror;
        settlementParties[1] = msg.sender;
        string[][] memory settlementPartyValues = new string[][](2);
        settlementPartyValues[0] = offer.offerorPartyValues;
        settlementPartyValues[1] = params.acceptorPartyValues;
        settlementAgreementId = ICyberAgreementRegistry(registry).createContract(
            offer.templateId,
            uint256(settlementSalt),
            offer.globalValues,
            settlementParties,
            settlementPartyValues,
            bytes32(0),
            address(this),
            offer.validUntil
        );
        // Offeror: DealManager (finalizer) attests commitment via signContractWithEscrow.
        // The registry does not verify escrowSigner's EIP-712 sig here; the offeror's
        // commitment is evidenced by their postOffer() tx and stored offerorAgreementSig.
        ICyberAgreementRegistry(registry).signContractWithEscrow(
            offer.offeror, settlementAgreementId, offer.offerorPartyValues,
            offer.offerorAgreementSig, false, ""
        );
        // Acceptor: proper EIP-712 sig verified by the registry.
        ICyberAgreementRegistry(registry).signContractFor(
            msg.sender, settlementAgreementId, params.acceptorPartyValues,
            params.acceptorAgreementSig, false, ""
        );

        // Resolve cert printer, tokenId, buyer, endorser, and endorsement sig per offer side;
        address certPrinter;
        uint256 tokenId;
        address buyer;
        address endorser;
        bytes memory endorsementSig;

        if (offer.side == OfferSide.SELL) {
            certPrinter = offer.certPrinter;
            tokenId = offer.tokenId;
            buyer = msg.sender;
            endorser = offer.offeror;
            endorsementSig = offer.openEndorsementSig;
        } else {
            certPrinter = offer.certPrinter;
            tokenId = params.sellerTokenId;
            buyer = offer.offeror;
            endorser = msg.sender;
            endorsementSig = params.openEndorsementSig;
            // Reserve units on the seller's cert at acceptance (bid flow)
            ICyberCertPrinter(certPrinter).reserveUnits(tokenId, params.units);
        }

        // Materialize open endorsement on seller's Ledger Entry Token
        DealManagerStorage.getIssuanceManager().attachOpenEndorsement(
            certPrinter,
            tokenId,
            endorser,
            buyer,
            endorsementSig,
            settlementAgreementId
        );

        // Compute pro-rata consideration for partial fills
        uint256 partialConsideration = offer.units > 0
            ? offer.consideration * params.units / offer.units
            : 0;

        // Build deal metadata for IssuanceManager.secondaryTransfer
        string memory buyerName;
        uint8 buyerHostingMode;
        address adminMultisig;
        if (offer.side == OfferSide.BUY) {
            buyerName = offer.buyerName;
            buyerHostingMode = offer.buyerHostingMode;
            adminMultisig = offer.adminMultisig;
        } else {
            buyerName = params.buyerName;
            buyerHostingMode = params.buyerHostingMode;
            adminMultisig = params.adminMultisig;
        }
        bytes memory dealMetadata = abi.encode(
            certPrinter,
            tokenId,
            params.units,
            buyer,
            buyerName,
            buyerHostingMode,
            adminMultisig,
            offer.exemptionPathway,
            settlementAgreementId
        );

        // Fund the settlement escrow.
        // BUY: funds are already in contract from postOffer(); no token movement needed.
        // SELL: pull the buyer's payment directly into contract.
        if (offer.side == OfferSide.SELL) {
            IERC20(offer.paymentToken).safeTransferFrom(buyer, address(this), partialConsideration);
        }
        SecondaryTradeStorage.setSecondaryEscrow(settlementAgreementId, SecondaryEscrow({
            counterparty: msg.sender,
            paymentToken: offer.paymentToken,
            paymentAmount: partialConsideration,
            units: params.units,
            expiry: offer.validUntil,
            status: SecondaryEscrowStatus.ACCEPTED,
            feeDestination: offer.integrator,
            offerId: params.offerId,
            tokenId: tokenId,
            dealMetadata: dealMetadata
        }));
        emit DealPaidAt(settlementAgreementId, LexScrowStorage.getDealRegistry(), block.timestamp);

        // Record settlement for buyer-facing threshold condition lookup
        offer.settlementAgreementIds.push(settlementAgreementId);

        // Update offer accounting and fill state
        offer.unitsAccepted += params.units;
        offer.paymentAccepted += partialConsideration;
        if (offer.unitsAccepted >= offer.units) {
            offer.status = OfferStatus.FULLY_ACCEPTED;
        } else {
            offer.status = OfferStatus.PARTIALLY_ACCEPTED;
        }

        emit OfferAccepted(params.offerId, settlementAgreementId, msg.sender, params.units);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Secondary trade — internals
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Terminal offer states: immutable, not cancellable, and never restored by a void
    function _isOfferTerminal(OfferStatus status) internal pure returns (bool) {
        return status == OfferStatus.CANCELLED || status == OfferStatus.FINALIZED;
    }

    /// @dev Derives the settlement's seller and buyer from the offer side: the offeror is the
    /// seller on SELL offers and the buyer on BUY offers; the counterparty (acceptor) is the other.
    function _settlementParties(Offer storage offer, SecondaryEscrow storage secEscrow)
        internal view returns (address seller, address buyer)
    {
        return offer.side == OfferSide.SELL
            ? (offer.offeror, secEscrow.counterparty)
            : (secEscrow.counterparty, offer.offeror);
    }

    /// @dev Reverts unless the settlement escrow is active (ACCEPTED). Terminal states get
    /// explicit errors so callers never act on an already-settled escrow.
    function _requireActiveSecondaryEscrow(SecondaryEscrow storage secEscrow) internal view {
        if (secEscrow.status == SecondaryEscrowStatus.FINALIZED) revert DealAlreadyFinalized();
        if (secEscrow.status == SecondaryEscrowStatus.VOIDED) revert DealVoided();
        if (secEscrow.status != SecondaryEscrowStatus.ACCEPTED) revert DealNotPaid();
    }

    function _finalizeSecondaryEscrow(bytes32 agreementId) internal {
        SecondaryEscrow storage secEscrow = SecondaryTradeStorage.getSecondaryEscrow(agreementId);
        Offer storage offer = SecondaryTradeStorage.getOffer(secEscrow.offerId);

        _requireActiveSecondaryEscrow(secEscrow);
        if (block.timestamp > secEscrow.expiry) revert DealExpired();
        if (!conditionCheck(agreementId)) revert AgreementConditionsNotMet();

        // Effect: mark finalized before external calls
        secEscrow.status = SecondaryEscrowStatus.FINALIZED;
        offer.unitsFinalized += secEscrow.units;
        // All offered units settled: the offer reaches its FINALIZED terminal state. CANCELLED
        // stays sticky — both are terminal, and cancellation is the offeror's recorded intent.
        if (offer.status != OfferStatus.CANCELLED && offer.unitsFinalized == offer.units) {
            offer.status = OfferStatus.FINALIZED;
        }
        emit DealFinalizedAt(agreementId, LexScrowStorage.getDealRegistry(), block.timestamp);

        (address seller, address buyer) = _settlementParties(offer, secEscrow);
        uint256 fee = computeFee(secEscrow.paymentAmount);
        uint256 toSeller = secEscrow.paymentAmount - fee;

        if (toSeller > 0) {
            IERC20(secEscrow.paymentToken).safeTransfer(seller, toSeller);
        }

        if (fee > 0) {
            emit FeeDistributed(agreementId, secEscrow.paymentToken, fee);
            address feeDestination = secEscrow.feeDestination;
            if (feeDestination != address(0)) {
                uint256 integratorRatio = IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).getIntegratorFeeRatio();
                uint256 integratorFee = fee * integratorRatio / DealManagerFactoryStorage.BASIS_POINTS;
                uint256 platformFee = fee - integratorFee;
                if (integratorFee > 0) IERC20(secEscrow.paymentToken).safeTransfer(feeDestination, integratorFee);
                if (platformFee > 0) IERC20(secEscrow.paymentToken).safeTransfer(getPlatformPayable(), platformFee);
            } else {
                IERC20(secEscrow.paymentToken).safeTransfer(getPlatformPayable(), fee);
            }
        }

        // Execute ownership change: void/decrement seller cert + mint buyer cert;
        // also consumes this lot's reserved units as part of the cert mutation
        DealManagerStorage.getIssuanceManager().secondaryTransfer(secEscrow.dealMetadata);

        emit SecondaryDealFinalized(agreementId, seller, buyer, secEscrow.paymentAmount);
    }

    function _voidSecondaryDeal(bytes32 agreementId) internal {
        SecondaryEscrow storage secEscrow = SecondaryTradeStorage.getSecondaryEscrow(agreementId);
        Offer storage offer = SecondaryTradeStorage.getOffer(secEscrow.offerId);

        // Update accounting counters
        offer.unitsAccepted -= secEscrow.units;
        offer.paymentAccepted -= secEscrow.paymentAmount;

        // Release this lot's unit reservation.
        // BUY: reserved at acceptance for this settlement only — always release.
        // SELL: reserved at postOffer for the whole offer — release only when the offer is CANCELLED
        // (the lot can never be re-accepted); otherwise the lot returns to the offer's free pool
        // and stays reserved.
        if (offer.side == OfferSide.BUY || offer.status == OfferStatus.CANCELLED) {
            ICyberCertPrinter(offer.certPrinter).releaseUnits(secEscrow.tokenId, secEscrow.units);
        }

        // Restore offer status (keep terminal offers closed)
        if (!_isOfferTerminal(offer.status)) {
            offer.status = offer.unitsAccepted == 0 ? OfferStatus.LIVE : OfferStatus.PARTIALLY_ACCEPTED;
        }

        bool wasAccepted = secEscrow.status == SecondaryEscrowStatus.ACCEPTED;
        secEscrow.status = SecondaryEscrowStatus.VOIDED;
        emit DealVoidedAt(agreementId, LexScrowStorage.getDealRegistry(), block.timestamp);
        if (wasAccepted) {
            // Refund mirrors the reservation logic above, with sides swapped.
            // SELL: payment was pulled per-settlement at acceptOffer — always refund the buyer.
            // BUY: payment came from the offer's pool at postOffer — refund only when the offer is
            // CANCELLED (the lot can never be re-accepted); otherwise the payment returns to the
            // offer's free pool and stays in custody.
            if (offer.side == OfferSide.SELL || offer.status == OfferStatus.CANCELLED) {
                (, address buyer) = _settlementParties(offer, secEscrow);
                IERC20(secEscrow.paymentToken).safeTransfer(buyer, secEscrow.paymentAmount);
            }
        }
    }

    /// @notice Records a party's request to void an ACCEPTED secondary settlement before it is finalized or expires
    /// @dev Finalizer-vouched request channel: the registry voids the agreement only once BOTH parties have
    /// requested (or it is past expiry). The local escrow is settled only when that actually happens, keeping
    /// DealManager and the registry in sync; a lone request just records intent and the counterparty can still finalize.
    /// @param agreementId Settlement agreement to void
    /// @param signer Caller's address (must equal msg.sender)
    /// @param signature Caller's EIP-712 void signature, forwarded to the agreement registry
    function voidSecondaryAgreement(bytes32 agreementId, address signer, bytes memory signature) external nonReentrant {
        if (msg.sender != signer) revert CounterPartyValueMismatch();
        SecondaryEscrow storage secEscrow = SecondaryTradeStorage.getSecondaryEscrow(agreementId);
        _requireActiveSecondaryEscrow(secEscrow);
        Offer storage offer = SecondaryTradeStorage.getOffer(secEscrow.offerId);
        if (msg.sender != secEscrow.counterparty && msg.sender != offer.offeror) revert NotPartyToAgreement();
        address registry = LexScrowStorage.getDealRegistry();
        ICyberAgreementRegistry(registry).voidContractFor(agreementId, signer, signature);
        // A lone request only records intent; the registry voids once both parties have requested
        // (or past expiry). Settle the escrow locally only when that actually happens.
        if (ICyberAgreementRegistry(registry).isVoided(agreementId)) {
            _voidSecondaryDeal(agreementId);
        }
    }

    /// @notice Syncs a secondary settlement that was voided directly in the agreement registry
    /// @dev Callable by anyone; guards against double-void via the terminal-state checks
    /// @param agreementId Settlement agreement that was already voided in the registry
    function syncVoidedSettlement(bytes32 agreementId) external nonReentrant {
        SecondaryEscrow storage secEscrow = SecondaryTradeStorage.getSecondaryEscrow(agreementId);
        _requireActiveSecondaryEscrow(secEscrow);
        if (!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId)) revert DealNotVoided();
        _voidSecondaryDeal(agreementId);
    }

    /// @notice UUPS upgrade authorization
    /// @dev MetaLeX releases new versions through the factory's reference implementation,
    /// and the CyberCorp owner can decide if or when he wants to perform the upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        if(IDealManagerFactory(DealManagerStorage.getUpgradeFactory()).getRefImplementation() != newImplementation) {
            revert NotRefImplementation();
        }
    }
}

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

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./libs/LexScroWLite.sol";
import "./libs/auth.sol";
import "./storage/DealManagerStorage.sol";
import "./storage/BorgAuthStorage.sol";

/// @title DealManager
/// @notice Manages the lifecycle of deals between parties, including creation, signing, payment, and finalization for a CyberCorp
/// @dev Implements UUPS upgradeable pattern and integrates with BorgAuth for access control
contract DealManager is Initializable, BorgAuthACL, LexScroWLite {
    using DealManagerStorage for DealManagerStorage.DealManagerData;

    error ZeroAddress();
    error CounterPartyValueMismatch();
    error AgreementConditionsNotMet();
    error DealNotPending();
    error PartyValuesLengthMismatch();
    error ConditionAlreadyExists();
    error ConditionDoesNotExist();
    error NotUpgradeFactory();
    error DealNotExpired();

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
        LexScrowStorage.setCorp(_corp);
        LexScrowStorage.setDealRegistry(_dealRegistry);
        DealManagerStorage.setIssuanceManager(_issuanceManager);

        // Initialize LexScroWLite without setting storage
        __LexScroWLite_init(_corp, _dealRegistry);
        DealManagerStorage.setUpgradeFactory(_upgradeFactory);
    }

    /// @notice Proposes a new deal
    /// @dev Creates a new agreement and certificate for the deal
    /// @param _certPrinterAddress Address of the certificate NFT contract
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
            corpAssets[i] = Token(TokenType.ERC721, _certPrinterAddress[i], certIds[i], 1);
        }

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount);

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
    /// @param _certPrinterAddress Address of the certificate NFT contract
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
        updateEscrow(agreementId, msg.sender, name);
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
        }
        else {
            DealManagerStorage.setCounterPartyValues(agreementId, partyValues);
        }
            
        if(!conditionCheck(agreementId)) revert AgreementConditionsNotMet();
        
        if(!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).hasSigned(agreementId, signer))
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated, secret);

        updateEscrow(agreementId, msg.sender, name);
        handleCounterPartyPayment(agreementId);
        finalizeDeal(agreementId);
    }

    /// @notice Finalizes a deal
    /// @dev Checks signatures, conditions and finalizes the agreement
    /// @param agreementId Unique identifier for the agreement
    function finalizeDeal(bytes32 agreementId) public {
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId)) revert DealVoided();
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PAID) revert DealNotPaid();
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isFinalized(agreementId)) revert DealAlreadyFinalized();
        if(!ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).allPartiesSigned(agreementId)) revert DealNotFullySigned();
        if(!conditionCheck(agreementId)) revert AgreementConditionsNotMet();
        
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).finalizeContract(agreementId);
        finalizeEscrow(agreementId);
        emit DealFinalized(
            agreementId,
            msg.sender,
            LexScrowStorage.getCorp(),
            LexScrowStorage.getDealRegistry(),
            false
        );
    }

    /// @notice Voids an expired deal
    /// @dev Voids the certificate and agreement for an expired deal
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function voidExpiredDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        Escrow storage deal = LexScrowStorage.getEscrow(agreementId);
        if (block.timestamp <= deal.expiry) revert DealNotExpired();
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
        for(uint256 i = 0; i < deal.corpAssets.length; i++) {
            if(deal.corpAssets[i].tokenType == TokenType.ERC721) {
                DealManagerStorage.getIssuanceManager().voidCertificate(
                    deal.corpAssets[i].tokenAddress, 
                    deal.corpAssets[i].tokenId
                );
            }
        }
        if(deal.status == EscrowStatus.PAID) 
            voidAndRefund(agreementId);
        else if(deal.status == EscrowStatus.PENDING)
            voidEscrow(agreementId);
    }

    /// @notice Revokes a pending deal
    /// @dev Can only be called for deals in pending status
    /// @param agreementId Unique identifier for the agreement
    /// @param signer Address of the signer
    /// @param signature Signature of the signer
    function revokeDeal(bytes32 agreementId, address signer, bytes memory signature) public {
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
    function signToVoid(bytes32 agreementId, address signer, bytes memory signature) public {
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId) && LexScrowStorage.getEscrow(agreementId).status == EscrowStatus.PAID)
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
}

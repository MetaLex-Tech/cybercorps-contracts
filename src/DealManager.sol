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

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./libs/LexScroWLite.sol";
import "./libs/auth.sol";
import "./storage/DealManagerStorage.sol";
import "./storage/BorgAuthStorage.sol";

contract DealManager is Initializable, UUPSUpgradeable, BorgAuthACL, LexScroWLite {
    using DealManagerStorage for DealManagerStorage.DealManagerData;

    IIssuanceManager public ISSUANCE_MANAGER;

    error ZeroAddress();
    error CounterPartyValueMismatch();
    error AgreementConditionsNotMet();
    error DealNotPending();
    error PartyValuesLengthMismatch();
    error ConditionAlreadyExists();
    error ConditionDoesNotExist();

    event DealProposed(
        bytes32 indexed agreementId,
        address indexed certAddress,
        uint256 indexed certId,
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

    mapping(bytes32 => string[]) public counterPartyValues;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    }

    function initialize(address _auth, address _corp, address _dealRegistry, address _issuanceManager) public initializer {
        __UUPSUpgradeable_init();
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
    }

    function proposeDeal(
        address _certPrinterAddress, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        uint256 _salt,
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails memory _certDetails,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public onlyOwner returns (bytes32 agreementId, uint256 certId) {
        agreementId = ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).createContract(_templateId, _salt, _globalValues, _parties, _partyValues, secretHash, address(this), expiry);
        
        certId = DealManagerStorage.getIssuanceManager().createCert(_certPrinterAddress, address(this), _certDetails);

        Token[] memory corpAssets = new Token[](1);
        corpAssets[0] = Token(TokenType.ERC721, _certPrinterAddress, certId, 1);

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
            certId,
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

    function proposeAndSignDeal(
        address _certPrinterAddress, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        uint256 _salt,
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails memory _certDetails,
        address proposer,
        bytes memory signature,
        string[][] memory _partyValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public returns (bytes32 agreementId, uint256 certId) {
        if(_partyValues.length > _parties.length) revert PartyValuesLengthMismatch();
        (agreementId, certId) = proposeDeal(_certPrinterAddress, _paymentToken, _paymentAmount, _templateId, _salt, _globalValues, _parties, _certDetails, _partyValues, conditions, secretHash, expiry);
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

    function voidExpiredDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        Escrow storage deal = LexScrowStorage.getEscrow(agreementId);
        for(uint256 i = 0; i < deal.corpAssets.length; i++) {
            if(deal.corpAssets[i].tokenType == TokenType.ERC721) {
                DealManagerStorage.getIssuanceManager().voidCertificate(
                    deal.corpAssets[i].tokenAddress, 
                    deal.corpAssets[i].tokenId
                );
            }
        }
        voidEscrow(agreementId);
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
    }

    function revokeDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        if(LexScrowStorage.getEscrow(agreementId).status == EscrowStatus.PENDING) 
            ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
        else
            revert DealNotPending();
    }

    function signToVoid(bytes32 agreementId, address signer, bytes memory signature) public {
        ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).voidContractFor(agreementId, signer, signature);
        if(ICyberAgreementRegistry(LexScrowStorage.getDealRegistry()).isVoided(agreementId) && LexScrowStorage.getEscrow(agreementId).status == EscrowStatus.PAID)
            voidAndRefund(agreementId);
    }

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

    function removeConditionAt(bytes32 agreementId, uint256 index) public onlyOwner {
        //make sure the contract is still pending
        if(LexScrowStorage.getEscrow(agreementId).status != EscrowStatus.PENDING) revert DealNotPending();
        //make sure the condition is in the list
        ICondition[] storage conditions = LexScrowStorage.getConditionsByEscrow(agreementId);
        if(index >= conditions.length) revert ConditionDoesNotExist();

        LexScrowStorage.removeConditionFromEscrow(agreementId, index);
    }

    function setDealRegistry(address _dealRegistry) public onlyOwner {
        LexScrowStorage.setDealRegistry(_dealRegistry);
    }

    function setCorp(address _corp) public onlyOwner {
        LexScrowStorage.setCorp(_corp);
    }

    function setIssuanceManager(address _issuanceManager) public onlyOwner {
        DealManagerStorage.setIssuanceManager(_issuanceManager);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    // Remove the public state variables since we're using the storage library
    function issuanceManager() public view returns (IIssuanceManager) {
        return DealManagerStorage.getIssuanceManager();
    }

    function getCounterPartyValues(bytes32 agreementId) public view returns (string[] memory) {
        return DealManagerStorage.getCounterPartyValues(agreementId);
    }
}

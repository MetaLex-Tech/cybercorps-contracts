// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./libs/LexScroWLite.sol";
import "./libs/auth.sol";

contract DealManager is Initializable, UUPSUpgradeable, BorgAuthACL, LexScroWLite {

    IIssuanceManager public ISSUANCE_MANAGER;

    error ZeroAddress();
    error CounterPartyValueMismatch();

    event DealProposed(
        bytes32 indexed agreementId,
        address indexed certAddress,
        uint256 indexed certId,
        address paymentToken,
        uint256 paymentAmount,
        bytes32 templateId,
        address corp,
        address dealRegistry,
        address[] parties
    );

    event DealFinalized(
        bytes32 indexed agreementId,
        address indexed signer,
        address indexed corp,
        address dealRegistry,
        bool fillUnallocated
    );

    mapping(bytes32 => string[]) public counterPartyValues;

    error AgreementConditionsNotMet();
    error DealNotPending();
    error PartyValuesLengthMismatch();
    error ConditionAlreadyExists();
    error ConditionDoesNotExist();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    }

    function initialize(address _auth, address _corp, address _dealRegistry, address _issuanceManager) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        __LexScroWLite_init(_corp, _dealRegistry);

        if (_corp == address(0)) revert ZeroAddress();
        CORP = _corp;
        if (_issuanceManager == address(0)) revert ZeroAddress();
        ISSUANCE_MANAGER = IIssuanceManager(_issuanceManager);
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
    ) public onlyOwner returns (bytes32 agreementId, uint256 certId){

        agreementId = ICyberDealRegistry(DEAL_REGISTRY).createContract(_templateId, _salt, _globalValues, _parties, _partyValues, secretHash, address(this), expiry);
        certId = IIssuanceManager(ISSUANCE_MANAGER).createCert(_certPrinterAddress, address(this), _certDetails);

        Token[] memory corpAssets = new Token[](1);
        corpAssets[0] = Token(TokenType.ERC721, _certPrinterAddress, certId, 1);

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount);
        createEscrow(agreementId, _parties[1], corpAssets, buyerAssets, expiry);

        //set conditions
        for(uint256 i = 0; i < conditions.length; i++) {
            conditionsByEscrow[agreementId].push(ICondition(conditions[i]));
        }

         emit DealProposed(
            agreementId,
            _certPrinterAddress,
            certId,
            _paymentToken,
            _paymentAmount,
            _templateId,
            CORP,
            address(DEAL_REGISTRY),
            _parties
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
        string[][] memory _partyValues, // These are the party values for the proposer
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) public returns (bytes32 agreementId, uint256 certId){
        if(_partyValues.length > _parties.length) revert PartyValuesLengthMismatch();
        (agreementId, certId) = proposeDeal(_certPrinterAddress, _paymentToken, _paymentAmount, _templateId, _salt, _globalValues, _parties, _certDetails, _partyValues, conditions, secretHash, expiry);
        // NOTE: proposer is expected to be listed as a party in the parties array.
        escrows[agreementId].signature = signature;
        if(_partyValues.length > 1) {
            if(_partyValues[1].length != _partyValues[0].length) revert PartyValuesLengthMismatch();
            counterPartyValues[agreementId] = _partyValues[1];
        }
        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(proposer, agreementId, _partyValues[0], signature, false, "");
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
        if(ICyberDealRegistry(DEAL_REGISTRY).isVoided(agreementId)) revert DealVoided();
        if(ICyberDealRegistry(DEAL_REGISTRY).isFinalized(agreementId)) revert DealAlreadyFinalized();
        if(escrows[agreementId].status != EscrowStatus.PENDING) revert DealNotPending();
        //check if the deal has expired
        if(escrows[agreementId].expiry < block.timestamp) revert DealExpired();

        string[] memory counterPartyCheck = counterPartyValues[agreementId];
        if(counterPartyCheck.length > 0) {
            if (keccak256(abi.encode(counterPartyCheck)) != keccak256(abi.encode(partyValues))) revert CounterPartyValueMismatch();
        }

        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated, secret);
        updateEscrow(agreementId, msg.sender, name);
        handleCounterPartyPayment(agreementId);
    }

    function signAndFinalizeDeal(address signer, bytes32 agreementId, string[] memory partyValues, bytes memory signature, bool _fillUnallocated, string memory name, string memory secret) public {
        if(ICyberDealRegistry(DEAL_REGISTRY).isVoided(agreementId)) revert DealVoided();
        if(ICyberDealRegistry(DEAL_REGISTRY).isFinalized(agreementId)) revert DealAlreadyFinalized();
        if(escrows[agreementId].status != EscrowStatus.PENDING) revert DealNotPending();

        string[] memory counterPartyCheck = counterPartyValues[agreementId];
        if(counterPartyCheck.length > 0) {
            if (keccak256(abi.encode(counterPartyCheck)) != keccak256(abi.encode(partyValues))) revert CounterPartyValueMismatch();
        }
        
        if(!conditionCheck(agreementId)) revert AgreementConditionsNotMet();
        
        if(!ICyberDealRegistry(DEAL_REGISTRY).hasSigned(agreementId, signer))
            ICyberDealRegistry(DEAL_REGISTRY).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated, secret);

        updateEscrow(agreementId, msg.sender, name);
        handleCounterPartyPayment(agreementId);
        finalizeDeal(agreementId);
    }

    function finalizeDeal(bytes32 agreementId) public {
        if(ICyberDealRegistry(DEAL_REGISTRY).isVoided(agreementId)) revert DealVoided();
        if(escrows[agreementId].status != EscrowStatus.PAID) revert DealNotPaid();
        if(ICyberDealRegistry(DEAL_REGISTRY).isFinalized(agreementId)) revert DealAlreadyFinalized();
        if(!ICyberDealRegistry(DEAL_REGISTRY).allPartiesSigned(agreementId)) revert DealNotFullySigned();
        if(!conditionCheck(agreementId)) revert AgreementConditionsNotMet();
        
        ICyberDealRegistry(DEAL_REGISTRY).finalizeContract(agreementId);
        finalizeEscrow(agreementId);
        emit DealFinalized(
            agreementId,
            msg.sender,
            CORP,
            address(DEAL_REGISTRY),
            false
        );
    }

    function voidExpiredDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        Escrow storage deal = escrows[agreementId];
        for(uint256 i = 0; i < deal.corpAssets.length; i++) {
            if(deal.corpAssets[i].tokenType == TokenType.ERC721) {
                IIssuanceManager(ISSUANCE_MANAGER).voidCertificate(deal.corpAssets[i].tokenAddress, deal.corpAssets[i].tokenId);
            }
        }
        voidEscrow(agreementId);
        ICyberDealRegistry(DEAL_REGISTRY).voidContractFor(agreementId, signer, signature);
    }

    function revokeDeal(bytes32 agreementId, address signer, bytes memory signature) public {
        if(escrows[agreementId].status == EscrowStatus.PENDING) 
            ICyberDealRegistry(DEAL_REGISTRY).voidContractFor(agreementId, signer, signature);
        else
            revert DealNotPending();
    }

    function signToVoid(bytes32 agreementId, address signer, bytes memory signature) public {
        ICyberDealRegistry(DEAL_REGISTRY).voidContractFor(agreementId, signer, signature);
        if(ICyberDealRegistry(DEAL_REGISTRY).isVoided(agreementId) && escrows[agreementId].status == EscrowStatus.PAID)
            voidAndRefund(agreementId);
    }

    function addCondition(bytes32 agreementId, address condition) public onlyOwner {
        //make sure the contract is still pending
        if(escrows[agreementId].status != EscrowStatus.PENDING) revert DealNotPending();
        //make sure the condition is not already in the list
        for(uint256 i = 0; i < conditionsByEscrow[agreementId].length; i++) {
            if(conditionsByEscrow[agreementId][i] == ICondition(condition)) revert ConditionAlreadyExists();
        }
        conditionsByEscrow[agreementId].push(ICondition(condition));
    }

    function removeConditionAt(bytes32 agreementId, uint256 index) public onlyOwner {
        //make sure the contract is still pending
        if(escrows[agreementId].status != EscrowStatus.PENDING) revert DealNotPending();
        //make sure the condition is in the list
        if(index >= conditionsByEscrow[agreementId].length) revert ConditionDoesNotExist();

        //remove the index and shift the array
        for(uint256 i = index; i < conditionsByEscrow[agreementId].length - 1; i++) {
            conditionsByEscrow[agreementId][i] = conditionsByEscrow[agreementId][i + 1];
        }
        conditionsByEscrow[agreementId].pop();
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

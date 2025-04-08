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
        bytes32 secretHash,
        uint256 expiry
    ) public onlyOwner returns (bytes32 agreementId, uint256 certId){
        certId = IIssuanceManager(ISSUANCE_MANAGER).createCert(_certPrinterAddress, address(this), _certDetails);
        agreementId = ICyberDealRegistry(DEAL_REGISTRY).createContract(_templateId, _salt, _globalValues, _parties, secretHash, address(this));

        Token[] memory corpAssets = new Token[](1);
        corpAssets[0] = Token(TokenType.ERC721, _certPrinterAddress, certId, 1);

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount);
        createEscrow(agreementId, _parties[1], corpAssets, buyerAssets, expiry);

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

    function proposeClosedDeal(
        address _certPrinterAddress, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        uint256 _salt,
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails memory _certDetails,
        string[] memory _creatingPartyValues,
        string[] memory _counterPartyValues,
        bytes32 secretHash,
        uint256 expiry
    ) public onlyOwner returns (bytes32 agreementId, uint256 certId){
        certId = IIssuanceManager(ISSUANCE_MANAGER).createCert(_certPrinterAddress, address(this), _certDetails);
        agreementId = ICyberDealRegistry(DEAL_REGISTRY).createClosedContract(_templateId, _salt, _globalValues, _parties, _creatingPartyValues, _counterPartyValues, secretHash, address(this));

        Token[] memory corpAssets = new Token[](1);
        corpAssets[0] = Token(TokenType.ERC721, _certPrinterAddress, certId, 1);

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount);
        createEscrow(agreementId, _parties[1], corpAssets, buyerAssets, expiry);

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
        string[] memory partyValues, // These are the party values for the proposer
        bytes32 secretHash,
        uint256 expiry
    ) public returns (bytes32 agreementId, uint256 certId){
        (agreementId, certId) = proposeDeal(_certPrinterAddress, _paymentToken, _paymentAmount, _templateId, _salt, _globalValues, _parties, _certDetails, secretHash, expiry);
        // NOTE: proposer is expected to be listed as a party in the parties array.
        escrows[agreementId].signature = signature;
        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(proposer, agreementId, partyValues, signature, false, "");
    }

    function proposeAndSignClosedDeal(
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
        string[] memory partyValues,
        string[] memory _counterPartyValues,
        bytes32 secretHash,
        uint256 expiry
    ) public returns (bytes32 agreementId, uint256 certId){
        (agreementId, certId) = proposeClosedDeal(_certPrinterAddress, _paymentToken, _paymentAmount, _templateId, _salt, _globalValues, _parties, _certDetails, partyValues, _counterPartyValues, secretHash, expiry);
        // NOTE: proposer is expected to be listed as a party in the parties array.
        escrows[agreementId].signature = signature;
        counterPartyValues[agreementId] = _counterPartyValues;
        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(proposer, agreementId, partyValues, signature, false, "");
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
            voidEscrow(agreementId);
    }

    /*function addCondition(Logic _op, address _condition) public onlyOwner {
        _addCondition(_op, _condition);
    }

    function removeCondition(address _condition) public onlyOwner {
        _removeCondition(_condition);
    }*/


    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

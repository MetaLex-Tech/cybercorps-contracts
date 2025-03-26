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
        uint256 _certId, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails memory _certDetails
    ) public onlyOwner returns (bytes32 agreementId){
        IIssuanceManager(ISSUANCE_MANAGER).createCert(_certPrinterAddress, address(this), _certDetails);
        agreementId = ICyberDealRegistry(DEAL_REGISTRY).createContract(_templateId, _globalValues, _parties);

        Token[] memory corpAssets = new Token[](1);
        corpAssets[0] = Token(TokenType.ERC721, _certPrinterAddress, _certId, 1);

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount);
        createEscrow(agreementId, _parties[1], corpAssets, buyerAssets);

        emit DealProposed(
            agreementId,
            _certPrinterAddress,
            _certId,
            _paymentToken,
            _paymentAmount,
            _templateId,
            CORP,
            address(DEAL_REGISTRY),
            _parties
        );
        
        return agreementId;
    }
    
    function proposeAndSignDeal(
        address _certPrinterAddress, 
        uint256 _certId, 
        address _paymentToken, 
        uint256 _paymentAmount, 
        bytes32 _templateId, 
        string[] memory _globalValues, 
        address[] memory _parties, 
        CertificateDetails memory _certDetails,
        address proposer,
        bytes memory signature,
        string[] memory partyValues // These are the party values for the proposer
    ) public returns (bytes32 agreementId){
        agreementId = proposeDeal(_certPrinterAddress, _certId, _paymentToken, _paymentAmount, _templateId, _globalValues, _parties, _certDetails);
        // NOTE: proposer is expected to be listed as a party in the parties array.
        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(proposer, agreementId, partyValues, signature, false);
        
        return agreementId;
    }

    function finalizeDeal(address signer, bytes32 agreementId, string[] memory partyValues, bytes memory signature, bool _fillUnallocated, string memory name) public {
        updateEscrow(agreementId, msg.sender);
        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(signer, agreementId, partyValues, signature, _fillUnallocated);
        finalizeDeal(agreementId, name);

        emit DealFinalized(
            agreementId,
            msg.sender,
            CORP,
            address(DEAL_REGISTRY),
            _fillUnallocated
        );
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

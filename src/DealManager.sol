// SPDX-License-Identifier: unlicensed
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IIssuanceManager.sol";
import "./libs/LexScroWLite.sol";
import "./interfaces/ICyberDealRegistry.sol";
import "./libs/auth.sol";

contract DealManager is Initializable, UUPSUpgradeable, BorgAuthACL, LexScroWLite {
    ICyberDealRegistry public DEAL_REGISTRY;
    IIssuanceManager public ISSUANCE_MANAGER;

    error ZeroAddress();

    event DealProposed(
        bytes32 indexed agreementId,
        address indexed certAddress,
        uint256 indexed certId,
        address paymentToken,
        uint256 paymentAmount,
        bytes32 templateId,
        address[] parties
    );

    event DealFinalized(
        bytes32 indexed agreementId,
        address indexed signer,
        bool fillUnallocated
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
    }

    function initialize(address _auth, address _corp, address _dealRegistry, address _issuanceManager) public initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
        __LexScroWLite_init(_corp);
        
        if (_corp == address(0)) revert ZeroAddress();
        CORP = _corp;
        if (_dealRegistry == address(0)) revert ZeroAddress();
        DEAL_REGISTRY = ICyberDealRegistry(_dealRegistry);
        if (_issuanceManager == address(0)) revert ZeroAddress();
        ISSUANCE_MANAGER = IIssuanceManager(_issuanceManager);
    }

    function proposeDeal(address proposer, address _certAddress, uint256 _certId, address _paymentToken, uint256 _paymentAmount, bytes32 _templateId, string[] memory _globalValues, address[] memory _parties, CertificateDetails memory _certDetails) public onlyOwner returns (bytes32 id){
        IIssuanceManager(ISSUANCE_MANAGER).createCert(_certAddress, address(this), _certDetails);
        bytes32 agreementId = ICyberDealRegistry(DEAL_REGISTRY).createContract(_templateId, _globalValues, _parties);
        
        // Sign for the proposer
        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(proposer, agreementId, _globalValues, false);

        Token[] memory corpAssets = new Token[](1);
        corpAssets[0] = Token(TokenType.ERC721, _certAddress, _certId, 1);

        Token[] memory buyerAssets = new Token[](1);
        buyerAssets[0] = Token(TokenType.ERC20, _paymentToken, 0, _paymentAmount);
        createEscrow(agreementId, _parties[1], corpAssets, buyerAssets);

        emit DealProposed(
            agreementId,
            _certAddress,
            _certId,
            _paymentToken,
            _paymentAmount,
            _templateId,
            _parties
        );

        return agreementId;
    }

    function finalizeDeal(address signer, bytes32 agreementId, string[] memory partyValues, bool _fillUnallocated) public {
        updateEscrow(agreementId, msg.sender);
        ICyberDealRegistry(DEAL_REGISTRY).signContractFor(signer, agreementId, partyValues, _fillUnallocated);
        finalizeDeal(agreementId);

        emit DealFinalized(
            agreementId,
            msg.sender,
            _fillUnallocated
        );
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

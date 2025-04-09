//interface for DealManager
pragma solidity 0.8.28;

import "./IIssuanceManager.sol";

interface IDealManager {
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
    ) external returns (bytes32 agreementId);

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
        string[][] memory paryValues,
        address[] memory conditions,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (bytes32 agreementId, uint256 certId);


    function finalizeDeal(
        address signer,
        bytes32 _agreementId,
        string[] memory _partyValues,
        bytes memory signature,
        bool _fillUnallocated,
        string memory buyerName,
        string memory secret
    ) external;

    function signDealAndPay(
        address signer,
        bytes32 agreementId,
        bytes memory signature,
        string[] memory partyValues,
        bool _fillUnallocated,
        string memory name,
        string memory secret
    ) external;
    

    function signAndFinalizeDeal(
        address signer,
        bytes32 _agreementId,
        string[] memory _partyValues,
        bytes memory signature,
        bool _fillUnallocated,
        string memory buyerName,
        string memory secret
    ) external;

    function voidExpiredDeal(
        bytes32 _agreementId,
        address signer,
        bytes memory signature
    ) external;

    function revokeDeal(
        bytes32 _agreementId,
        address signer,
        bytes memory signature
    ) external;

    function signToVoid(
        bytes32 _agreementId,
        address signer,
        bytes memory signature
    ) external;

    function initialize(
        address _auth,
        address _corp,
        address _dealRegistry,
        address _issuanceManager
    ) external;
}

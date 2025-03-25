//interface for DealManager
pragma solidity 0.8.28;

import "./IIssuanceManager.sol";

interface IDealManager {
    function proposeDeal(
        address _certPrinterAddress,
        uint256 _certId,
        address _paymentToken,
        uint256 _paymentAmount,
        bytes32 _templateId,
        string[] memory _globalValues,
        address[] memory _parties,
        CertificateDetails memory _certDetails
    ) external returns (bytes32 agreementId);

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
        string[] memory paryValues
    ) external returns (bytes32 agreementId);

    function finalizeDeal(
        address signer,
        bytes32 _agreementId,
        string[] memory _partyValues,
        bytes memory signature,
        bool _fillUnallocated
    ) external;

    function initialize(
        address _auth,
        address _corp,
        address _dealRegistry,
        address _issuanceManager
    ) external;
}

//interface for DealManager
pragma solidity 0.8.28;

import "./IIssuanceManager.sol";
interface IDealManager {
    function proposeDeal(address proposer, address _certPrinterAddress, uint256 _certId, address _paymentToken, uint256 _paymentAmount, bytes32 _templateId, string[] memory _globalValues, address[] memory _parties, CertificateDetails memory _certDetails) external returns (bytes32 id);
    function finalizeDeal(bytes32 _agreementId, string[] memory _partyValues, bool _fillUnallocated) external;
    function initialize(address _auth, address _corp, address _dealRegistry, address _issuanceManager) external;
}



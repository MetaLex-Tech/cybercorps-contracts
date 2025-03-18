pragma solidity 0.8.28;

interface ICyberAgreementFactory {
    function deployAgreementFactory(address _registryAddress, address _issuanceManagerAddress) external returns (address, address);
}

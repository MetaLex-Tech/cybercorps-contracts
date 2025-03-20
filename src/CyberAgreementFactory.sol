pragma solidity 0.8.28;



contract CyberAgreementFactory {

    address public lexscrowFactory;

    constructor(address _lexscrowFactory) {
        lexscrowFactory = _lexscrowFactory;
    }

    function deployAgreementFactory(address _registryAddress, address _issuanceManagerAddress) public returns (address, address) {

    }
    
}   
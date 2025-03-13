pragma solidity 0.8.28;

import "../dependencies/cyberCorpTripler/src/ERC721LexscrowFactory.sol";
import "../dependencies/cyberCorpTripler/src/RicardianTriplerOpenOfferCyberCorpSAFE.sol";

contract CyberAgreementFactory {

    address public lexscrowFactory;

    constructor(address _lexscrowFactory) {
        lexscrowFactory = _lexscrowFactory;
    }

    function deployAgreementFactory(address _registryAddress, address _issuanceManagerAddress) public returns (address, address) {
        address agreementFactoryAddress = address(new AgreementV2Factory(_registryAddress, _issuanceManagerAddress));

        return (agreementFactoryAddress, lexscrowFactory);
    }
    
}   
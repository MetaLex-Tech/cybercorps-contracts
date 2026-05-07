// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

abstract contract KnownAddressesLoaded {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 internal constant BASE_SEPOLIA_FORK_BLOCK = 38956871;

    address internal constant METALEX_SAFE = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    address internal constant CYBER_AGREEMENT_REGISTRY = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
    address internal constant CYBERCORP_FACTORY = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
    address internal constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
}

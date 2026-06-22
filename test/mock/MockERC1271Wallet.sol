// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract MockERC1271Wallet {
    bytes4 private _magicValue;

    constructor(bytes4 magicValue) {
        _magicValue = magicValue;
    }

    function isValidSignature(bytes32, bytes memory) external view returns (bytes4) {
        return _magicValue;
    }

    // Accept ERC721 safe transfers so the wallet can receive NFT certificates.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

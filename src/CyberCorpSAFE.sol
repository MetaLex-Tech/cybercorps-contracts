// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC721A} from "erc721a/contracts/ERC721A.sol";
import {IERC721A} from "erc721a/contracts/interfaces/IERC721A.sol";
import {IERC721AQueryable} from "erc721a/contracts/interfaces/IERC721AQueryable.sol";
import {ICyberCorps} from "./interfaces/ICyberCorps.sol";
import {ICyberCorpSAFE} from "./interfaces/ICyberCorpSAFE.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";

contract CyberCorpSAFE is ICyberCorpSAFE, ERC721A {
    ICyberCorps public immutable cyberCorps;
    uint256 public immutable cyberCorpId;

    bool public globalTransfersEnabled = false;
    mapping(uint256 => bool) public isTokenTransferrable;
    mapping(uint256 => CyberCorpSAFEDetails) private _safeDetails;

    error OnlyCyberCorpsContract();
    error OnlyCyberCorpOwner();
    error TokenOwnedByZeroAddress();
    error TokenNotTransferrable(uint256 tokenId);

    modifier onlyCyberCorps() {
        if (msg.sender != address(cyberCorps)) {
            revert OnlyCyberCorpsContract();
        }
        _;
    }

    modifier onlyCyberCorpOwner() {
        if (cyberCorps.ownerOf(cyberCorpId) != msg.sender) {
            revert OnlyCyberCorpOwner();
        }
        _;
    }

    constructor(ICyberCorps cyberCorps_, uint256 cyberCorpId_, string memory name_, string memory symbol_)
        ERC721A(name_, symbol_)
    {
        if (msg.sender != address(cyberCorps_)) {
            revert OnlyCyberCorpsContract();
        }
        cyberCorps = cyberCorps_;
        cyberCorpId = cyberCorpId_;
    }

    function setAreTokensTransferrable(uint256[] calldata ids, bool enabled) public onlyCyberCorpOwner {
        uint256 length = ids.length;
        for (uint256 i = 0; i < length;) {
            uint256 id = ids[i];
            if (cyberCorps.ownerOf(id) == address(0)) {
                revert TokenOwnedByZeroAddress();
            }
            isTokenTransferrable[id] = enabled;
            emit TransferabilitySet(id, enabled);
            unchecked {
                ++i;
            }
        }
    }

    function createSAFE(address recipient, CyberCorpSAFEDetails memory details) public onlyCyberCorpOwner {
        uint256 tokenId = _nextTokenId();
        _mint(recipient, 1);
        _safeDetails[tokenId] = details;
    }

    function _beforeTokenTransfers(address from, address, /*to*/ uint256 startTokenId, uint256 quantity)
        internal
        view
        override
    {
        if (from == address(0)) return; // mint
        if (globalTransfersEnabled) return; // all tokens are freely transferrable
        for (uint256 i = 0; i < quantity; ++i) {
            if (!isTokenTransferrable[startTokenId + i]) revert TokenNotTransferrable(startTokenId + i);
        }
    }

    function tokenURI(uint256 tokenId) public view override(ERC721A, IERC721A) returns (string memory) {
        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": "SAFE #',
            _toString(tokenId),
            '",',
            '"description": "A Simple Agreement for Future Equity token",',
            '"details": {',
            '"principalToken": "',
            _toHexString(safeDetails(tokenId).principalToken),
            '",',
            '"principalAmount": "',
            _toString(safeDetails(tokenId).principalAmount),
            '",',
            '"valuationToken": "',
            _toHexString(safeDetails(tokenId).valuationToken),
            '",',
            '"valuationCap": "',
            _toString(safeDetails(tokenId).valuationCap),
            '"}',
            "}"
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(dataURI)));
    }

    function safeDetails(uint256 tokenId) public view returns (CyberCorpSAFEDetails memory) {
        return _safeDetails[tokenId];
    }

    function _toHexString(address addr) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(addr)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i + 2] = _char(hi);
            s[2 * i + 3] = _char(lo);
        }
        return string(s);
    }

    function _char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function setGlobalTransfersEnabled(bool enabled) public onlyCyberCorpOwner {
        globalTransfersEnabled = enabled;
        emit GlobalTransferabilitySet(enabled);
    }
}

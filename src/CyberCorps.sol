// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "./interfaces/ICyberCorps.sol";
import "./DeterministicDeployFactory.sol";

import {ERC721AQueryable} from "erc721a/contracts/extensions/ERC721AQueryable.sol";
import {ERC721A} from "erc721a/contracts/ERC721A.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {IERC721A} from "erc721a/contracts/interfaces/IERC721A.sol";

contract CyberCorps is ERC721AQueryable, ICyberCorps {
    mapping(uint256 => CyberCorpInfo) public cyberCorpInfo;

    constructor(string memory name_, string memory symbol_)
        ERC721A(name_, symbol_) // Call ERC721A constructor first
        ERC721AQueryable() // Then call ERC721AQueryable constructor with no args
    {}

    function mintCyberCorp(address to_, CyberCorpInfo memory info_) public {
        uint256 tokenId = _nextTokenId();
        _mint(to_, 1);
        cyberCorpInfo[tokenId] = info_;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721A, IERC721A) returns (string memory) {
        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": ',
            '"',
            cyberCorpInfo[tokenId].name,
            '",',
            '"active": ',
            cyberCorpInfo[tokenId].active ? "true" : "false",
            "}"
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(dataURI)));
    }

    function enableSAFEs(uint256 tokenId) public {}
}

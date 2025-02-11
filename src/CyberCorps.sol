// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "./interfaces/ICyberCorps.sol";

import {CyberCorpSAFE} from "./CyberCorpSAFE.sol";

import {ERC721A} from "erc721a/contracts/ERC721A.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import {IERC721A} from "erc721a/contracts/interfaces/IERC721A.sol";

contract CyberCorps is ERC721A, ICyberCorps {
    address public immutable USDC;

    mapping(uint256 => CyberCorpInfo) public cyberCorpInfo;
    mapping(uint256 => address) public SAFEContractForCorp;

    error SAFEAlreadyEnabled();

    constructor(string memory name_, string memory symbol_, address USDC_)
        ERC721A(name_, symbol_) // Call ERC721A constructor first
    {
        USDC = USDC_;
    }

    function mintCyberCorp(address to_, CyberCorpInfo memory info_) public {
        uint256 tokenId = _nextTokenId();
        _mint(to_, 1);
        cyberCorpInfo[tokenId] = info_;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721A, IERC721A) returns (string memory) {
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        "{",
                        '"name":"',
                        cyberCorpInfo[tokenId].name,
                        '",',
                        '"symbol":"',
                        cyberCorpInfo[tokenId].symbol,
                        '",',
                        '"active":',
                        cyberCorpInfo[tokenId].active ? "true" : "false",
                        "}"
                    )
                )
            )
        );
    }

    function enableSAFEs(uint256 tokenId) public {
        if (SAFEContractForCorp[tokenId] != address(0)) revert SAFEAlreadyEnabled();
        CyberCorpInfo memory info = cyberCorpInfo[tokenId];
        address deployedSafeContract = address(
            new CyberCorpSAFE(
                this, tokenId, string.concat(info.name, " SAFEs"), string.concat(info.symbol, "-SAFE"), USDC
            )
        );
        SAFEContractForCorp[tokenId] = deployedSafeContract;
        emit SAFEsEnalbed(tokenId, deployedSafeContract);
    }
}

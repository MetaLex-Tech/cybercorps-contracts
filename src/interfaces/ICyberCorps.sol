// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC721AQueryable} from "erc721a/contracts/interfaces/IERC721AQueryable.sol";

interface ICyberCorps is IERC721AQueryable {
    struct CyberCorpInfo {
        string name;
        string symbol;
        bool active;
    }

    function mintCyberCorp(address to_, CyberCorpInfo memory info_) external;
    function enableSAFEs(uint256 tokenId) external;

    event SAFEsEnabled(uint256 indexed tokenId, address SAFEContract);
}

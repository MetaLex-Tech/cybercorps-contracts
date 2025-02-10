// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC721A} from "erc721a/contracts/interfaces/IERC721A.sol";

interface ICyberCorps is IERC721A {
    struct CyberCorpInfo {
        string name;
        bool active;
    }

    function mintCyberCorp(address to_, CyberCorpInfo memory info_) external;
    function enableSAFEs(uint256 tokenId) external;
}

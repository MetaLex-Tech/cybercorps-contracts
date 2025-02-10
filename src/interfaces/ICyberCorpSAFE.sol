// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC721A} from "erc721a/contracts/interfaces/IERC721A.sol";

error OnlyCyberCorpsContract();

interface ICyberCorpSAFE is IERC721A {
    struct CyberCorpSAFEDetails {
        address principalToken;
        uint256 principalAmount;
        address valuationToken;
        uint256 valuationCap;
    }

    function setAreTokensTransferrable(uint256[] calldata ids, bool enabled) external;
    function createSAFE(address recipient, CyberCorpSAFEDetails memory details) external;

    function safeDetails(uint256 tokenId) external view returns (CyberCorpSAFEDetails memory);

    function isTokenTransferrable(uint256 tokenId) external view returns (bool);
    function globalTransfersEnabled() external view returns (bool);

    function setGlobalTransfersEnabled(bool enabled) external;

    event TransferabilitySet(uint256 indexed tokenId, bool enabled);
    event GlobalTransferabilitySet(bool enabled);
}

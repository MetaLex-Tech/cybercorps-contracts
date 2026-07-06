// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title IERC5484 - Consensual Soulbound Token interface (EIP-5484)
/// @notice Canonical declaration for the LeXcheXBadge family. (lexchex.sol / ILexChex.sol carry their
/// own file-local copies for the legacy v1 deployment; do not import this file alongside those.)
interface IERC5484 {
    enum BurnAuth {
        IssuerOnly,
        OwnerOnly,
        Both,
        Neither
    }

    event Issued(
        address indexed from,
        address indexed to,
        uint256 indexed tokenId,
        BurnAuth burnAuth
    );

    function burnAuth(uint256 tokenId) external view returns (BurnAuth);
}

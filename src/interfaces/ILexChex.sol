// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "../creds/storage/lexchexStorage.sol";

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

interface ILexChex is IERC5484 {
    function accreditations(uint256 tokenId) external view returns (Accreditation memory);
    function setAccreditation(uint256 tokenId, Accreditation memory acc) external;
    function mint(address to, Accreditation memory acc) external returns (uint256);
    function burn(uint256 tokenId) external;
    function hasValidLexCheX(address owner) external view returns (bool);
    function getAccreditation(uint256 tokenId) external view returns (Accreditation memory);
    function getTokenIdsByOwner(address owner) external view returns (uint256[] memory);
    function getAccreditationByOwner(address owner) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function isValid(uint256 tokenId) external view returns (bool);
}



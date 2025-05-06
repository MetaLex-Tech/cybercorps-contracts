pragma solidity 0.8.28;

interface ICertificateExtension {
    function getExtensionData(uint256 tokenId) external view returns (bytes memory);
    function setExtensionData(uint256 tokenId, bytes memory data) external;
    function supportsExtensionType(bytes32 extensionType) external pure returns (bool);
    function getExtensionURI(bytes memory data) external view returns (string memory);
}
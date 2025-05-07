pragma solidity 0.8.28;

interface ICertificateExtension {
    function supportsExtensionType(bytes32 extensionType) external pure returns (bool);
    function getExtensionURI(bytes memory data) external view returns (string memory);
}
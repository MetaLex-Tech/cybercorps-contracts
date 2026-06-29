// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "../../interfaces/ICyberCertPrinter.sol";
import "./baseCondition.sol";

/// @title ArbiterDefaultCondition
/// @notice Lets the neutral arbiter named in a lien attest that default has occurred.
contract ArbiterDefaultCondition is BaseCondition {
    error NotArbiter();

    event DefaultDeclared(address indexed certAddress, uint256 indexed tokenId, uint256 indexed lienIndex, bool declared);

    bytes4 private constant _FORECLOSE_SELECTOR =
        bytes4(keccak256("foreclose(address,uint256,uint256,address,string)"));

    mapping(address => mapping(uint256 => mapping(uint256 => bool))) public defaultDeclared;

    function declareDefault(
        address certAddress,
        uint256 tokenId,
        uint256 lienIndex,
        bool declared
    ) external {
        (Lien memory lien, uint256 seniorIndex, bool found) =
            ICyberCertPrinter(certAddress).seniorActiveLien(tokenId);
        if (!found || seniorIndex != lienIndex || msg.sender != lien.arbiter) revert NotArbiter();

        defaultDeclared[certAddress][tokenId][lienIndex] = declared;
        emit DefaultDeclared(certAddress, tokenId, lienIndex, declared);
    }

    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) public view override returns (bool) {
        if (_functionSignature != _FORECLOSE_SELECTOR) return false;

        (address certAddress, uint256 tokenId, uint256 lienIndex) =
            abi.decode(data, (address, uint256, uint256));
        if (certAddress != _contract) return false;

        return defaultDeclared[certAddress][tokenId][lienIndex];
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "./baseCondition.sol";

/// @title RepaidCondition
/// @notice Release predicate backed by a finalized repayment oracle.
contract RepaidCondition is BaseCondition {
    error NotOracle();

    event RepaidUpdated(address indexed certAddress, uint256 indexed tokenId, uint256 indexed lienIndex, bool repaid);

    bytes4 private constant _RELEASE_SELECTOR =
        bytes4(keccak256("releaseEncumbrance(address,uint256,uint256)"));

    address public immutable oracle;
    mapping(address => mapping(uint256 => mapping(uint256 => bool))) public repaid;

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function setRepaid(
        address certAddress,
        uint256 tokenId,
        uint256 lienIndex,
        bool value
    ) external {
        if (msg.sender != oracle) revert NotOracle();
        repaid[certAddress][tokenId][lienIndex] = value;
        emit RepaidUpdated(certAddress, tokenId, lienIndex, value);
    }

    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) public view override returns (bool) {
        if (_functionSignature != _RELEASE_SELECTOR) return false;

        (address certAddress, uint256 tokenId, uint256 lienIndex) =
            abi.decode(data, (address, uint256, uint256));
        if (certAddress != _contract) return false;

        return repaid[certAddress][tokenId][lienIndex];
    }
}

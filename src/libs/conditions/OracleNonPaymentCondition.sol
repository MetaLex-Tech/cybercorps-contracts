// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "./baseCondition.sol";

/// @title OracleNonPaymentCondition
/// @notice Default predicate backed by a loan-servicing oracle.
contract OracleNonPaymentCondition is BaseCondition {
    error NotOracle();

    event NonPaymentUpdated(address indexed certAddress, uint256 indexed tokenId, uint256 indexed lienIndex, bool nonPayment);

    bytes4 private constant _FORECLOSE_SELECTOR =
        bytes4(keccak256("foreclose(address,uint256,uint256,address,string)"));

    address public immutable oracle;
    mapping(address => mapping(uint256 => mapping(uint256 => bool))) public nonPayment;

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function setNonPayment(
        address certAddress,
        uint256 tokenId,
        uint256 lienIndex,
        bool value
    ) external {
        if (msg.sender != oracle) revert NotOracle();
        nonPayment[certAddress][tokenId][lienIndex] = value;
        emit NonPaymentUpdated(certAddress, tokenId, lienIndex, value);
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

        return nonPayment[certAddress][tokenId][lienIndex];
    }
}

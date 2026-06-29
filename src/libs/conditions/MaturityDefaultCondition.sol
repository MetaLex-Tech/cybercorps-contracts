// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import "../../interfaces/ICyberCertPrinter.sol";
import "./baseCondition.sol";

/// @title MaturityDefaultCondition
/// @notice A trustless default predicate that flips true after the lien maturity timestamp.
contract MaturityDefaultCondition is BaseCondition {
    bytes4 private constant _FORECLOSE_SELECTOR =
        bytes4(keccak256("foreclose(address,uint256,uint256,address,string)"));

    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) public view override returns (bool) {
        if (_functionSignature != _FORECLOSE_SELECTOR) return false;

        (address certAddress, uint256 tokenId, uint256 lienIndex) =
            abi.decode(data, (address, uint256, uint256));
        if (certAddress != _contract) return false;

        (Lien memory lien, uint256 seniorIndex, bool found) =
            ICyberCertPrinter(certAddress).seniorActiveLien(tokenId);
        return found && seniorIndex == lienIndex && lien.maturity != 0 && block.timestamp >= lien.maturity;
    }
}

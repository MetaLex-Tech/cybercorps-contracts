// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseCondition} from "./baseCondition.sol";
import {ICondition} from "../../interfaces/ICondition.sol";

contract OrCondition is BaseCondition {
    error NeedMoreConditions();

    ICondition[] public conditions;

    constructor(address[] memory _conditions) {
        if (_conditions.length < 2) revert NeedMoreConditions();
        for (uint256 i = 0; i < _conditions.length; i++) {
            conditions.push(ICondition(_conditions[i]));
        }
    }

    function checkCondition(
        address _contract,
        bytes4 _functionSignature,
        bytes memory data
    ) public view override returns (bool) {
        for (uint256 i = 0; i < conditions.length; i++) {
            if (conditions[i].checkCondition(_contract, _functionSignature, data))
                return true;
        }
        return false;
    }
}

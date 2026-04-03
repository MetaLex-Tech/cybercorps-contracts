// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ICondition} from "../src/interfaces/ICondition.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {OrCondition} from "../src/libs/conditions/OrCondition.sol";

contract AlwaysTrueCondition is ICondition {
    function checkCondition(address, bytes4, bytes memory) external pure returns (bool) {
        return true;
    }
}

contract AlwaysFalseCondition is ICondition {
    function checkCondition(address, bytes4, bytes memory) external pure returns (bool) {
        return false;
    }
}

contract OrConditionTest is Test {
    AlwaysTrueCondition internal trueCondition;
    AlwaysFalseCondition internal falseCondition;

    function setUp() public {
        trueCondition = new AlwaysTrueCondition();
        falseCondition = new AlwaysFalseCondition();
    }

    function _makeOr(address a, address b) internal returns (OrCondition) {
        address[] memory addrs = new address[](2);
        addrs[0] = a;
        addrs[1] = b;
        return new OrCondition(addrs);
    }

    function test_AllFalse_ReturnsFalse() public {
        OrCondition orCond = _makeOr(address(falseCondition), address(falseCondition));
        assertFalse(orCond.checkCondition(address(0), bytes4(0), ""));
    }

    function test_FirstTrue_ReturnsTrue() public {
        OrCondition orCond = _makeOr(address(trueCondition), address(falseCondition));
        assertTrue(orCond.checkCondition(address(0), bytes4(0), ""));
    }

    function test_LastTrue_ReturnsTrue() public {
        OrCondition orCond = _makeOr(address(falseCondition), address(trueCondition));
        assertTrue(orCond.checkCondition(address(0), bytes4(0), ""));
    }

    function test_AllTrue_ReturnsTrue() public {
        OrCondition orCond = _makeOr(address(trueCondition), address(trueCondition));
        assertTrue(orCond.checkCondition(address(0), bytes4(0), ""));
    }

    function test_ThreeConditions_MiddleTrue_ReturnsTrue() public {
        address[] memory addrs = new address[](3);
        addrs[0] = address(falseCondition);
        addrs[1] = address(trueCondition);
        addrs[2] = address(falseCondition);
        OrCondition orCond = new OrCondition(addrs);
        assertTrue(orCond.checkCondition(address(0), bytes4(0), ""));
    }

    function test_RevertIf_ConstructorWithFewerThanTwoConditions() public {
        address[] memory addrs = new address[](1);
        addrs[0] = address(trueCondition);
        vm.expectRevert(OrCondition.NeedMoreConditions.selector);
        new OrCondition(addrs);
    }

    function test_RevertIf_ConstructorWithZeroConditions() public {
        address[] memory addrs = new address[](0);
        vm.expectRevert(OrCondition.NeedMoreConditions.selector);
        new OrCondition(addrs);
    }

    function test_SupportsInterface_ICondition() public {
        OrCondition orCond = _makeOr(address(trueCondition), address(falseCondition));
        assertTrue(orCond.supportsInterface(type(ICondition).interfaceId));
    }

    function test_SupportsInterface_IERC165() public {
        OrCondition orCond = _makeOr(address(trueCondition), address(falseCondition));
        assertTrue(orCond.supportsInterface(type(IERC165).interfaceId));
    }

    function test_SupportsInterface_Unknown_ReturnsFalse() public {
        OrCondition orCond = _makeOr(address(trueCondition), address(falseCondition));
        assertFalse(orCond.supportsInterface(bytes4(0xDEADBEEF)));
    }

    function test_ConditionsArray_StoredCorrectly() public {
        OrCondition orCond = _makeOr(address(trueCondition), address(falseCondition));
        assertEq(address(orCond.conditions(0)), address(trueCondition));
        assertEq(address(orCond.conditions(1)), address(falseCondition));
    }

    // Integration: OrCondition composed with two real sub-conditions, one of which passes
    function test_Integration_OrCondition_PassesWhenOneSubConditionPasses() public {
        // Simulate an OrCondition used as a round condition:
        // falseCondition || trueCondition → should pass
        OrCondition orCond = _makeOr(address(falseCondition), address(trueCondition));

        // checkCondition args don't matter for always-true/false mocks
        bool result = orCond.checkCondition(address(this), bytes4(keccak256("allocate(bytes32,uint256)")), abi.encode(bytes32(0)));
        assertTrue(result);
    }

    function test_Integration_OrCondition_FailsWhenAllSubConditionsFail() public {
        OrCondition orCond = _makeOr(address(falseCondition), address(falseCondition));

        bool result = orCond.checkCondition(address(this), bytes4(keccak256("allocate(bytes32,uint256)")), abi.encode(bytes32(0)));
        assertFalse(result);
    }
}

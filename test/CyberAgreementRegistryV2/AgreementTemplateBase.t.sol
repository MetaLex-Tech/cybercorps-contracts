/*    .o.
     .888.
    .8"888.
   .8' `888.
   .88ooo8888.
  .8'     `888.
 o88o     o8888o



 ooo        ooooo               .             ooooo                  ooooooo  ooooo
 `88.       .888'             .o8             `888'                   `8888    d8'
  888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P
  8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'
  8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.
  8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b
 o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o



   .oooooo.                .o8                            .oooooo.
  d8P'  `Y8b              "888"                           d8P'  `Y8b
 888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.
 888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b
 888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888
 `88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o.
  `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
               .o..P'                                                                     888
               `Y8P'                                                                     o888o
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published,
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system,
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {AgreementTemplateBase} from "../../src/templates/AgreementTemplateBase.sol";
import {IAgreementTemplate} from "../../src/interfaces/IAgreementTemplate.sol";
import {ICondition} from "../../src/interfaces/ICondition.sol";

/**
 * @notice Concrete implementation of AgreementTemplateBase for testing
 */
contract TestAgreementTemplate is AgreementTemplateBase {
    // Define test input/output structs
    struct TestInput {
        address tokenAddress;
        uint256 amount;
    }
    
    struct TestOutput {
        address tokenAddress;
        uint256 amount;
        string greeting;
    }

    function setContentUri(string memory _contentUri) public {
        _setContentUri(_contentUri);
    }

    function addClosingCondition(address condition) public {
        _addClosingCondition(condition);
    }

    function getWordingValues(bytes memory data) external pure returns (bytes memory) {
        TestInput memory input = abi.decode(data, (TestInput));
        
        TestOutput memory output = TestOutput({
            tokenAddress: input.tokenAddress,
            amount: input.amount,
            greeting: "Hello"
        });
        
        return abi.encode(output);
    }
}

/**
 * @notice Mock condition for testing
 */
contract MockTestCondition is ICondition {
    function checkCondition(address, bytes4, bytes memory) external pure returns (bool) {
        return true;
    }
}

contract AgreementTemplateBaseTest is Test {
    // Test accounts
    address deployer;
    TestAgreementTemplate template;

    function setUp() public {
        deployer = makeAddr("deployer");

        vm.startPrank(deployer);

        // Deploy TestAgreementTemplate directly (no proxy needed for tests)
        template = new TestAgreementTemplate();
        template.setContentUri("ar://QmTest/");

        vm.stopPrank();
    }

    // ============ Interface Support Tests ============

    function test_SupportsInterface_IAgreementTemplate() public view {
        assertTrue(
            template.supportsInterface(type(IAgreementTemplate).interfaceId),
            "Should support IAgreementTemplate"
        );
    }

    function test_SupportsInterface_IERC165() public view {
        assertTrue(
            template.supportsInterface(type(IERC165).interfaceId),
            "Should support IERC165"
        );
    }

    function test_DoesNotSupportInterface_Unknown() public view {
        bytes4 unknownInterfaceId = bytes4(keccak256("unknownInterface()"));
        assertFalse(
            template.supportsInterface(unknownInterfaceId),
            "Should not support unknown interface"
        );
    }

    // ============ Content URI Tests ============

    function test_ContentUri() public view {
        assertEq(
            template.contentUri(),
            "ar://QmTest/",
            "Content URI mismatch"
        );
    }

    // ============ Closing Conditions Tests ============

    function test_GetClosingConditions_Empty() public view {
        address[] memory conditions = template.getClosingConditions();
        assertEq(conditions.length, 0, "Should have no closing conditions");
    }

    function test_AddClosingCondition() public {
        MockTestCondition condition1 = new MockTestCondition();
        MockTestCondition condition2 = new MockTestCondition();

        template.addClosingCondition(address(condition1));
        address[] memory conditions = template.getClosingConditions();
        assertEq(conditions.length, 1);
        assertEq(conditions[0], address(condition1));

        template.addClosingCondition(address(condition2));
        conditions = template.getClosingConditions();
        assertEq(conditions.length, 2);
        assertEq(conditions[1], address(condition2));
    }

    // ============ Get Wording Values Tests ============

    function test_GetWordingValues() public view {
        TestAgreementTemplate.TestInput memory input = TestAgreementTemplate.TestInput({
            tokenAddress: address(0x123),
            amount: 1000
        });
        
        bytes memory data = abi.encode(input);
        bytes memory result = template.getWordingValues(data);
        
        TestAgreementTemplate.TestOutput memory output = abi.decode(result, (TestAgreementTemplate.TestOutput));
        
        assertEq(output.tokenAddress, input.tokenAddress);
        assertEq(output.amount, input.amount);
        assertEq(output.greeting, "Hello");
    }

    // ============ Validation Tests ============

    function test_Validate_DefaultReturnsTrue() public view {
        // Default implementation returns true
        bytes memory data = abi.encode(TestAgreementTemplate.TestInput(address(0), 0));
        assertTrue(template.validate(data), "Default validate should return true");
    }
}

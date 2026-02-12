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
import {SimpleSaleAgreementTemplate} from "../../src/templates/examples/SimpleSaleAgreementTemplate.sol";
import {IAgreementTemplate} from "../../src/interfaces/IAgreementTemplate.sol";
import {ICondition} from "../../src/interfaces/ICondition.sol";
import {MockERC20} from "../mock/MockERC20.sol";

contract SimpleSaleAgreementTemplateTest is Test {
    // Test accounts
    address deployer;
    SimpleSaleAgreementTemplate template;
    MockERC20 mockToken;

    function setUp() public {
        deployer = makeAddr("deployer");

        vm.startPrank(deployer);

        // Deploy a mock ERC20 for testing
        mockToken = new MockERC20("Mock Token", "MOCK", 18);

        // Deploy SimpleSaleAgreementTemplate (immutable, no proxy)
        address[] memory conditions = new address[](0);
        template = new SimpleSaleAgreementTemplate("ar://QmTest/", conditions);

        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(template.contentUri(), "ar://QmTest/", "Content URI should be set");
        address[] memory conditions = template.getClosingConditions();
        assertEq(conditions.length, 0, "Should have no conditions");
    }

    // ============ Get Wording Values Tests ============

    function test_GetWordingValues_ETHPayment() public view {
        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(mockToken),
            assetAmount: 100,
            purchasePrice: 1.5 ether,
            paymentToken: address(0), // ETH
            deliveryDate: block.timestamp + 1 days,
            description: "Rare NFT"
        });

        bytes memory data = abi.encode(input);
        bytes memory result = template.getWordingValues(data);

        SimpleSaleAgreementTemplate.SaleOutput memory output = abi.decode(
            result,
            (SimpleSaleAgreementTemplate.SaleOutput)
        );

        // Verify all fields are populated
        assertEq(output.assetAddress, input.assetAddress);
        assertEq(output.assetAmount, input.assetAmount);
        assertEq(output.assetDecimals, 18);
        assertEq(output.purchasePrice, input.purchasePrice);
        assertEq(output.paymentToken, input.paymentToken);
        assertEq(output.deliveryDate, input.deliveryDate);
        assertEq(output.description, input.description);

        // Verify token metadata fetched
        assertEq(output.assetName, "Mock Token");
        assertEq(output.assetSymbol, "MOCK");
        
        // Verify ETH payment token info
        assertEq(output.paymentTokenName, "Ether");
        assertEq(output.paymentTokenSymbol, "ETH");
        assertEq(output.paymentTokenDecimals, 18);
    }

    function test_GetWordingValues_ERC20Payment() public {
        // Setup: Deploy another mock as payment token
        vm.startPrank(deployer);
        MockERC20 paymentToken = new MockERC20("USD Coin", "USDC", 6);
        vm.stopPrank();

        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(mockToken),
            assetAmount: 500,
            purchasePrice: 1000 ether,
            paymentToken: address(paymentToken),
            deliveryDate: block.timestamp + 7 days,
            description: "Payment in USDC"
        });

        bytes memory data = abi.encode(input);
        bytes memory result = template.getWordingValues(data);

        SimpleSaleAgreementTemplate.SaleOutput memory output = abi.decode(
            result,
            (SimpleSaleAgreementTemplate.SaleOutput)
        );

        // Verify ERC20 payment token metadata is resolved
        assertEq(output.paymentTokenName, "USD Coin");
        assertEq(output.paymentTokenSymbol, "USDC");
        assertEq(output.paymentTokenDecimals, 6);
    }

    // ============ Validation Tests ============

    function test_Validate_Valid() public view {
        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(mockToken),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(input);
        assertTrue(template.validate(data), "Valid data should pass");
    }

    function test_Validate_Invalid_ZeroAssetAddress() public view {
        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(0),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(input);
        assertFalse(template.validate(data), "Zero asset address should fail");
    }

    function test_Validate_Invalid_ZeroAssetAmount() public view {
        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(mockToken),
            assetAmount: 0,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(input);
        assertFalse(template.validate(data), "Zero asset amount should fail");
    }

    function test_Validate_Invalid_ZeroPurchasePrice() public view {
        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(mockToken),
            assetAmount: 100,
            purchasePrice: 0,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(input);
        assertFalse(template.validate(data), "Zero purchase price should fail");
    }

    function test_Validate_Invalid_PastDeliveryDate() public view {
        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(mockToken),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp - 1, // Past date
            description: "Test sale"
        });

        bytes memory data = abi.encode(input);
        assertFalse(template.validate(data), "Past delivery date should fail");
    }

    function test_Validate_Invalid_EmptyDescription() public view {
        SimpleSaleAgreementTemplate.SaleInput memory input = SimpleSaleAgreementTemplate.SaleInput({
            assetAddress: address(mockToken),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: ""
        });

        bytes memory data = abi.encode(input);
        assertFalse(template.validate(data), "Empty description should fail");
    }

    function test_Validate_Invalid_MalformedData() public view {
        bytes memory malformedData = hex"1234";
        assertFalse(template.validate(malformedData), "Malformed data should fail");
    }

    // ============ Closing Conditions Tests ============

    function test_GetClosingConditions_Empty() public view {
        address[] memory conditions = template.getClosingConditions();
        assertEq(conditions.length, 0, "Should have no closing conditions");
    }

    function test_GetClosingConditions_WithConditions() public {
        // Deploy new template with conditions
        address mockCondition = address(0x9999);
        address[] memory conditions = new address[](1);
        conditions[0] = mockCondition;

        vm.startPrank(deployer);
        SimpleSaleAgreementTemplate templateWithConditions = new SimpleSaleAgreementTemplate(
            "ar://QmTest2/",
            conditions
        );
        vm.stopPrank();

        address[] memory retrievedConditions = templateWithConditions.getClosingConditions();
        assertEq(retrievedConditions.length, 1, "Should have one condition");
        assertEq(retrievedConditions[0], mockCondition, "Condition address should match");
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

    function test_SupportsInterface_Unknown() public view {
        bytes4 unknownInterfaceId = bytes4(keccak256("unknownInterface()"));
        assertFalse(
            template.supportsInterface(unknownInterfaceId),
            "Should not support unknown interface"
        );
    }

}

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
 d8P'  `Y8b              "888                           d8P'  `Y8b
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
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../../src/libs/auth.sol";
import {SimpleSaleAgreementTemplate} from "../../src/templates/examples/SimpleSaleAgreementTemplate.sol";
import {IAgreementTemplate} from "../../src/interfaces/IAgreementTemplate.sol";
import {ICondition} from "../../src/interfaces/ICondition.sol";

contract SimpleSaleAgreementTemplateTest is Test {
    // Test accounts
    address deployer;
    BorgAuth auth;
    SimpleSaleAgreementTemplate template;

    bytes32 coreSalt = keccak256("SimpleSaleAgreementTemplateTest");

    function setUp() public {
        deployer = makeAddr("deployer");

        vm.startPrank(deployer);

        // Deploy BorgAuth
        auth = new BorgAuth{salt: coreSalt}(deployer);

        // Deploy SimpleSaleAgreementTemplate with proxy
        SimpleSaleAgreementTemplate templateImpl = new SimpleSaleAgreementTemplate{salt: coreSalt}();
        template = SimpleSaleAgreementTemplate(
            address(
                new ERC1967Proxy{salt: coreSalt}(
                    address(templateImpl),
                    abi.encodeWithSelector(
                        SimpleSaleAgreementTemplate.initialize.selector,
                        address(auth),
                        "ipfs://QmTest/"
                    )
                )
            )
        );

        vm.stopPrank();
    }

    // ============ Initialization Tests ============

    function test_Initialize() public view {
        assertEq(
            template.templateContentUri(),
            "ipfs://QmTest/",
            "Content URI should be set"
        );
    }

    // ============ Template Data Encoding/Decoding Tests ============

    function test_EncodeDecodeTemplateData() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory encoded = abi.encode(saleData);
        bytes memory returnedData = template.decodeTemplateData(encoded);

        SimpleSaleAgreementTemplate.SaleAgreementData memory decoded = abi.decode(
            returnedData,
            (SimpleSaleAgreementTemplate.SaleAgreementData)
        );

        assertEq(decoded.assetAddress, saleData.assetAddress, "Asset address mismatch");
        assertEq(decoded.assetAmount, saleData.assetAmount, "Asset amount mismatch");
        assertEq(decoded.purchasePrice, saleData.purchasePrice, "Purchase price mismatch");
        assertEq(decoded.paymentToken, saleData.paymentToken, "Payment token mismatch");
        assertEq(decoded.deliveryDate, saleData.deliveryDate, "Delivery date mismatch");
        assertEq(decoded.description, saleData.description, "Description mismatch");
    }

    function test_EncodeTemplateData() public view {
        bytes memory data = abi.encode(
            SimpleSaleAgreementTemplate.SaleAgreementData({
                assetAddress: address(0x1234),
                assetAmount: 100,
                purchasePrice: 1 ether,
                paymentToken: address(0),
                deliveryDate: block.timestamp + 1 days,
                description: "Test"
            })
        );

        bytes memory encoded = template.encodeTemplateData(data);
        assertEq(encoded, data, "Should return same data");
    }

    // ============ Validation Tests ============

    function test_ValidateTemplateData_Valid() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(saleData);
        assertTrue(template.validateTemplateData(data), "Valid data should pass");
    }

    function test_ValidateTemplateData_Invalid_ZeroAssetAddress() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(saleData);
        assertFalse(
            template.validateTemplateData(data),
            "Zero asset address should fail"
        );
    }

    function test_ValidateTemplateData_Invalid_ZeroAssetAmount() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 0,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(saleData);
        assertFalse(
            template.validateTemplateData(data),
            "Zero asset amount should fail"
        );
    }

    function test_ValidateTemplateData_Invalid_ZeroPurchasePrice() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 0,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        bytes memory data = abi.encode(saleData);
        assertFalse(
            template.validateTemplateData(data),
            "Zero purchase price should fail"
        );
    }

    function test_ValidateTemplateData_Invalid_PastDeliveryDate() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp - 1, // Past date
            description: "Test sale"
        });

        bytes memory data = abi.encode(saleData);
        assertFalse(
            template.validateTemplateData(data),
            "Past delivery date should fail"
        );
    }

    function test_ValidateTemplateData_Invalid_EmptyDescription() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: ""
        });

        bytes memory data = abi.encode(saleData);
        assertFalse(
            template.validateTemplateData(data),
            "Empty description should fail"
        );
    }

    function test_ValidateTemplateData_Invalid_MalformedData() public view {
        bytes memory malformedData = hex"1234";
        assertFalse(
            template.validateTemplateData(malformedData),
            "Malformed data should fail"
        );
    }

    // ============ Legal Wording Values Tests ============

    function test_GetLegalWordingValues() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1.5 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Rare NFT"
        });

        bytes memory data = abi.encode(saleData);
        (string[] memory keys, string[] memory values) = template.getLegalWordingValues(data);

        assertEq(keys.length, 6, "Should have 6 keys");
        assertEq(values.length, 6, "Should have 6 values");

        // Check keys
        assertEq(keys[0], "assetAddress", "Key mismatch");
        assertEq(keys[1], "assetAmount", "Key mismatch");
        assertEq(keys[2], "purchasePrice", "Key mismatch");
        assertEq(keys[3], "paymentToken", "Key mismatch");
        assertEq(keys[4], "deliveryDate", "Key mismatch");
        assertEq(keys[5], "description", "Key mismatch");

        // Check values
        assertTrue(
            _contains(values[0], "1234"),
            "Asset address should contain 1234"
        );
        assertEq(values[1], "100", "Asset amount mismatch");
        assertTrue(
            _contains(values[2], "1.5"),
            "Purchase price should contain 1.5"
        );
        assertEq(values[3], "ETH", "Payment token should be ETH");
        assertTrue(
            bytes(values[4]).length > 0,
            "Delivery date should not be empty"
        );
        assertEq(values[5], "Rare NFT", "Description mismatch");
    }

    function test_GetLegalWordingValues_WithERC20() public view {
        address usdc = address(0xa0b86a33e6441e6c7c7cE3C9B5DE2F8D6C4b2A1E);

        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x5678),
            assetAmount: 500,
            purchasePrice: 1000 ether,
            paymentToken: usdc,
            deliveryDate: block.timestamp + 7 days,
            description: "Payment in USDC"
        });

        bytes memory data = abi.encode(saleData);
        (string[] memory keys, string[] memory values) = template.getLegalWordingValues(data);

        assertTrue(
            _contains(values[3], "a0b86a"),
            "Payment token should show address"
        );
        assertFalse(
            _equals(values[3], "ETH"),
            "Payment token should not be ETH"
        );
    }

    // ============ Party Data Tests ============

    function test_PartyDataValidation_Individual() public view {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        assertTrue(
            template.validatePartyData(partyData),
            "Individual with valid data should pass"
        );
    }

    function test_PartyDataValidation_Company() public view {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "MetaLeX Labs, Inc.",
            partyType: IAgreementTemplate.PartyType.Company,
            contactDetails: "legal@metalex.ai",
            jurisdiction: "Delaware"
        });

        assertTrue(
            template.validatePartyData(partyData),
            "Company with valid data should pass"
        );
    }

    // ============ Closing Conditions Tests ============

    function test_GetClosingConditions() public view {
        ICondition[] memory conditions = template.getClosingConditions();
        assertEq(conditions.length, 0, "Should have no closing conditions");
    }

    // ============ Interface Support Tests ============

    function test_SupportsInterface() public view {
        assertTrue(
            template.supportsInterface(type(IAgreementTemplate).interfaceId),
            "Should support IAgreementTemplate"
        );
    }

    // ============ Helper Functions ============

    function _contains(string memory _str, string memory _substring) internal pure returns (bool) {
        bytes memory strBytes = bytes(_str);
        bytes memory subBytes = bytes(_substring);

        if (subBytes.length > strBytes.length) {
            return false;
        }

        for (uint256 i = 0; i <= strBytes.length - subBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < subBytes.length; j++) {
                if (strBytes[i + j] != subBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }

        return false;
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    // ============ Additional Coverage Tests ============

    function test_GetLegalWordingValues_ZeroEther() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 0,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Free asset"
        });

        bytes memory data = abi.encode(saleData);
        (, string[] memory values) = template.getLegalWordingValues(data);

        assertTrue(_contains(values[2], "0"));
        assertTrue(_contains(values[2], "ETH"));
    }

    function test_GetLegalWordingValues_LargeAmount() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 999999,
            purchasePrice: 1000000 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 365 days,
            description: "Large amount test"
        });

        bytes memory data = abi.encode(saleData);
        (string[] memory keys, string[] memory values) = template.getLegalWordingValues(data);

        assertEq(keys.length, 6);
        assertEq(values.length, 6);
    }

    function test_GetLegalWordingValues_FarFutureDate() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 3650 days,
            description: "Future delivery"
        });

        bytes memory data = abi.encode(saleData);
        (, string[] memory values) = template.getLegalWordingValues(data);

        assertTrue(bytes(values[4]).length >= 10);
        assertTrue(_contains(values[4], "-"));
    }

    function test_ValidateTemplateData_ZeroAddressPaymentToken() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "ETH payment"
        });

        bytes memory data = abi.encode(saleData);
        assertTrue(template.validateTemplateData(data));
    }

    function test_ValidateTemplateData_CurrentTimestampDelivery() public view {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp,
            description: "Current delivery"
        });

        bytes memory data = abi.encode(saleData);
        assertFalse(template.validateTemplateData(data));
    }

    function test_ValidatePartyData_LongStrings() public view {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "A very long name that might cause issues if there are buffer limits",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "a.very.long.email@example.com",
            jurisdiction: ""
        });

        assertTrue(template.validatePartyData(partyData));
    }

    function test_ValidatePartyData_CompanyWithLongJurisdiction() public view {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "Test Corp",
            partyType: IAgreementTemplate.PartyType.Company,
            contactDetails: "legal@testcorp.com",
            jurisdiction: "Delaware United States"
        });

        assertTrue(template.validatePartyData(partyData));
    }
}

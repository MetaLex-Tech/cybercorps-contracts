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
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {AgreementTemplateBase, PartyDataLib} from "../../src/templates/AgreementTemplateBase.sol";
import {IAgreementTemplate} from "../../src/interfaces/IAgreementTemplate.sol";
import {ICondition} from "../../src/interfaces/ICondition.sol";

/**
 * @notice Concrete implementation of AgreementTemplateBase for testing
 */
contract TestAgreementTemplate is AgreementTemplateBase {
    function setContentUri(string memory _contentUri) public {
        _setTemplateContentUri(_contentUri);
    }

    function encodeTemplateData(bytes memory data) external pure override returns (bytes memory) {
        return data;
    }

    function decodeTemplateData(bytes memory data) external pure override returns (bytes memory) {
        return data;
    }

    function validateTemplateData(bytes memory) external pure override returns (bool) {
        return true;
    }

    function getLegalWordingValues(bytes memory) external pure override returns (string[] memory keys, string[] memory values) {
        keys = new string[](0);
        values = new string[](0);
    }
}

contract AgreementTemplateBaseTest is Test {
    // Test accounts
    address deployer;
    TestAgreementTemplate template;

    bytes32 coreSalt = keccak256("AgreementTemplateBaseTest");

    function setUp() public {
        deployer = makeAddr("deployer");

        vm.startPrank(deployer);

        // Deploy TestAgreementTemplate directly (no proxy needed for tests)
        template = new TestAgreementTemplate();
        template.setContentUri("ipfs://QmTest/");

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

    function test_TemplateContentUri() public view {
        assertEq(
            template.templateContentUri(),
            "ipfs://QmTest/",
            "Content URI mismatch"
        );
    }

    // ============ Closing Conditions Tests ============

    function test_GetClosingConditions_Empty() public view {
        ICondition[] memory conditions = template.getClosingConditions();
        assertEq(conditions.length, 0, "Should have no closing conditions");
    }

    // ============ Party Data Encoding/Decoding Tests ============

    function test_EncodeDecodePartyData() public pure {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        bytes memory encoded = abi.encode(partyData);
        IAgreementTemplate.PartyData memory decoded = abi.decode(encoded, (IAgreementTemplate.PartyData));

        assertEq(decoded.name, partyData.name, "Name mismatch");
        assertEq(uint256(decoded.partyType), uint256(partyData.partyType), "Party type mismatch");
        assertEq(decoded.contactDetails, partyData.contactDetails, "Contact details mismatch");
        assertEq(decoded.jurisdiction, partyData.jurisdiction, "Jurisdiction mismatch");
    }

    function test_EncodePartyData() public pure {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Company,
            contactDetails: "bob@example.com",
            jurisdiction: "Delaware"
        });

        bytes memory encoded = abi.encode(partyData);
        assertTrue(encoded.length > 0, "Encoded data should not be empty");
    }

    // ============ Party Data Validation Tests ============

    function test_ValidatePartyData_ValidIndividual() public pure {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        assertTrue(
            _validatePartyData(partyData),
            "Individual with valid data should pass"
        );
    }

    function test_ValidatePartyData_ValidCompany() public pure {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "MetaLeX Labs",
            partyType: IAgreementTemplate.PartyType.Company,
            contactDetails: "legal@metalex.ai",
            jurisdiction: "Delaware"
        });

        assertTrue(
            _validatePartyData(partyData),
            "Company with valid data should pass"
        );
    }

    function test_ValidatePartyData_Invalid_EmptyName() public pure {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        assertFalse(
            _validatePartyData(partyData),
            "Empty name should fail validation"
        );
    }

    function test_ValidatePartyData_Invalid_EmptyContact() public pure {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "",
            jurisdiction: ""
        });

        assertFalse(
            _validatePartyData(partyData),
            "Empty contact details should fail validation"
        );
    }

    function test_ValidatePartyData_Invalid_CompanyNoJurisdiction() public pure {
        IAgreementTemplate.PartyData memory partyData = IAgreementTemplate.PartyData({
            name: "MetaLeX Labs",
            partyType: IAgreementTemplate.PartyType.Company,
            contactDetails: "legal@metalex.ai",
            jurisdiction: ""
        });

        assertFalse(
            _validatePartyData(partyData),
            "Company without jurisdiction should fail validation"
        );
    }

    // ============ PartyDataLib Tests ============

    function test_PartyDataLib_Equals() public pure {
        IAgreementTemplate.PartyData memory data1 = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        IAgreementTemplate.PartyData memory data2 = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        assertTrue(
            PartyDataLib.equals(data1, data2),
            "Identical party data should be equal"
        );
    }

    function test_PartyDataLib_NotEquals_Name() public pure {
        IAgreementTemplate.PartyData memory data1 = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        IAgreementTemplate.PartyData memory data2 = IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        assertFalse(
            PartyDataLib.equals(data1, data2),
            "Different names should not be equal"
        );
    }

    function test_PartyDataLib_NotEquals_PartyType() public pure {
        IAgreementTemplate.PartyData memory data1 = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        IAgreementTemplate.PartyData memory data2 = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Company,
            contactDetails: "alice@example.com",
            jurisdiction: "California"
        });

        assertFalse(
            PartyDataLib.equals(data1, data2),
            "Different party types should not be equal"
        );
    }

    function test_PartyDataLib_ToString() public pure {
        IAgreementTemplate.PartyData memory data = IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        });

        string memory str = PartyDataLib.toString(data);
        assertTrue(bytes(str).length > 0, "String representation should not be empty");
        
        // Check that name is in the string
        assertTrue(_contains(str, "Alice"), "String should contain name");
        assertTrue(_contains(str, "Individual"), "String should contain party type");
    }

    // ============ Helper Functions ============

    function _validatePartyData(IAgreementTemplate.PartyData memory partyData) internal pure returns (bool) {
        // Name is required
        if (bytes(partyData.name).length == 0) {
            return false;
        }

        // Contact details are required
        if (bytes(partyData.contactDetails).length == 0) {
            return false;
        }

        // Jurisdiction is required for companies
        if (
            partyData.partyType == IAgreementTemplate.PartyType.Company &&
            bytes(partyData.jurisdiction).length == 0
        ) {
            return false;
        }

        return true;
    }

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
}

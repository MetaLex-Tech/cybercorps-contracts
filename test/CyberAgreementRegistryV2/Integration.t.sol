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
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BorgAuth, BorgAuthACL} from "../../src/libs/auth.sol";
import {CyberAgreementRegistryV2} from "../../src/CyberAgreementRegistryV2.sol";
import {AgreementTemplateBase} from "../../src/templates/AgreementTemplateBase.sol";
import {SimpleSaleAgreementTemplate} from "../../src/templates/examples/SimpleSaleAgreementTemplate.sol";
import {IAgreementTemplate} from "../../src/interfaces/IAgreementTemplate.sol";
import {ICondition} from "../../src/interfaces/ICondition.sol";
import {ICyberAgreementRegistryV2} from "../../src/interfaces/ICyberAgreementRegistryV2.sol";
import {CyberAgreementV2Utils} from "./libs/CyberAgreementV2Utils.sol";

/**
 * @notice Mock condition for testing
 */
contract MockCondition is ICondition {
    bool public shouldPass;

    constructor(bool _shouldPass) {
        shouldPass = _shouldPass;
    }

    function setShouldPass(bool _shouldPass) external {
        shouldPass = _shouldPass;
    }

    function checkCondition(address, bytes4, bytes memory) external view returns (bool) {
        return shouldPass;
    }
}

/**
 * @notice Test template with closing conditions
 */
contract TestTemplateWithConditions is Initializable, BorgAuthACL, AgreementTemplateBase {
    function initialize(address _auth, string memory _contentUri, ICondition[] memory _conditions) public initializer {
        __BorgAuthACL_init(_auth);
        _setTemplateContentUri(_contentUri);
        for (uint256 i = 0; i < _conditions.length; i++) {
            _addClosingCondition(_conditions[i]);
        }
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

contract IntegrationTest is Test {
    // Test accounts
    address deployer;
    uint256 deployerPrivateKey;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;
    address chad;
    uint256 chadPrivateKey;

    // Contracts
    BorgAuth auth;
    CyberAgreementRegistryV2 registry;
    SimpleSaleAgreementTemplate simpleTemplate;

    bytes32 coreSalt = keccak256("IntegrationTest");

    function setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");
        (chad, chadPrivateKey) = makeAddrAndKey("chad");

        vm.startPrank(deployer);

        // Deploy BorgAuth
        auth = new BorgAuth{salt: coreSalt}(deployer);

        // Deploy CyberAgreementRegistryV2
        CyberAgreementRegistryV2 registryImpl = new CyberAgreementRegistryV2{salt: coreSalt}();
        registry = CyberAgreementRegistryV2(
            address(
                new ERC1967Proxy{salt: coreSalt}(
                    address(registryImpl),
                    abi.encodeWithSelector(
                        CyberAgreementRegistryV2.initialize.selector,
                        address(auth)
                    )
                )
            )
        );

        // Deploy SimpleSaleAgreementTemplate
        SimpleSaleAgreementTemplate templateImpl = new SimpleSaleAgreementTemplate{salt: coreSalt}();
        simpleTemplate = SimpleSaleAgreementTemplate(
            address(
                new ERC1967Proxy{salt: coreSalt}(
                    address(templateImpl),
                    abi.encodeWithSelector(
                        SimpleSaleAgreementTemplate.initialize.selector,
                        address(auth),
                        "ipfs://QmSaleTemplate/"
                    )
                )
            )
        );

        vm.stopPrank();
    }

    // ============ Complete Workflow Tests ============

    function test_CompleteWorkflow_CreateSignFinalize() public {
        // Step 1: Create agreement
        (
            bytes32 agreementId,
            bytes[] memory partyData,
            bytes memory templateData,
            address[] memory parties
        ) = _createSaleAgreementWithData();

        // Step 2: Alice signs
        _signAgreement(agreementId, partyData, templateData, parties, alice, alicePrivateKey, 0);
        assertTrue(registry.hasSigned(agreementId, alice), "Alice should have signed");
        assertFalse(registry.allPartiesSigned(agreementId), "Not all parties should have signed");

        // Step 3: Bob signs - should auto-finalize
        _signAgreement(agreementId, partyData, templateData, parties, bob, bobPrivateKey, 1);
        assertTrue(registry.hasSigned(agreementId, bob), "Bob should have signed");
        assertTrue(registry.allPartiesSigned(agreementId), "All parties should have signed");
        assertTrue(registry.isFinalized(agreementId), "Agreement should be finalized");

        // Verify events were emitted
        // (Events are checked in individual functions)
    }

    function test_CompleteWorkflow_CreateSignVoid() public {
        // Step 1: Create agreement with chad as finalizer (so it doesn't auto-finalize)
        (
            bytes32 agreementId,
            bytes[] memory partyData,
            bytes memory templateData,
            address[] memory parties
        ) = _createSaleAgreementWithFinalizer(chad);

        // Step 2: Both parties sign
        _signAgreement(agreementId, partyData, templateData, parties, alice, alicePrivateKey, 0);
        _signAgreement(agreementId, partyData, templateData, parties, bob, bobPrivateKey, 1);

        assertTrue(registry.allPartiesSigned(agreementId), "All parties should have signed");
        assertFalse(registry.isFinalized(agreementId), "Should not be finalized yet");

        // Step 3: Alice requests void
        bytes memory voidSignature = CyberAgreementV2Utils.signVoid(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.VOID_TYPEHASH(),
            agreementId,
            alice,
            alicePrivateKey
        );

        vm.prank(alice);
        registry.voidAgreement(agreementId, voidSignature);

        assertFalse(registry.isVoided(agreementId), "Should not be voided yet");

        // Step 4: Bob also requests void - agreement is voided
        voidSignature = CyberAgreementV2Utils.signVoid(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.VOID_TYPEHASH(),
            agreementId,
            bob,
            bobPrivateKey
        );

        vm.prank(bob);
        registry.voidAgreement(agreementId, voidSignature);

        assertTrue(registry.isVoided(agreementId), "Should be voided");
    }

    function test_CompleteWorkflow_WithFinalizer() public {
        // Step 1: Create agreement with Chad as finalizer
        (
            bytes32 agreementId,
            bytes[] memory partyData,
            bytes memory templateData,
            address[] memory parties
        ) = _createSaleAgreementWithFinalizer(chad);

        // Step 2: Both parties sign - but agreement is not finalized yet
        _signAgreement(agreementId, partyData, templateData, parties, alice, alicePrivateKey, 0);
        _signAgreement(agreementId, partyData, templateData, parties, bob, bobPrivateKey, 1);

        assertTrue(registry.allPartiesSigned(agreementId), "All parties should have signed");
        assertFalse(registry.isFinalized(agreementId), "Should not be finalized yet");

        // Step 3: Chad finalizes
        vm.prank(chad);
        registry.finalizeAgreement(agreementId);

        assertTrue(registry.isFinalized(agreementId), "Should be finalized");
    }

    // ============ Closing Conditions Tests ============

    function test_Workflow_WithClosingConditions_Pass() public {
        // Create condition that passes
        MockCondition passingCondition = new MockCondition(true);

        // Deploy template with condition
        vm.startPrank(deployer);
        ICondition[] memory conditions = new ICondition[](1);
        conditions[0] = passingCondition;

        TestTemplateWithConditions templateImpl = new TestTemplateWithConditions();
        TestTemplateWithConditions templateWithCondition = TestTemplateWithConditions(
            address(
                new ERC1967Proxy(
                    address(templateImpl),
                    abi.encodeWithSelector(
                        TestTemplateWithConditions.initialize.selector,
                        address(auth),
                        "ipfs://QmConditionTemplate/",
                        conditions
                    )
                )
            )
        );
        vm.stopPrank();

        // Create agreement
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes[] memory partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        bytes32 agreementId = registry.createAgreement(
            address(templateWithCondition),
            "",
            parties,
            partyData,
            address(0), // auto-finalize
            block.timestamp + 7 days
        );

        // Both parties sign - should auto-finalize because condition passes
        _signAgreementWithTemplate(agreementId, partyData, parties, alice, alicePrivateKey, 0, address(templateWithCondition));
        _signAgreementWithTemplate(agreementId, partyData, parties, bob, bobPrivateKey, 1, address(templateWithCondition));

        assertTrue(registry.isFinalized(agreementId), "Should be finalized because condition passes");
    }

    function test_Workflow_WithClosingConditions_Fail() public {
        // Create condition that fails
        MockCondition failingCondition = new MockCondition(false);

        // Deploy template with condition
        vm.startPrank(deployer);
        ICondition[] memory conditions = new ICondition[](1);
        conditions[0] = failingCondition;

        TestTemplateWithConditions templateImpl = new TestTemplateWithConditions();
        TestTemplateWithConditions templateWithCondition = TestTemplateWithConditions(
            address(
                new ERC1967Proxy(
                    address(templateImpl),
                    abi.encodeWithSelector(
                        TestTemplateWithConditions.initialize.selector,
                        address(auth),
                        "ipfs://QmConditionTemplate/",
                        conditions
                    )
                )
            )
        );
        vm.stopPrank();

        // Create agreement
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes[] memory partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        bytes32 agreementId = registry.createAgreement(
            address(templateWithCondition),
            "",
            parties,
            partyData,
            address(0), // auto-finalize
            block.timestamp + 7 days
        );

        // Both parties sign - should NOT auto-finalize because condition fails
        _signAgreementWithTemplate(agreementId, partyData, parties, alice, alicePrivateKey, 0, address(templateWithCondition));
        _signAgreementWithTemplate(agreementId, partyData, parties, bob, bobPrivateKey, 1, address(templateWithCondition));

        assertFalse(registry.isFinalized(agreementId), "Should not be finalized because condition fails");
        assertTrue(registry.allPartiesSigned(agreementId), "All parties should have signed");

        // Now make condition pass and finalize manually
        failingCondition.setShouldPass(true);

        vm.prank(chad);
        registry.finalizeAgreement(agreementId);

        assertTrue(registry.isFinalized(agreementId), "Should be finalized now");
    }

    function test_RevertIf_ManualFinalizeConditionsFail() public {
        // Create condition that fails
        MockCondition failingCondition = new MockCondition(false);

        // Deploy template with condition
        vm.startPrank(deployer);
        ICondition[] memory conditions = new ICondition[](1);
        conditions[0] = failingCondition;

        TestTemplateWithConditions templateImpl = new TestTemplateWithConditions();
        TestTemplateWithConditions templateWithCondition = TestTemplateWithConditions(
            address(
                new ERC1967Proxy(
                    address(templateImpl),
                    abi.encodeWithSelector(
                        TestTemplateWithConditions.initialize.selector,
                        address(auth),
                        "ipfs://QmConditionTemplate/",
                        conditions
                    )
                )
            )
        );
        vm.stopPrank();

        // Create agreement with no auto-finalize (has finalizer)
        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes[] memory partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        bytes32 agreementId = registry.createAgreement(
            address(templateWithCondition),
            "",
            parties,
            partyData,
            chad, // finalizer
            block.timestamp + 7 days
        );

        // Both parties sign
        _signAgreementWithTemplate(agreementId, partyData, parties, alice, alicePrivateKey, 0, address(templateWithCondition));
        _signAgreementWithTemplate(agreementId, partyData, parties, bob, bobPrivateKey, 1, address(templateWithCondition));

        // Chad tries to finalize but condition fails
        vm.prank(chad);
        vm.expectRevert(CyberAgreementRegistryV2.ConditionsNotMet.selector);
        registry.finalizeAgreement(agreementId);
    }

    // ============ Multiple Agreements Tests ============

    function test_MultipleAgreementsPerParty() public {
        // Create first agreement
        (bytes32 agreementId1,,,) = _createSaleAgreementWithData();
        
        // Warp to next block to ensure different salt
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        
        // Create second agreement
        (bytes32 agreementId2,,,) = _createSaleAgreementWithData();

        // Check Alice's agreements
        bytes32[] memory aliceAgreements = registry.getAgreementsForParty(alice);
        assertEq(aliceAgreements.length, 2, "Alice should have 2 agreements");
        assertEq(aliceAgreements[0], agreementId1, "First agreement ID mismatch");
        assertEq(aliceAgreements[1], agreementId2, "Second agreement ID mismatch");
    }

    // ============ Edge Cases ============

    function test_AgreementLifecycle_ExpireAfterSign() public {
        // Create agreement data first (capture timestamp)
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 10 days,
            description: "Expiring agreement"
        });

        bytes memory templateData = abi.encode(saleData);

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes[] memory partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        bytes32 agreementId = registry.createAgreement(
            address(simpleTemplate),
            templateData,
            parties,
            partyData,
            address(0),
            block.timestamp + 1 days
        );

        // Alice signs with the same data used for creation
        bytes memory signature = CyberAgreementV2Utils.signAgreement(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.AGREEMENT_TYPEHASH(),
            agreementId,
            address(simpleTemplate),
            templateData,
            parties,
            partyData[0],
            alicePrivateKey
        );

        vm.prank(alice);
        registry.signAgreement(agreementId, partyData[0], signature, false, "");

        // Warp past expiry
        vm.warp(block.timestamp + 2 days);

        // Bob tries to sign - should fail with AgreementExpired
        bytes memory bobSignature = CyberAgreementV2Utils.signAgreement(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.AGREEMENT_TYPEHASH(),
            agreementId,
            address(simpleTemplate),
            templateData,
            parties,
            partyData[1],
            bobPrivateKey
        );

        vm.prank(bob);
        vm.expectRevert(CyberAgreementRegistryV2.AgreementExpired.selector);
        registry.signAgreement(agreementId, partyData[1], bobSignature, false, "");
    }

    // ============ Helper Functions ============

    function _createSaleAgreementWithData()
        internal
        returns (
            bytes32 agreementId,
            bytes[] memory partyData,
            bytes memory templateData,
            address[] memory parties
        )
    {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        templateData = abi.encode(saleData);

        parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        agreementId = registry.createAgreement(
            address(simpleTemplate),
            templateData,
            parties,
            partyData,
            address(0), // no finalizer
            block.timestamp + 7 days
        );
    }

    function _createSaleAgreementWithFinalizer(address finalizer)
        internal
        returns (
            bytes32 agreementId,
            bytes[] memory partyData,
            bytes memory templateData,
            address[] memory parties
        )
    {
        SimpleSaleAgreementTemplate.SaleAgreementData memory saleData = SimpleSaleAgreementTemplate
            .SaleAgreementData({
            assetAddress: address(0x1234),
            assetAmount: 100,
            purchasePrice: 1 ether,
            paymentToken: address(0),
            deliveryDate: block.timestamp + 1 days,
            description: "Test sale"
        });

        templateData = abi.encode(saleData);

        parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        agreementId = registry.createAgreement(
            address(simpleTemplate),
            templateData,
            parties,
            partyData,
            finalizer,
            block.timestamp + 7 days
        );
    }

    function _signAgreement(
        bytes32 agreementId,
        bytes[] memory partyData,
        bytes memory templateData,
        address[] memory parties,
        address party,
        uint256 privateKey,
        uint256 partyIndex
    ) internal {
        bytes memory signature = CyberAgreementV2Utils.signAgreement(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.AGREEMENT_TYPEHASH(),
            agreementId,
            address(simpleTemplate),
            templateData,
            parties,
            partyData[partyIndex],
            privateKey
        );

        vm.prank(party);
        registry.signAgreement(agreementId, partyData[partyIndex], signature, false, "");
    }

    function _signAgreementWithTemplate(
        bytes32 agreementId,
        bytes[] memory partyData,
        address[] memory parties,
        address party,
        uint256 privateKey,
        uint256 partyIndex,
        address template
    ) internal {
        bytes memory signature = CyberAgreementV2Utils.signAgreement(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.AGREEMENT_TYPEHASH(),
            agreementId,
            template,
            "", // empty template data for test template
            parties,
            partyData[partyIndex],
            privateKey
        );

        vm.prank(party);
        registry.signAgreement(agreementId, partyData[partyIndex], signature, false, "");
    }

    // ============ Multiple Closing Conditions Tests ============

    function test_Workflow_WithMultipleConditions_AllPass() public {
        MockCondition condition1 = new MockCondition(true);
        MockCondition condition2 = new MockCondition(true);
        MockCondition condition3 = new MockCondition(true);

        vm.startPrank(deployer);
        ICondition[] memory conditions = new ICondition[](3);
        conditions[0] = condition1;
        conditions[1] = condition2;
        conditions[2] = condition3;

        TestTemplateWithConditions templateImpl = new TestTemplateWithConditions();
        TestTemplateWithConditions templateWithConditions = TestTemplateWithConditions(
            address(
                new ERC1967Proxy(
                    address(templateImpl),
                    abi.encodeWithSelector(
                        TestTemplateWithConditions.initialize.selector,
                        address(auth),
                        "ipfs://QmMultiCondition/",
                        conditions
                    )
                )
            )
        );
        vm.stopPrank();

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes[] memory partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        bytes32 agreementId = registry.createAgreement(
            address(templateWithConditions),
            "",
            parties,
            partyData,
            address(0),
            block.timestamp + 7 days
        );

        // Both parties sign - should auto-finalize because all conditions pass
        _signAgreementWithTemplate(agreementId, partyData, parties, alice, alicePrivateKey, 0, address(templateWithConditions));
        _signAgreementWithTemplate(agreementId, partyData, parties, bob, bobPrivateKey, 1, address(templateWithConditions));

        assertTrue(registry.isFinalized(agreementId), "Should be finalized because all conditions pass");
    }

    function test_Workflow_WithMultipleConditions_OneFails() public {
        MockCondition condition1 = new MockCondition(true);
        MockCondition condition2 = new MockCondition(false); // This one fails
        MockCondition condition3 = new MockCondition(true);

        vm.startPrank(deployer);
        ICondition[] memory conditions = new ICondition[](3);
        conditions[0] = condition1;
        conditions[1] = condition2;
        conditions[2] = condition3;

        TestTemplateWithConditions templateImpl = new TestTemplateWithConditions();
        TestTemplateWithConditions templateWithConditions = TestTemplateWithConditions(
            address(
                new ERC1967Proxy(
                    address(templateImpl),
                    abi.encodeWithSelector(
                        TestTemplateWithConditions.initialize.selector,
                        address(auth),
                        "ipfs://QmMultiCondition/",
                        conditions
                    )
                )
            )
        );
        vm.stopPrank();

        address[] memory parties = new address[](2);
        parties[0] = alice;
        parties[1] = bob;

        bytes[] memory partyData = new bytes[](2);
        partyData[0] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Alice",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "alice@example.com",
            jurisdiction: ""
        })
        );
        partyData[1] = abi.encode(
            IAgreementTemplate.PartyData({
            name: "Bob",
            partyType: IAgreementTemplate.PartyType.Individual,
            contactDetails: "bob@example.com",
            jurisdiction: ""
        })
        );

        vm.prank(alice);
        bytes32 agreementId = registry.createAgreement(
            address(templateWithConditions),
            "",
            parties,
            partyData,
            address(0),
            block.timestamp + 7 days
        );

        // Both parties sign - should NOT auto-finalize because one condition fails
        _signAgreementWithTemplate(agreementId, partyData, parties, alice, alicePrivateKey, 0, address(templateWithConditions));
        _signAgreementWithTemplate(agreementId, partyData, parties, bob, bobPrivateKey, 1, address(templateWithConditions));

        assertFalse(registry.isFinalized(agreementId), "Should not be finalized because one condition fails");
        assertTrue(registry.allPartiesSigned(agreementId), "All parties should have signed");

        // Fix the failing condition and finalize manually
        condition2.setShouldPass(true);

        vm.prank(chad);
        registry.finalizeAgreement(agreementId);

        assertTrue(registry.isFinalized(agreementId), "Should be finalized after fixing condition");
    }
}

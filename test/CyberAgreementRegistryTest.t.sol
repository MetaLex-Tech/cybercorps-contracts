// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";

contract CyberAgreementRegistryTest is Test {
    address deployer;
    uint256 deployerPrivateKey;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    bytes32 coreSalt = keccak256("CyberAgreementRegistryTest");
    
    BorgAuth coreAuth;
    CyberAgreementRegistry registry;
    
    bytes32 testTemplateId = keccak256("test-template-id");
    string testLegalDocUri = "ipfs://template";
    string[] testGlobalFields;
    string[] testPartyFields;

function setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vm.startPrank(deployer);

        coreAuth = new BorgAuth{salt: coreSalt}(deployer);

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: coreSalt}(
                    address(new CyberAgreementRegistry{salt: coreSalt}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(coreAuth)
                    )
                )
            )
        );

        testGlobalFields = new string[](1);
        testGlobalFields[0] = "Global Field";
        testPartyFields = new string[](2);
        testPartyFields[0] = "Officer Name";
        testPartyFields[1] = "Officer Title";
        registry.createTemplate(
            testTemplateId,
            "Test",
            testLegalDocUri,
            testGlobalFields,
            testPartyFields
        );

        vm.stopPrank();
    }

    /// @notice Should not allow escrow-sign when finalizer is undefined
    function test_RevertIf_signContractWithEscrowUndefinedFinalizer() public {
        uint256 salt = uint256(keccak256("test_RevertIf_signContractWithEscrowUndefinedFinalizer"));

        address[] memory parties = new address[](1);
        parties[0] = alice;

        string[] memory globalValues = new string[](1);
        globalValues[0] = "global value 0";

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](2);
        partyValues[0][0] = "Alice";
        partyValues[0][1] = "Test title";

        vm.prank(alice);
        bytes32 agreementId = registry.createContract(
            testTemplateId,
            salt,
            globalValues,
            parties,
            partyValues,
            "",
            address(0),
            block.timestamp + 10
        );

        vm.expectRevert(CyberAgreementRegistry.FinalizerNotDefined.selector);
        vm.prank(bob);
        registry.signContractWithEscrow(
            alice,
            agreementId,
            partyValues[0],
            "",
            false,
            ""
        );
    }
}

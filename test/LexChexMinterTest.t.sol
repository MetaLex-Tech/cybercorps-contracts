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

import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {LeXcheXUtils} from "./libs/LeXcheXUtils.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {Test, console} from "forge-std/Test.sol";

contract PaymentToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Payment Token", "TestUSDC") {
        _mint(msg.sender, initialSupply);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract LexChexMinterTest is Test {
    using ERC1967ProxyLib for address;

    uint256 adminPrivateKey = 1;
    address admin = vm.addr(adminPrivateKey);
    uint256 user1PrivateKey = 2;
    address user1 = vm.addr(user1PrivateKey);
    uint256 user2PrivateKey = 3;
    address user2 = vm.addr(user2PrivateKey);

    address owner = address(1);
    address agent = address(2);
    address treasury = address(3);

    ERC20 paymentToken = new PaymentToken(0);

    BorgAuth coreAuth;
    BorgAuth lexchexAuth;
    CyberAgreementRegistry registry;
    LeXcheX public lexchex;
    LeXcheXMinter public lexchexMinter;

    uint256 requestSalt = uint256(keccak256("LexChexMinterTestRequestSalt"));
    bytes32 templateId = bytes32(uint256(1));
    string[] globalFields = new string[](1);
    string[] partyFields = new string[](1);
    string[] globalValues = new string[](1);
    address[] parties = new address[](1);
    string[][] partyValues = new string[][](1);
    bytes32 agreementId;
    bytes agreementSignature;
    string[] portfolio = new string[](2);
    LeXcheXMinter.MintRequest request;
    bytes authoritySignature;

    function setUp() public {
        bytes32 salt = bytes32(keccak256("LexChexMinterTest"));

        vm.startPrank(owner);

        coreAuth = new BorgAuth(owner);
        lexchexAuth = new BorgAuth(owner);

        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(coreAuth))
        )));

        lexchex = LeXcheX(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheX{salt: salt}()),
            abi.encodeWithSelector(LeXcheX.initialize.selector, address(lexchexAuth))
        )));

        lexchexMinter = LeXcheXMinter(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheXMinter{salt: salt}()),
            abi.encodeWithSelector(
                LeXcheXMinter.initialize.selector,
                address(coreAuth),
                address(lexchex),
                address(registry),
                address(paymentToken),
                treasury
            )
        )));

        // Grant LeXcheXMinter admin access to LeXcheX
        lexchexAuth.updateRole(address(lexchexMinter), lexchexAuth.ADMIN_ROLE());
        // Grant admin EOA access to minter
        coreAuth.updateRole(admin, coreAuth.ADMIN_ROLE());

        vm.stopPrank();

        //
        // Prepare a valid request
        //

        // Prepare funds for agent
        deal(address(paymentToken), agent, 10e6, true);
        vm.prank(agent);
        paymentToken.approve(address(lexchexMinter), 10e6);

        // TODO Use more realistic values
        string memory legalContractUri = "ipfs.io/ipfs/[cid]";
        globalFields[0] = "Global Field 1";
        partyFields[0] = "Party Field 1";

        vm.prank(owner);
        registry.createTemplate(
            templateId,
            "Test Template",
            legalContractUri,
            globalFields,
            partyFields
        );

        globalValues[0] = "Global Value 1";

        parties[0] = address(user1);

        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        agreementId = keccak256(
            abi.encode(
                templateId,
                requestSalt,
                globalValues,
                parties
            )
        );

        agreementSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            legalContractUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            user1PrivateKey
        );

        portfolio[0] = "0x123...";
        portfolio[1] = "bc1q...";
    }

    function testMetadata() public view {
        assertEq(lexchexMinter.auth(), address(coreAuth), "Unexpected auth");
        assertEq(lexchexMinter.lexchex(), address(lexchex), "Unexpected lexchex");
        assertEq(lexchexMinter.dealRegistry(), address(registry), "Unexpected dealRegistry");
        assertEq(lexchexMinter.paymentToken(), address(paymentToken), "Unexpected paymentToken");
        assertEq(lexchexMinter.treasury(), address(treasury), "Unexpected treasury");
        assertEq(lexchexMinter.version(), "1", "Unexpected version");
        assertEq(lexchexMinter.DOMAIN_SEPARATOR(), keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("LeXcheXMinter")),
                keccak256(bytes("1")),
                block.chainid,
                address(lexchexMinter)
            )
        ), "Unexpected DOMAIN_SEPARATOR");
        assertEq(lexchexMinter.AUTHORITY_TYPEHASH(), keccak256(
            "AuthorityData(address owner,string name,string entityType,string jurisdiction,string contact,uint256 mintPrice,uint256 expiry)"
        ), "Unexpected AUTHORITY_TYPEHASH");
    }

    function test_RevertIf_initializeImplementation() public {
        LeXcheXMinter impl = new LeXcheXMinter();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        impl.initialize(
            address(coreAuth),
            address(lexchex),
            address(registry),
            address(paymentToken),
            treasury
        );
    }

    function testRequestMint() public {
        uint256 agentPaymentBalanceBefore = paymentToken.balanceOf(agent);
        uint256 treasuryPaymentBalanceBefore = paymentToken.balanceOf(treasury);

        request = LeXcheXMinter.MintRequest({
            owner: user1,
            name: "Test Entity",
            entityType: "LLC",
            jurisdiction: "Delaware",
            contact: "test@test.com",
            mintPrice: 10e6,
            expiry: block.timestamp + 1 days
        });

        authoritySignature = LeXcheXUtils.signAuthorizationTypedData(
            vm,
            lexchexMinter.DOMAIN_SEPARATOR(),
            lexchexMinter.AUTHORITY_TYPEHASH(),
            LeXcheXMinter.AuthorityData({
                owner: request.owner,
                name: request.name,
                entityType: request.entityType,
                jurisdiction: request.jurisdiction,
                contact: request.contact,
                mintPrice: request.mintPrice,
                expiry: request.expiry
            }),
            adminPrivateKey
        );

        // Request should succeed

        // Agreement should be fully signed
        vm.expectEmit(true, true, true, true);
        emit CyberAgreementRegistry.ContractFullySigned(agreementId, block.timestamp);
        vm.expectEmit(true, true, true, true);
        emit LeXcheXMinter.MintRequested(user1, 10e6, agreementId);
        vm.expectEmit(true, true, true, true);
        emit LeXcheXMinter.MintCompleted(user1, 0, agreementId);
        vm.prank(agent);
        lexchexMinter.requestMint(
            request,
            templateId,
            requestSalt,
            globalValues,
            parties,
            partyValues,
            agreementSignature,
            authoritySignature
        );
        
        assertEq(lexchex.balanceOf(user1), 1, "user1 should get one token");
        assertEq(lexchex.ownerOf(0), user1, "token should be owned by user 1");
        assertEq(lexchex.accreditations(0).agreementId, agreementId, "agreement ID should be set");
        assertEq(agentPaymentBalanceBefore - paymentToken.balanceOf(agent), 10e6, "payment amount is not correct");
        assertEq(paymentToken.balanceOf(treasury) - treasuryPaymentBalanceBefore, 10e6, "treasury received amount is not correct");
    }

    function testRequestMintFree() public {
        uint256 agentPaymentBalanceBefore = paymentToken.balanceOf(agent);
        uint256 treasuryPaymentBalanceBefore = paymentToken.balanceOf(treasury);

        request = LeXcheXMinter.MintRequest({
            owner: user1,
            name: "Test Entity",
            entityType: "LLC",
            jurisdiction: "Delaware",
            contact: "test@test.com",
            mintPrice: 0, // free
            expiry: block.timestamp + 1 days
        });

        authoritySignature = LeXcheXUtils.signAuthorizationTypedData(
            vm,
            lexchexMinter.DOMAIN_SEPARATOR(),
            lexchexMinter.AUTHORITY_TYPEHASH(),
            LeXcheXMinter.AuthorityData({
                owner: request.owner,
                name: request.name,
                entityType: request.entityType,
                jurisdiction: request.jurisdiction,
                contact: request.contact,
                mintPrice: request.mintPrice,
                expiry: request.expiry
            }),
            adminPrivateKey
        );

        // Request should succeed

        // Agreement should be fully signed
        vm.expectEmit(true, true, true, true);
        emit CyberAgreementRegistry.ContractFullySigned(agreementId, block.timestamp);
        vm.expectEmit(true, true, true, true);
        emit LeXcheXMinter.MintRequested(user1, 0, agreementId);
        vm.expectEmit(true, true, true, true);
        emit LeXcheXMinter.MintCompleted(user1, 0, agreementId);
        vm.prank(agent);
        lexchexMinter.requestMint(
            request,
            templateId,
            requestSalt,
            globalValues,
            parties,
            partyValues,
            agreementSignature,
            authoritySignature
        );

        assertEq(lexchex.balanceOf(user1), 1, "user1 should get one token");
        assertEq(lexchex.ownerOf(0), user1, "token should be owned by user 1");
        assertEq(lexchex.accreditations(0).agreementId, agreementId, "agreement ID should be set");
        assertEq(paymentToken.balanceOf(agent), agentPaymentBalanceBefore, "payment should be free");
        assertEq(paymentToken.balanceOf(treasury), treasuryPaymentBalanceBefore, "treasury should not receive payment");
    }

    function test_RevertIf_invalidAuthoritySignature() public {
        request = LeXcheXMinter.MintRequest({
            owner: user1,
            name: "Test Entity",
            entityType: "LLC",
            jurisdiction: "Delaware",
            contact: "test@test.com",
            mintPrice: 10e6,
            expiry: block.timestamp + 1 days
        });

        // Create an invalid authority signature
        authoritySignature = LeXcheXUtils.signAuthorizationTypedData(
            vm,
            lexchexMinter.DOMAIN_SEPARATOR(),
            lexchexMinter.AUTHORITY_TYPEHASH(),
            LeXcheXMinter.AuthorityData({
                owner: request.owner,
                name: request.name,
                entityType: request.entityType,
                jurisdiction: request.jurisdiction,
                contact: request.contact,
                mintPrice: request.mintPrice,
                expiry: request.expiry
            }),
            user1PrivateKey // Intentionally wrong private key
        );

        // Request should fail
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, coreAuth.ADMIN_ROLE(), user1));
        vm.prank(agent);
        lexchexMinter.requestMint(
            request,
            templateId,
            requestSalt,
            globalValues,
            parties,
            partyValues,
            agreementSignature,
            authoritySignature
        );
    }

    function testSetLexchex() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, coreAuth.OWNER_ROLE(), admin));
        vm.prank(admin);
        lexchexMinter.setLexchex(address(0x1));

        // Owner should be allowed
        vm.prank(owner);
        lexchexMinter.setLexchex(address(0x1));
        assertEq(lexchexMinter.lexchex(), address(0x1), "lexchex should've been updated");
    }

    function testSetDealRegistry() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, coreAuth.OWNER_ROLE(), admin));
        vm.prank(admin);
        lexchexMinter.setDealRegistry(address(0x1));

        // Owner should be allowed
        vm.prank(owner);
        lexchexMinter.setDealRegistry(address(0x1));
        assertEq(lexchexMinter.dealRegistry(), address(0x1), "dealRegistry should've been updated");
    }

    function testSetPaymentToken() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, coreAuth.OWNER_ROLE(), admin));
        vm.prank(admin);
        lexchexMinter.setPaymentToken(address(0x1));

        // Owner should be allowed
        vm.prank(owner);
        lexchexMinter.setPaymentToken(address(0x1));
        assertEq(lexchexMinter.paymentToken(), address(0x1), "paymentToken should've been updated");
    }

    function testSetTreasury() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, coreAuth.OWNER_ROLE(), admin));
        vm.prank(admin);
        lexchexMinter.setTreasury(address(0x1));

        // Owner should be allowed
        vm.prank(owner);
        lexchexMinter.setTreasury(address(0x1));
        assertEq(lexchexMinter.treasury(), address(0x1), "treasury should've been updated");
    }

    function testUpgradeLeXcheX() public {
        // Deploy new implementation
        address newImplementation = address(new LeXcheXMinter());

        // Upgrade to new implementation without initialization data

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, coreAuth.OWNER_ROLE(), admin));
        vm.prank(admin);
        lexchexMinter.upgradeToAndCall(newImplementation, "");

        // Owner should be able to upgrade it
        vm.prank(owner);
        lexchexMinter.upgradeToAndCall(newImplementation, "");
        assertEq(address(lexchexMinter).getErc1967Implementation(vm), newImplementation);

        // Verify requestMint() should still work
        testRequestMint();
    }
}

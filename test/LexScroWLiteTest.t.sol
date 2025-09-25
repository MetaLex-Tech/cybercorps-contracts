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
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "openzeppelin-contracts/token/ERC1155/ERC1155.sol";
import {ERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LexScroWLite} from "../src/libs/LexScroWLite.sol";
import {LexScrowStorage, Token, TokenType, EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {Endorsement} from "../src/storage/CyberCertPrinterStorage.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract ERC721Mock is ERC721Enumerable {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function mint(address to) public returns(uint256) {
        uint256 tokenId = totalSupply();
        _safeMint(to, tokenId);
        return tokenId;
    }
}

contract ERC721WithEndorsementMock is ERC721Mock {
    constructor(string memory _name, string memory _symbol) ERC721Mock(_name, _symbol) {}

    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        // no-op
    }
}

contract ERC1155Mock is ERC1155 {
    constructor(string memory uri_) ERC1155(uri_) {}

    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount,"");
    }
}

contract LexScroWLiteMock is LexScroWLite {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _corp, address _dealRegistry) public initializer {
        __LexScroWLite_init(_corp, _dealRegistry);
    }

    function createEscrow_(bytes32 agreementId, address counterParty, Token[] memory corpAssets, Token[] memory buyerAssets, uint256 expiry) public {
        createEscrow(agreementId, counterParty, corpAssets, buyerAssets, expiry);
    }

    function updateEscrow_(bytes32 agreementId, address counterParty, string memory buyerName) public {
        updateEscrow(agreementId, counterParty, buyerName);
    }

    function handleCounterPartyPayment_(bytes32 agreementId) public {
        handleCounterPartyPayment(agreementId);
    }

    function finalizeEscrow_(bytes32 agreementId) public {
        finalizeEscrow(agreementId);
    }

    function voidAndRefund_(bytes32 agreementId) public {
        voidAndRefund(agreementId);
    }
}

contract CyberAgreementRegistryMock {
    mapping(bytes32 => bool) public isVoided;

    function mockVoidAgreement(bytes32 agreementId, bool _isVoided) public {
        isVoided[agreementId] = _isVoided;
    }
}

contract CyberCorpMock {
    address public companyPayable;

    constructor(address _companyPayable) {
        companyPayable = _companyPayable;
    }
}

contract LexScroWLiteTest is Test {

    bytes32 public salt = keccak256("LexScroWLiteTest");

    uint256 public ownerPrivateKey = uint256(salt) + 0;
    address public owner = vm.addr(ownerPrivateKey);

    address public companyPayable = address(1000);
    address public companyOwner = address(1001);
    address public alice = address(1002);
    address public bob = address(1003);

    ERC20Mock public corpTokenErc20 = new ERC20Mock("Corp ERC20", "CORP20");
    ERC721Mock public corpTokenErc721 = new ERC721Mock("Corp ERC721", "CORP721");
    ERC721WithEndorsementMock public corpTokenErc721WithEndorsement = new ERC721WithEndorsementMock("Corp ERC721 with Endorsement", "CORP721E");
    ERC1155Mock public corpTokenErc1155 = new ERC1155Mock("corp/erc1155");
    uint256 public corpTokenErc721Id;
    uint256 public corpTokenErc721WithEndorsementId;
    uint256 public corpTokenErc1155Id = 0;

    ERC20Mock public buyerTokenErc20 = new ERC20Mock("Buyer ERC20", "BUY20");
    ERC721Mock public buyerTokenErc721 = new ERC721Mock("Buyer ERC721", "BUY721");
    ERC1155Mock public buyerTokenErc1155 = new ERC1155Mock("buyer/erc1155");
    uint256 public buyerTokenErc721Id;
    uint256 public buyerTokenErc1155Id = 0;

    CyberAgreementRegistryMock public registry;
    CyberCorpMock public corp;
    LexScroWLiteMock public lexScrow;

    function setUp() public {
        registry = new CyberAgreementRegistryMock{salt: salt}();

        corp = new CyberCorpMock{salt: salt}(companyPayable);

        lexScrow = LexScroWLiteMock(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new LexScroWLiteMock{salt: salt}()),
                    abi.encodeWithSelector(
                        LexScroWLiteMock.initialize.selector,
                        address(corp),
                        address(registry)
                    )
                )
            )
        );

        // Prepare funds

        corpTokenErc20.mint(address(lexScrow), 10 ether);
        corpTokenErc721Id = corpTokenErc721.mint(address(lexScrow));
        corpTokenErc721WithEndorsementId = corpTokenErc721WithEndorsement.mint(address(lexScrow));
        corpTokenErc1155.mint(address(lexScrow), corpTokenErc1155Id, 10 ether);

        buyerTokenErc20.mint(alice, 100 ether);
        buyerTokenErc721Id = buyerTokenErc721.mint(alice);
        buyerTokenErc1155.mint(alice, buyerTokenErc1155Id, 100 ether);

        vm.startPrank(alice);
        buyerTokenErc20.approve(address(lexScrow), 100 ether);
        buyerTokenErc721.approve(address(lexScrow), buyerTokenErc721Id);
        buyerTokenErc1155.setApprovalForAll(address(lexScrow), true);
        vm.stopPrank();
    }

    function test_NormalFlow() public {

        // Escrow configs

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = _getCorpAssets();
        Token[] memory buyerAssets = _getBuyerAssets();

        // Run through the typical escrow flow

        uint256 aliceCorpTokenErc20BalancesBefore = corpTokenErc20.balanceOf(alice);
        assertEq(corpTokenErc721.ownerOf(corpTokenErc721Id), address(lexScrow), "Corp ERC721 token should be in escrow");
        uint256 aliceCorpTokenErc1155BalanceBefore = corpTokenErc1155.balanceOf(alice, corpTokenErc1155Id);

        uint256 companyBuyerTokenErc20BalancesBefore = buyerTokenErc20.balanceOf(companyPayable);
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), alice, "Alice should own Buyer ERC721 token before payment");
        uint256 companyBuyerTokenErc1155BalanceBefore = buyerTokenErc1155.balanceOf(companyPayable, buyerTokenErc1155Id);

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);

        lexScrow.handleCounterPartyPayment_(agreementId);

        lexScrow.finalizeEscrow_(agreementId);

        // Verify the assets are exchanged

        assertEq(
            corpTokenErc20.balanceOf(alice),
            aliceCorpTokenErc20BalancesBefore + 10 ether,
            "Alice should receive Corp ERC20 tokens"
        );
        assertEq(corpTokenErc721.ownerOf(corpTokenErc721Id), alice, "Alice should receive Corp ERC721 tokens");
        assertEq(
            corpTokenErc1155.balanceOf(alice, corpTokenErc1155Id),
            aliceCorpTokenErc1155BalanceBefore + 10 ether,
            "Alice should receive Corp ERC1155 tokens"
        );

        assertEq(
            buyerTokenErc20.balanceOf(companyPayable),
            companyBuyerTokenErc20BalancesBefore + 100 ether,
            "Company should receive Buyer ERC20 tokens"
        );
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), companyPayable, "Company should receive Buyer ERC721 tokens");
        assertEq(
            buyerTokenErc1155.balanceOf(companyPayable, buyerTokenErc1155Id),
            companyBuyerTokenErc1155BalanceBefore + 100 ether,
            "Company should receive Buyer ERC1155 tokens"
        );
    }

    function test_PaymentFlow_HandleCounterPartyPayment() public {
        // handleCounterPartyPayment() should be the only function that pull assets from the buyer,
        // and the escrow status must change to PAID after it, or otherwise `voidAndRefund()` would fail

        // Prepare Escrow

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = _getCorpAssets();
        Token[] memory buyerAssets = _getBuyerAssets();

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);

        // Asset should stay with the buyer until handleCounterPartyPayment() is called

        assertEq(buyerTokenErc20.balanceOf(alice), 100 ether, "Alice should own Buyer ERC20 token before payment");
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), alice, "Alice should own Buyer ERC721 token before payment");
        assertEq(buyerTokenErc1155.balanceOf(alice, buyerTokenErc1155Id), 100 ether, "Alice should own Buyer ERC1155 token before payment");

        // Verify escrow status
        assertEq(uint8(lexScrow.getEscrowDetails(agreementId).status), uint8(EscrowStatus.PENDING), "Escrow status should be PENDING");

        lexScrow.handleCounterPartyPayment_(agreementId);

        // Verify assets are in escrow

        assertEq(buyerTokenErc20.balanceOf(alice), 0 ether, "Alice should have paid Buyer ERC20 token");
        assertEq(buyerTokenErc1155.balanceOf(alice, buyerTokenErc1155Id), 0 ether, "Alice should have paid Buyer ERC1155 token");

        assertEq(buyerTokenErc20.balanceOf(address(lexScrow)), 100 ether, "Alice's ERC20 token should be in escrow");
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), address(lexScrow), "Alice's ERC712 token should be in escrow");
        assertEq(buyerTokenErc1155.balanceOf(address(lexScrow), buyerTokenErc1155Id), 100 ether, "Alice's ERC1155 token should be in escrow");

        // Verify escrow status
        assertEq(uint8(lexScrow.getEscrowDetails(agreementId).status), uint8(EscrowStatus.PAID), "Escrow status should be PAID");
    }

    function test_PaymentFlow_FinalizeEscrow() public {
        // finalizeEscrow() should be the only function that settles and transfer all assets to their destinations,
        // and the escrow status should change to FINALIZED after it.

        // Prepare Escrow

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = _getCorpAssets();
        Token[] memory buyerAssets = _getBuyerAssets();

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);
        lexScrow.handleCounterPartyPayment_(agreementId);

        // All assets should be in escrow until finalized

        assertEq(corpTokenErc20.balanceOf(address(lexScrow)), 10 ether, "Corp's ERC20 token should be in escrow");
        assertEq(corpTokenErc721.ownerOf(corpTokenErc721Id), address(lexScrow), "Corp's ERC712 token should be in escrow");
        assertEq(corpTokenErc1155.balanceOf(address(lexScrow), corpTokenErc1155Id), 10 ether, "Corp's ERC1155 token should be in escrow");
        assertEq(buyerTokenErc20.balanceOf(address(lexScrow)), 100 ether, "Alice's ERC20 token should be in escrow");
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), address(lexScrow), "Alice's ERC712 token should be in escrow");
        assertEq(buyerTokenErc1155.balanceOf(address(lexScrow), buyerTokenErc1155Id), 100 ether, "Alice's ERC1155 token should be in escrow");

        // Verify escrow status
        assertEq(uint8(lexScrow.getEscrowDetails(agreementId).status), uint8(EscrowStatus.PAID), "Escrow status should be PAID");

        lexScrow.finalizeEscrow_(agreementId);

        // Verify assets are distributed

        assertEq(corpTokenErc20.balanceOf(alice), 10 ether, "Alice should have Corp's ERC20 token");
        assertEq(corpTokenErc721.ownerOf(corpTokenErc721Id), alice, "Alice should have Corp's ERC712 token");
        assertEq(corpTokenErc1155.balanceOf(alice, corpTokenErc1155Id), 10 ether, "Alice should have Corp's ERC1155");
        assertEq(buyerTokenErc20.balanceOf(companyPayable), 100 ether, "Company should have Alice's ERC20 token");
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), companyPayable, "Company should have Alice's ERC712 token");
        assertEq(buyerTokenErc1155.balanceOf(companyPayable, buyerTokenErc1155Id), 100 ether, "Company should have Alice's ERC1155 token");

        // Verify escrow status
        assertEq(uint8(lexScrow.getEscrowDetails(agreementId).status), uint8(EscrowStatus.FINALIZED), "Escrow status should be FINALIZED");
    }

    function test_PaymentFlow_VoidAndRefund() public {
        // voidAndRefund() should be the only function that returns assets to the buyer, and it should verify buyer's
        // payment status before and update it after refund.

        // Prepare Escrow

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = _getCorpAssets();
        Token[] memory buyerAssets = _getBuyerAssets();

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);
        lexScrow.handleCounterPartyPayment_(agreementId);

        // All assets should be in escrow until finalized

        assertEq(corpTokenErc20.balanceOf(address(lexScrow)), 10 ether, "Corp's ERC20 token should be in escrow");
        assertEq(corpTokenErc721.ownerOf(corpTokenErc721Id), address(lexScrow), "Corp's ERC712 token should be in escrow");
        assertEq(corpTokenErc1155.balanceOf(address(lexScrow), corpTokenErc1155Id), 10 ether, "Corp's ERC1155 token should be in escrow");
        assertEq(buyerTokenErc20.balanceOf(address(lexScrow)), 100 ether, "Alice's ERC20 token should be in escrow");
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), address(lexScrow), "Alice's ERC712 token should be in escrow");
        assertEq(buyerTokenErc1155.balanceOf(address(lexScrow), buyerTokenErc1155Id), 100 ether, "Alice's ERC1155 token should be in escrow");

        // Verify escrow status
        assertEq(uint8(lexScrow.getEscrowDetails(agreementId).status), uint8(EscrowStatus.PAID), "Escrow status should be PAID");

        registry.mockVoidAgreement(agreementId, true);
        lexScrow.voidAndRefund_(agreementId);

        // Verify assets are returned

        assertEq(buyerTokenErc20.balanceOf(alice), 100 ether, "Alice should have ERC20 token refund");
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), alice, "Alice should have ERC712 token refund");
        assertEq(buyerTokenErc1155.balanceOf(alice, buyerTokenErc1155Id), 100 ether, "Alice should have ERC1155 token refund");

        // Note LexScroWLite by default does not implement corp asset refunds, so they will be stuck in escrow

        assertEq(corpTokenErc20.balanceOf(address(lexScrow)), 10 ether, "Corp's ERC20 token should still be in escrow");
        assertEq(corpTokenErc721.ownerOf(corpTokenErc721Id), address(lexScrow), "Corp's ERC712 token should still be in escrow");
        assertEq(corpTokenErc1155.balanceOf(address(lexScrow), corpTokenErc1155Id), 10 ether, "Corp's ERC1155 token should still be in escrow");

        // Verify escrow status
        assertEq(uint8(lexScrow.getEscrowDetails(agreementId).status), uint8(EscrowStatus.VOIDED), "Escrow status should be VOIDED");
    }

    function test_RevertIf_PaymentFlow_VoidAndRefundWithoutVoidedAgreement() public {
        // Prepare Escrow

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = _getCorpAssets();
        Token[] memory buyerAssets = _getBuyerAssets();

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);
        lexScrow.handleCounterPartyPayment_(agreementId);

        // Should fail since agreement is not voided first
        vm.expectRevert(LexScroWLite.DealNotVoided.selector);
        lexScrow.voidAndRefund_(agreementId);
    }

    function test_UpdateEscrowNonERC721() public {
        // Prepare Escrow

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = new Token[](2);
        corpAssets[0] = Token({
            tokenType: TokenType.ERC20,
            tokenAddress: address(corpTokenErc20),
            tokenId: 0,
            amount: 10 ether
        });
        corpAssets[1] = Token({
            tokenType: TokenType.ERC1155,
            tokenAddress: address(corpTokenErc1155),
            tokenId: corpTokenErc1155Id,
            amount: 10 ether
        });
        Token[] memory buyerAssets = _getBuyerAssets();

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);

        // updateEscrow should update the counter-party of the escrow

        lexScrow.updateEscrow_(agreementId, bob, "Bob");

        assertEq(lexScrow.getEscrowDetails(agreementId).counterParty, bob);
    }

    function test_UpdateEscrowERC721() public {
        // updateEscrow should update the counter-party of the escrow, and if the token is ERC721,
        // it assumes the token implements ICyberCertPrinter and will add endorsement to it.

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = new Token[](1);
        corpAssets[0] = Token({
            tokenType: TokenType.ERC721,
            tokenAddress: address(corpTokenErc721WithEndorsement),
            tokenId: corpTokenErc721Id,
            amount: 1
        });
        Token[] memory buyerAssets = _getBuyerAssets();

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);

        // updateEscrow should fail because the corpAssets contain non-ICyberCertPrinter ERC-721 tokens

        lexScrow.updateEscrow_(agreementId, bob, "Bob");
    }

    function test_RevertIf_UpdateEscrowERC721WithoutEndorsement() public {
        // updateEscrow assumes an ERC721 token implements ICyberCertPrinter and
        // will fail if it does not implement `addEndorsement()`

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");
        Token[] memory corpAssets = _getCorpAssets();
        Token[] memory buyerAssets = _getBuyerAssets();

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);

        // updateEscrow should fail because the corpAssets contain non-ICyberCertPrinter ERC-721 tokens
        vm.expectRevert(); // ex. unrecognized function selector 0x94b5611f for contract 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef, which has no fallback function
        lexScrow.updateEscrow_(agreementId, bob, "Bob");
    }

    function test_ConditionCheck() public {
        // TODO: WIP
    }

    function test_AddCondition() public {
        // TODO: WIP
    }

    function test_RemoveCondition() public {
        // TODO: WIP
    }

    function test_VoidExpiredUnpaid() public {
        // TODO: WIP
    }

    function test_VoidExpiredPaid() public {
        // TODO: WIP
    }

    function test_VoidByPartyUnpaid() public {
        // TODO: WIP
    }

    function test_VoidByPartyPaid() public {
        // TODO: WIP
    }

    function _getCorpAssets() internal returns(Token[] memory) {
        Token[] memory corpAssets = new Token[](3);
        corpAssets[0] = Token({
            tokenType: TokenType.ERC20,
            tokenAddress: address(corpTokenErc20),
            tokenId: 0,
            amount: 10 ether
        });
        corpAssets[1] = Token({
            tokenType: TokenType.ERC721,
            tokenAddress: address(corpTokenErc721),
            tokenId: corpTokenErc721Id,
            amount: 1
        });
        corpAssets[2] = Token({
            tokenType: TokenType.ERC1155,
            tokenAddress: address(corpTokenErc1155),
            tokenId: corpTokenErc1155Id,
            amount: 10 ether
        });
        return corpAssets;
    }

    function _getBuyerAssets() internal returns(Token[] memory) {
        Token[] memory buyerAssets = new Token[](3);
        buyerAssets[0] = Token({
            tokenType: TokenType.ERC20,
            tokenAddress: address(buyerTokenErc20),
            tokenId: 0,
            amount: 100 ether
        });
        buyerAssets[1] = Token({
            tokenType: TokenType.ERC721,
            tokenAddress: address(buyerTokenErc721),
            tokenId: buyerTokenErc721Id,
            amount: 1
        });
        buyerAssets[2] = Token({
            tokenType: TokenType.ERC1155,
            tokenAddress: address(buyerTokenErc1155),
            tokenId: buyerTokenErc1155Id,
            amount: 100 ether
        });
        return buyerAssets;
    }
}

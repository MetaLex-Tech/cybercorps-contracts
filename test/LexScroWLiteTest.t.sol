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
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LexScroWLite} from "../src/libs/LexScroWLite.sol";
import {LexScrowStorage, Token, TokenType} from "../src/storage/LexScrowStorage.sol";

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

    function handleCounterPartyPayment_(bytes32 agreementId) public {
        handleCounterPartyPayment(agreementId);
    }

    function finalizeEscrow_(bytes32 agreementId) public {
        finalizeEscrow(agreementId);
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

    ERC20Mock public corpTokenErc20 = new ERC20Mock("Corp ERC20", "CORP20");
    ERC721Mock public corpTokenErc721 = new ERC721Mock("Corp ERC721", "CORP721");
    ERC1155Mock public corpTokenErc1155 = new ERC1155Mock("corp/erc1155");
    uint256 public corpTokenErc721Id;
    uint256 public corpTokenErc1155Id = 0;

    ERC20Mock public buyerTokenErc20 = new ERC20Mock("Buyer ERC20", "BUY20");
    ERC721Mock public buyerTokenErc721 = new ERC721Mock("Buyer ERC721", "BUY721");
    ERC1155Mock public buyerTokenErc1155 = new ERC1155Mock("buyer/erc1155");
    uint256 public buyerTokenErc721Id;
    uint256 public buyerTokenErc1155Id = 0;

    CyberAgreementRegistry public registry;
    CyberCorpMock public corp;
    LexScroWLiteMock public lexScrow;

    function setUp() public {
        BorgAuth auth = new BorgAuth{salt: salt}(owner);

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberAgreementRegistry{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(auth)
                    )
                )
            )
        );

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
        corpTokenErc1155.mint(address(lexScrow), corpTokenErc1155Id, 10 ether);

        buyerTokenErc20.mint(alice, 100 ether);
        buyerTokenErc721Id = buyerTokenErc721.mint(alice);
        buyerTokenErc1155.mint(alice, buyerTokenErc1155Id, 100 ether);
    }

    function test_NormalFlow() public {

        // Escrow configs

        bytes32 agreementId = keccak256("LexScroWLiteTest.Agreement");

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

        // Run through the typical escrow flow

        // Buyer preparations
        vm.startPrank(alice);
        buyerTokenErc20.approve(address(lexScrow), 100 ether);
        buyerTokenErc721.approve(address(lexScrow), buyerTokenErc721Id);
        buyerTokenErc1155.setApprovalForAll(address(lexScrow), true);
        vm.stopPrank();

        uint256 aliceCorpTokenErc20BalancesBefore = corpTokenErc20.balanceOf(alice);
        assertEq(corpTokenErc721.ownerOf(corpTokenErc721Id), address(lexScrow), "Corp ERC721 token should be in escrow");
        uint256 aliceCorpTokenErc1155BalanceBefore = corpTokenErc1155.balanceOf(alice, corpTokenErc1155Id);

        uint256 companyBuyerTokenErc20BalancesBefore = buyerTokenErc20.balanceOf(companyPayable);
        assertEq(buyerTokenErc721.ownerOf(buyerTokenErc721Id), alice, "Alice should own Buyer ERC721 token before payment");
        uint256 companyBuyerTokenErc1155BalanceBefore = buyerTokenErc1155.balanceOf(companyPayable, buyerTokenErc1155Id);

        lexScrow.createEscrow_(agreementId, alice, corpAssets, buyerAssets, block.timestamp);

        lexScrow.handleCounterPartyPayment_(agreementId);

        lexScrow.finalizeEscrow_(agreementId);

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

    function test_NormalFlowWithCondition() public {}

    function test_UpdateEscrowNonERC721() public {}

    function test_UpdateEscrowERC721() public {}

    function test_AddCondition() public {}

    function test_RemoveCondition() public {}

    function test_VoidExpiredUnpaid() public {}

    function test_VoidExpiredPaid() public {}

    function test_VoidByPartyUnpaid() public {}

    function test_VoidByPartyPaid() public {}
}

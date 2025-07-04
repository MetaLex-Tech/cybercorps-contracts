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

import "forge-std/Test.sol";
import "../src/creds/lexchex.sol";
import "../src/libs/auth.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";

contract LexChexTest is Test {
    using ERC1967ProxyLib for address;

    LeXcheX public lexchex;
    LeXcheX public impl;
    BorgAuth public auth;

    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address owner = address(0x4);

    Accreditation testAccreditation;

    event LexChex_Issued(address indexed owner, uint256 indexed id, Accreditation acc);
    event LexChex_Voided(address indexed owner, uint256 indexed id, string reason);
    event LexChex_Burned(address indexed owner, uint256 indexed id);
    event LexChex_AccreditationSet(address indexed owner, uint256 indexed id, Accreditation acc);

    function setUp() public {
        // Setup roles - owner needs to be set in constructor
        auth = new BorgAuth(owner);
        
        vm.startPrank(owner);
        // Set admin role - owner can do this because they were set in constructor
        auth.updateRole(admin, auth.ADMIN_ROLE());
        vm.stopPrank();

        // Deploy implementation and proxy
        bytes32 salt = bytes32(0);
        impl = new LeXcheX();
        lexchex = LeXcheX(
            address(new ERC1967Proxy{salt: salt}(
                address(impl),
                abi.encodeWithSelector(LeXcheX.initialize.selector, address(auth))
            ))
        );
        
        testAccreditation = Accreditation({
            agreementId: bytes32(uint256(1)),
            registryAddress: address(0x5),
            investorName: "Test Entity",
            investorType: "LLC",
            investorJurisdiction: "Delaware",
            investorContact: "test@test.com",
            issuanceDate: block.timestamp,
            expiryDate: block.timestamp + 365 days,
            voided: "",
            signature: bytes("0x123..."),
            uuid: 1
        });
    }

    function test_RevertIf_initializeImplementation() public {
        LeXcheX impl = new LeXcheX();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        impl.initialize(address(auth));
    }

    // Test 2: Minting as admin
    function testMintAsAdmin() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit LexChex_Issued(admin, 0, testAccreditation);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        assertEq(tokenId, 0);
        assertEq(lexchex.ownerOf(tokenId), user1);
        vm.stopPrank();
        //print the tokenURI
        console.log(lexchex.tokenURI(tokenId));
    }

    // Test 3: Minting as non-admin should fail
    function test_RevertWhen_MintingAsNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, 98, user1));
        lexchex.mint(user1, testAccreditation);
        vm.stopPrank();
    }

    // Test 4: Test burning own token
    function testBurnOwnToken() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit LexChex_Burned(user1, tokenId);
        vm.startPrank(user1);
        lexchex.burn(tokenId);
        vm.stopPrank();

       // vm.expectRevert("ERC721: invalid token ID");
       //address owner = lexchex.ownerOf(tokenId);
       //console.log("owner", owner);
    }

    // Test 5: Test burning someone else's token should fail
    function test_RevertWhen_BurningOthersToken() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(LeXcheX.LexChex_OnlyOwnerCanBurn.selector));
        lexchex.burn(tokenId);
        vm.stopPrank();
    }

    // Test 6: Test voiding as owner
    function testVoidAsOwner() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectEmit(true, true, false, true);
        emit LexChex_Voided(owner, tokenId, "Regulatory non-compliance");
        lexchex.void(tokenId, "Regulatory non-compliance");
        vm.stopPrank();
    }

    // Test 7: Test voiding as non-owner should fail
    function test_RevertWhen_VoidingAsNonOwner() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        lexchex.void(tokenId, "Unauthorized void");
        vm.stopPrank();
    }

    // Test 8: Test token validity checks
    function testTokenValidity() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        
        // Should be valid initially
        assertTrue(lexchex.isValid(tokenId));

        // Should be invalid after voiding
        vm.stopPrank();
        vm.startPrank(owner);
        lexchex.void(tokenId, "Voided for testing");
       Accreditation memory a = lexchex.accreditations(tokenId);
       console.log("a: ", a.voided);
        console.log(lexchex.isValid(tokenId));
        assertFalse(lexchex.isValid(tokenId));
        vm.stopPrank();
    }

    // Test 9: Test token validity after expiry
    function testTokenValidityAfterExpiry() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        assertTrue(lexchex.isValid(tokenId));

        // Fast forward past expiry
        vm.warp(block.timestamp + 366 days);
        assertFalse(lexchex.isValid(tokenId));
        vm.stopPrank();
    }

    // Test 11: Test non-transferability (soulbound)
    function test_RevertWhen_TransferringToken() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(LeXcheX.LexChex_SoulBound.selector));
        lexchex.transferFrom(user1, user2, tokenId);
        vm.stopPrank();
    }

    // Test 12: Test burn authorization type
    function testBurnAuth() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        assertEq(uint256(lexchex.burnAuth(tokenId)), uint256(IERC5484.BurnAuth.OwnerOnly));
        vm.stopPrank();
    }

    // Test 13: Test multiple mints
    function testMultipleMints() public {
        vm.startPrank(admin);
        
        uint256 tokenId1 = lexchex.mint(user1, testAccreditation);
        uint256 tokenId2 = lexchex.mint(user2, testAccreditation);
        
        assertEq(tokenId1, 0);
        assertEq(tokenId2, 1);
        assertEq(lexchex.ownerOf(tokenId1), user1);
        assertEq(lexchex.ownerOf(tokenId2), user2);
        vm.stopPrank();
    }

    // Test 14: Test burning non-existent token
    function test_RevertWhen_BurningNonExistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 999));
        lexchex.burn(999);
    }

    // Test 16: Test validity of non-existent token
    function testValidityNonExistentToken() public {
        assertFalse(lexchex.isValid(999));
    }

    // Test 17: Test double initialization should fail
    function test_RevertWhen_InitializingTwice() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        lexchex.initialize(address(auth));
    }


    // Test 19: Test minting with expired date should still work
    function testMintWithExpiredDate() public {
        // Move timestamp a little forward to avoid arithmetic edge cases
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(admin);
        
        Accreditation memory expiredAcc = testAccreditation;
        expiredAcc.expiryDate = block.timestamp - 1 days;
        
        uint256 tokenId = lexchex.mint(user1, expiredAcc);

        assertFalse(lexchex.isValid(tokenId));
        assertEq(lexchex.accreditations(tokenId).expiryDate, expiredAcc.expiryDate);

        vm.stopPrank();
    }

    // Test 20: Test voiding already voided token
    function testVoidAlreadyVoided() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        vm.stopPrank();

        vm.startPrank(owner);
        lexchex.void(tokenId, "First void");
        lexchex.void(tokenId, "Second void");
        assertFalse(lexchex.isValid(tokenId));
        vm.stopPrank();
    }

    function testUpgradeLeXcheX() public {
        // Mint a token to change the existing states
        vm.prank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        assertEq(lexchex.totalSupply(), 1, "There should be just one NFT minted");
        assertEq(lexchex.ownerOf(tokenId), user1, "The token should be owned by user1");

        // Deploy new implementation
        address newImplementation = address(new LeXcheX());

        // Upgrade to new implementation without initialization data

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), admin));
        vm.prank(admin);
        lexchex.upgradeToAndCall(newImplementation, "");

        // Owner should be able to upgrade it
        vm.prank(owner);
        lexchex.upgradeToAndCall(newImplementation, "");
        assertEq(address(lexchex).getErc1967Implementation(vm), newImplementation);

        // Verify the existing states
        assertEq(lexchex.totalSupply(), 1, "Total supply should be the same after upgrade");
        assertEq(lexchex.ownerOf(tokenId), user1, "Token ownership should be the same after upgrade");
    }

    // Test 21: Mint 3, burn 2, then mint 2 more - print IDs
    function testMintBurnMintAgain() public {
        // Mint 3 NFTs
        vm.startPrank(admin);
        uint256 firstTokenId = lexchex.mint(user1, testAccreditation);
        console.log("First NFT minted with ID:", firstTokenId);
        
        uint256 secondTokenId = lexchex.mint(user2, testAccreditation);
        console.log("Second NFT minted with ID:", secondTokenId);
        
        uint256 thirdTokenId = lexchex.mint(user1, testAccreditation);
        console.log("Third NFT minted with ID:", thirdTokenId);
        vm.stopPrank();

        // Verify initial state
        assertEq(firstTokenId, 0, "First token ID should be 0");
        assertEq(secondTokenId, 1, "Second token ID should be 1");
        assertEq(thirdTokenId, 2, "Third token ID should be 2");
        assertEq(lexchex.totalSupply(), 3, "Total supply should be 3 after minting 3");

        // Burn 2 NFTs (first and third)
        vm.startPrank(user1);
        lexchex.burn(firstTokenId);
        console.log("First NFT burned with ID:", firstTokenId);
        
        lexchex.burn(thirdTokenId);
        console.log("Third NFT burned with ID:", thirdTokenId);
        vm.stopPrank();

        // Verify state after burning 2
        assertEq(lexchex.totalSupply(), 1, "Total supply should be 1 after burning 2");
        assertEq(lexchex.ownerOf(secondTokenId), user2, "Second token should still be owned by user2");

        // Mint 2 more NFTs
        vm.startPrank(admin);
        uint256 fourthTokenId = lexchex.mint(user2, testAccreditation);
        console.log("Fourth NFT minted with ID:", fourthTokenId);
        
        uint256 fifthTokenId = lexchex.mint(user1, testAccreditation);
        console.log("Fifth NFT minted with ID:", fifthTokenId);
        vm.stopPrank();

        // Verify final state
        assertEq(fourthTokenId, 3, "Fourth token ID should be 3");
        assertEq(fifthTokenId, 4, "Fifth token ID should be 4");
        assertEq(lexchex.totalSupply(), 3, "Total supply should be 3 at the end");
        
        // Verify ownership
        assertEq(lexchex.ownerOf(secondTokenId), user2, "Second token should be owned by user2");
        assertEq(lexchex.ownerOf(fourthTokenId), user2, "Fourth token should be owned by user2");
        assertEq(lexchex.ownerOf(fifthTokenId), user1, "Fifth token should be owned by user1");

        // Verify burned tokens are no longer accessible
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, firstTokenId));
        lexchex.ownerOf(firstTokenId);
        
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, thirdTokenId));
        lexchex.ownerOf(thirdTokenId);
    }

    function testSetAccreditation() public {
        // Mint a token first
        vm.prank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        assertEq(tokenId, 0);

        // Set new accreditation
        Accreditation memory newAccreditation = Accreditation({
            agreementId: bytes32(uint256(2)),
            registryAddress: address(0x5),
            investorName: "New Test Entity",
            investorType: "LLC",
            investorJurisdiction: "Delaware",
            investorContact: "new-test@test.com",
            issuanceDate: block.timestamp,
            expiryDate: block.timestamp + 365 days,
            voided: "",
            signature: bytes("0x123..."),
            uuid: 1
        });
        vm.expectEmit(true, true, true, true);
        emit LexChex_AccreditationSet(owner, tokenId, newAccreditation);
        vm.prank(owner);
        lexchex.setAccreditation(
            tokenId,
            newAccreditation
        );
        assertEq(lexchex.accreditations(tokenId).agreementId, bytes32(uint256(2)), "Should have new accreditation");
    }

    function test_RevertWhen_SetAccreditationNonAdmin() public {
        // Mint a token first
        vm.prank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        assertEq(tokenId, 0);

        // Non-admin should not be able to set new accreditation
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.ADMIN_ROLE(), user1));
        vm.prank(user1);
        lexchex.setAccreditation(
            tokenId,
            Accreditation({
                agreementId: bytes32(uint256(2)),
                registryAddress: address(0x5),
                investorName: "New Test Entity",
                investorType: "LLC",
                investorJurisdiction: "Delaware",
                investorContact: "new-test@test.com",
                issuanceDate: block.timestamp,
                expiryDate: block.timestamp + 365 days,
                voided: "",
                signature: bytes("0x123..."),
                uuid: 1
            })
        );
    }
}

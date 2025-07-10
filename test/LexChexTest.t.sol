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

    function testGetTokenIdsByOwner() public {
        assertEq(lexchex.getTokenIdsByOwner(user1), new uint256[](0));

        vm.prank(admin);
        lexchex.mint(user1, testAccreditation);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        assertEq(lexchex.getTokenIdsByOwner(user1), tokenIds);
    }

    function testHasValidLexCheX() public {
        assertFalse(lexchex.hasValidLexCheX(user1));

        vm.prank(admin);
        lexchex.mint(user1, testAccreditation);

        assertTrue(lexchex.hasValidLexCheX(user1));
    }

    function testGetAccreditationByOwner() public {
        vm.startPrank(admin);
        lexchex.mint(user1, testAccreditation);
        lexchex.mint(user1, testAccreditation); // Deliberately mint multiple tokens
        vm.stopPrank();

        // Should get you the first token ID
        assertEq(lexchex.getAccreditationByOwner(user1), 0, "Expected token ID");
    }

    function testTokenURI() public {
        vm.prank(admin);
        lexchex.mint(user1, testAccreditation);

        // echo -n '{"name": "U.S. Accredited Investor Certificate #0", "description": "This certificate represents verification of U.S. Accredited Investor status.","image": "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB4bWxuczp4aHRtbD0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94aHRtbCIgdmVyc2lvbj0iMS4xIiB3aWR0aD0iMTAwMCIgaGVpZ2h0PSI2NTAiPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiICBmaWxsPSIjMTkxYTE4Ii8+PHN2ZyB4PSI4ODAiIHk9IjU3MCIgd2lkdGg9IjYxIiBoZWlnaHQ9IjMwIiB2aWV3Qm94PSIwIDAgNjEgMzAiIGZpbGw9Im5vbmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PHBhdGggZD0iTTI5LjU0ODggMEMzMC41MTA3IDAgMzEuMjkxIDAuNzc5NzUzIDMxLjI5MSAxLjc0MTIxVjExLjk1N0MzMS4yOTEgMTIuNTQzIDMwLjk5NTcgMTMuMDkwMiAzMC41MDU5IDEzLjQxMjFMNi42OTYyOSAyOS4wNjA1QzYuNDEyMjEgMjkuMjQ3MiA2LjA3OTIxIDI5LjM0NjcgNS43MzkyNiAyOS4zNDY3SDEuNzQxMjFDMC43Nzk1MzYgMjkuMzQ2NSAwIDI4LjU2NjggMCAyNy42MDU1VjE5Ljk2NDhDOC4yNzI2MWUtMDUgMTkuMzc5OSAwLjI5MzgxNiAxOC44MzM5IDAuNzgyMjI3IDE4LjUxMTdMMjguNDE1IDAuMjg4MDg2QzI4LjY5OTYgMC4xMDA0MTIgMjkuMDMzMSAwIDI5LjM3NCAwSDI5LjU0ODhaTTU0Ljc4MzIgMC4wMDA5NzY1NjJDNTUuNzQ1IDAuMDAwOTc2NTYyIDU2LjUyNDMgMC43Nzk4NCA1Ni41MjQ0IDEuNzQxMjFWMTEuOTU3QzU2LjUyNDQgMTIuNTQzIDU2LjIzIDEzLjA5MDIgNTUuNzQwMiAxMy40MTIxTDMxLjkzMDcgMjkuMDYwNUMzMS42NDY1IDI5LjI0NzMgMzEuMzEzNyAyOS4zNDY3IDMwLjk3MzYgMjkuMzQ2N0gyNi45NzU2QzI2LjAxMzkgMjkuMzQ2NiAyNS4yMzQ0IDI4LjU2NjkgMjUuMjM0NCAyNy42MDU1VjE5Ljk2NDhDMjUuMjM0NSAxOS4zOCAyNS41MjgyIDE4LjgzMzggMjYuMDE2NiAxOC41MTE3TDUzLjY0OTQgMC4yODgwODZDNTMuOTM0IDAuMTAwNDg4IDU0LjI2NzUgMC4wMDA5NzY1NjIgNTQuNjA4NCAwLjAwMDk3NjU2Mkg1NC43ODMyWk01OC45NTIxIDE1LjU0QzU5LjgyNSAxNC45NTMyIDYwLjk5OTcgMTUuNTc4MyA2MSAxNi42Mjk5VjI3Ljc5MkM2MC45OTk5IDI4LjY1MDYgNjAuMzAzMyAyOS4zNDY3IDU5LjQ0NDMgMjkuMzQ2N0g0OC41NDU5QzQ3LjY4NyAyOS4zNDY2IDQ2Ljk5MDMgMjguNjUwNSA0Ni45OTAyIDI3Ljc5MlYyNC4zNTk0QzQ2Ljk5MDIgMjMuODQyIDQ3LjI0ODQgMjMuMzU4MiA0Ny42Nzc3IDIzLjA2OTNMNTguOTUyMSAxNS41NFoiIGZpbGw9IiNEQUZGMDAiLz48L3N2Zz48cmVjdCB4PSIwIiB5PSI4MyIgd2lkdGg9IjEwMDBweCIgaGVpZ2h0PSI1MHB4IiBmaWxsPSJ1cmwoI2xpbkdyYWQpIj48L3JlY3Q+PHRleHQgeD0iMjEyIiB5PSIxMjYiIGZvbnQtZmFtaWx5PSJHZW9yZ2lhICIgZm9udC1zaXplPSI1MyIgZmlsbD0idXJsKCN0ZXh0R3JhZCkiPlUuUy4gQWNjcmVkaXRlZCBJbnZlc3RvcjwvdGV4dD48dGV4dCB4PSIyNDkiIHk9IjIyNiIgZm9udC1mYW1pbHk9Ikdlb3JnaWEiIGZvbnQtc2l6ZT0iMjUiIGZpbGw9IiNmMmYyZjIiPlRIRSBIT0xERVIgT0YgVEhJUyBDRVJUSUZJQ0FURSBJUyBBPC90ZXh0Pjx0ZXh0IHg9IjMxOCIgeT0iMjY2IiBmb250LWZhbWlseT0iR2VvcmdpYSIgZm9udC1zaXplPSIyNSIgZmlsbD0iI2YyZjJmMiI+VS5TLiBBQ0NSRURJVEVEIElOVkVTVE9SIDwvdGV4dD48ZGVmcz48cmFkaWFsR3JhZGllbnQgaWQ9ImdyYWQxIiBjeD0iNTAlIiBjeT0iNTAlIiByPSI1MCUiIGZ4PSI1MCUiIGZ5PSI1MCUiPjxzdG9wIG9mZnNldD0iMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiNkYWZmMDA7IHN0b3Atb3BhY2l0eTouMDciIC8+PHN0b3Agb2Zmc2V0PSIxMDAlIiBzdHlsZT0ic3RvcC1jb2xvcjojMTkxYTE4OyBzdG9wLW9wYWNpdHk6LjA3IiAvPjwvcmFkaWFsR3JhZGllbnQ+PGxpbmVhckdyYWRpZW50IGlkPSJsaW5HcmFkIj48c3RvcCBvZmZzZXQ9IjAlIiBzdHlsZT0ic3RvcC1jb2xvcjojZGFmZjAwOyBzdG9wLW9wYWNpdHk6LjQiIC8+PHN0b3Agb2Zmc2V0PSIyMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiNkYWZmMDA7IHN0b3Atb3BhY2l0eTowIiAvPjxzdG9wIG9mZnNldD0iODAlIiBzdHlsZT0ic3RvcC1jb2xvcjojZGFmZjAwOyBzdG9wLW9wYWNpdHk6MCIgLz48c3RvcCBvZmZzZXQ9IjEwMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiNkYWZmMDA7IHN0b3Atb3BhY2l0eTouNCIgLz48L2xpbmVhckdyYWRpZW50PjxsaW5lYXJHcmFkaWVudCBpZD0idGV4dEdyYWQiIHgxPSIwJSIgeTE9IjAlIiB4Mj0iMCUiIHkyPSIxMDAlIj48c3RvcCBvZmZzZXQ9IjAlIiBzdHlsZT0ic3RvcC1jb2xvcjojZGFmZjAwOyBzdG9wLW9wYWNpdHk6MSIgLz48c3RvcCBvZmZzZXQ9IjEwMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiNGMkY4Q0I7IHN0b3Atb3BhY2l0eToxIiAvPjwvbGluZWFyR3JhZGllbnQ+PC9kZWZzPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InVybCgjZ3JhZDEpIiAvPjx0ZXh0IHg9IjE1MCIgeT0iMzYwIiBmb250LWZhbWlseT0iR2VvcmdpYSIgZm9udC1zaXplPSIzMCIgZmlsbD0iI2YyZjJmMiIgb3BhY2l0eT0iLjYiID5DRVJUSUZJRUQgQlk8L3RleHQ+PHRleHQgeD0iMzg1IiB5PSIzNTUiIGZvbnQtZmFtaWx5PSJHZW9yZ2lhIiBmb250LXNpemU9IjMwIiBmaWxsPSJ1cmwoI3RleHRHcmFkKSIgPkdhYnJpZWwgU2hhcGlybywgRXNxLiwgb2YgTWV0YUxlWDwvdGV4dD48cmVjdCB4PSIzODAiIHk9IjM2MyIgd2lkdGg9IjQ3MHB4IiBoZWlnaHQ9IjVweCIgZmlsbD0iI2YyZjJmMiIgb3BhY2l0eT0iLjI0Ij48L3JlY3Q+PHRleHQgeD0iMTUwIiB5PSI0NTAiIGZvbnQtZmFtaWx5PSJHZW9yZ2lhIiBmb250LXNpemU9IjMwIiBmaWxsPSIjZjJmMmYyIiBvcGFjaXR5PSIuNiI+R09PRCBVTlRJTDwvdGV4dD48dGV4dCB4PSI0OTUiIHk9IjQ0MCIgZm9udC1mYW1pbHk9Ikdlb3JnaWEiIGZvbnQtc2l6ZT0iMzAiIGZpbGw9InVybCgjdGV4dEdyYWQpIiA+MTIvMjUvMTk3MDwvdGV4dD48cmVjdCB4PSIzODAiIHk9IjQ1MyIgd2lkdGg9IjQ3MHB4IiBoZWlnaHQ9IjVweCIgZmlsbD0iI2YyZjJmMiIgb3BhY2l0eT0iLjI0Ij48L3JlY3Q+PHRleHQgeD0iMzI1IiB5PSI1NzAiIGZvbnQtZmFtaWx5PSJHZW9yZ2lhIiBmb250LXNpemU9IjE3IiBmaWxsPSIjZjJmMmYyIiBvcGFjaXR5PSIuNiI+Tm9uLXRyYW5zZmVyYWJsZS4gU291bC1ib3VuZC4gVmVyaWZpZWQgb24tY2hhaW4uPC90ZXh0Pjx0ZXh0IHg9IjIxMCIgeT0iNjAwIiBmb250LWZhbWlseT0iR2VvcmdpYSIgZm9udC1zaXplPSIxNSIgZmlsbD0iI2YyZjJmMiIgb3BhY2l0eT0iLjI0Ij4weDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDE8L3RleHQ+PC9zdmc+", "attributes": [{"trait_type": "Name", "value": "Test Entity"},{"trait_type": "Entity Type", "value": "LLC"},{"trait_type": "Jurisdiction", "value": "Delaware"},{"trait_type": "Status", "value": "Valid"}]}' | b64encode
        assertEq(lexchex.tokenURI(0), "data:application/json;base64,eyJuYW1lIjogIlUuUy4gQWNjcmVkaXRlZCBJbnZlc3RvciBDZXJ0aWZpY2F0ZSAjMCIsICJkZXNjcmlwdGlvbiI6ICJUaGlzIGNlcnRpZmljYXRlIHJlcHJlc2VudHMgdmVyaWZpY2F0aW9uIG9mIFUuUy4gQWNjcmVkaXRlZCBJbnZlc3RvciBzdGF0dXMuIiwiaW1hZ2UiOiAiZGF0YTppbWFnZS9zdmcreG1sO2Jhc2U2NCxQSE4yWnlCNGJXeHVjejBpYUhSMGNEb3ZMM2QzZHk1M015NXZjbWN2TWpBd01DOXpkbWNpSUhodGJHNXpPbmhzYVc1clBTSm9kSFJ3T2k4dmQzZDNMbmN6TG05eVp5OHhPVGs1TDNoc2FXNXJJaUI0Yld4dWN6cDRhSFJ0YkQwaWFIUjBjRG92TDNkM2R5NTNNeTV2Y21jdk1UazVPUzk0YUhSdGJDSWdkbVZ5YzJsdmJqMGlNUzR4SWlCM2FXUjBhRDBpTVRBd01DSWdhR1ZwWjJoMFBTSTJOVEFpUGp4eVpXTjBJSGRwWkhSb1BTSXhNREFsSWlCb1pXbG5hSFE5SWpFd01DVWlJQ0JtYVd4c1BTSWpNVGt4WVRFNElpOCtQSE4yWnlCNFBTSTRPREFpSUhrOUlqVTNNQ0lnZDJsa2RHZzlJall4SWlCb1pXbG5hSFE5SWpNd0lpQjJhV1YzUW05NFBTSXdJREFnTmpFZ016QWlJR1pwYkd3OUltNXZibVVpSUhodGJHNXpQU0pvZEhSd09pOHZkM2QzTG5jekxtOXlaeTh5TURBd0wzTjJaeUkrUEhCaGRHZ2daRDBpVFRJNUxqVTBPRGdnTUVNek1DNDFNVEEzSURBZ016RXVNamt4SURBdU56YzVOelV6SURNeExqSTVNU0F4TGpjME1USXhWakV4TGprMU4wTXpNUzR5T1RFZ01USXVOVFF6SURNd0xqazVOVGNnTVRNdU1Ea3dNaUF6TUM0MU1EVTVJREV6TGpReE1qRk1OaTQyT1RZeU9TQXlPUzR3TmpBMVF6WXVOREV5TWpFZ01qa3VNalEzTWlBMkxqQTNPVEl4SURJNUxqTTBOamNnTlM0M016a3lOaUF5T1M0ek5EWTNTREV1TnpReE1qRkRNQzQzTnprMU16WWdNamt1TXpRMk5TQXdJREk0TGpVMk5qZ2dNQ0F5Tnk0Mk1EVTFWakU1TGprMk5EaERPQzR5TnpJMk1XVXRNRFVnTVRrdU16YzVPU0F3TGpJNU16Z3hOaUF4T0M0NE16TTVJREF1TnpneU1qSTNJREU0TGpVeE1UZE1Namd1TkRFMUlEQXVNamc0TURnMlF6STRMalk1T1RZZ01DNHhNREEwTVRJZ01qa3VNRE16TVNBd0lESTVMak0zTkNBd1NESTVMalUwT0RoYVRUVTBMamM0TXpJZ01DNHdNREE1TnpZMU5qSkROVFV1TnpRMUlEQXVNREF3T1RjMk5UWXlJRFUyTGpVeU5ETWdNQzQzTnprNE5DQTFOaTQxTWpRMElERXVOelF4TWpGV01URXVPVFUzUXpVMkxqVXlORFFnTVRJdU5UUXpJRFUyTGpJeklERXpMakE1TURJZ05UVXVOelF3TWlBeE15NDBNVEl4VERNeExqa3pNRGNnTWprdU1EWXdOVU16TVM0Mk5EWTFJREk1TGpJME56TWdNekV1TXpFek55QXlPUzR6TkRZM0lETXdMamszTXpZZ01qa3VNelEyTjBneU5pNDVOelUyUXpJMkxqQXhNemtnTWprdU16UTJOaUF5TlM0eU16UTBJREk0TGpVMk5qa2dNalV1TWpNME5DQXlOeTQyTURVMVZqRTVMamsyTkRoRE1qVXVNak0wTlNBeE9TNHpPQ0F5TlM0MU1qZ3lJREU0TGpnek16Z2dNall1TURFMk5pQXhPQzQxTVRFM1REVXpMalkwT1RRZ01DNHlPRGd3T0RaRE5UTXVPVE0wSURBdU1UQXdORGc0SURVMExqSTJOelVnTUM0d01EQTVOelkxTmpJZ05UUXVOakE0TkNBd0xqQXdNRGszTmpVMk1rZzFOQzQzT0RNeVdrMDFPQzQ1TlRJeElERTFMalUwUXpVNUxqZ3lOU0F4TkM0NU5UTXlJRFl3TGprNU9UY2dNVFV1TlRjNE15QTJNU0F4Tmk0Mk1qazVWakkzTGpjNU1rTTJNQzQ1T1RrNUlESTRMalkxTURZZ05qQXVNekF6TXlBeU9TNHpORFkzSURVNUxqUTBORE1nTWprdU16UTJOMGcwT0M0MU5EVTVRelEzTGpZNE55QXlPUzR6TkRZMklEUTJMams1TURNZ01qZ3VOalV3TlNBME5pNDVPVEF5SURJM0xqYzVNbFl5TkM0ek5UazBRelEyTGprNU1ESWdNak11T0RReUlEUTNMakkwT0RRZ01qTXVNelU0TWlBME55NDJOemMzSURJekxqQTJPVE5NTlRndU9UVXlNU0F4TlM0MU5Gb2lJR1pwYkd3OUlpTkVRVVpHTURBaUx6NDhMM04yWno0OGNtVmpkQ0I0UFNJd0lpQjVQU0k0TXlJZ2QybGtkR2c5SWpFd01EQndlQ0lnYUdWcFoyaDBQU0kxTUhCNElpQm1hV3hzUFNKMWNtd29JMnhwYmtkeVlXUXBJajQ4TDNKbFkzUStQSFJsZUhRZ2VEMGlNakV5SWlCNVBTSXhNallpSUdadmJuUXRabUZ0YVd4NVBTSkhaVzl5WjJsaElDSWdabTl1ZEMxemFYcGxQU0kxTXlJZ1ptbHNiRDBpZFhKc0tDTjBaWGgwUjNKaFpDa2lQbFV1VXk0Z1FXTmpjbVZrYVhSbFpDQkpiblpsYzNSdmNqd3ZkR1Y0ZEQ0OGRHVjRkQ0I0UFNJeU5Ea2lJSGs5SWpJeU5pSWdabTl1ZEMxbVlXMXBiSGs5SWtkbGIzSm5hV0VpSUdadmJuUXRjMmw2WlQwaU1qVWlJR1pwYkd3OUlpTm1NbVl5WmpJaVBsUklSU0JJVDB4RVJWSWdUMFlnVkVoSlV5QkRSVkpVU1VaSlEwRlVSU0JKVXlCQlBDOTBaWGgwUGp4MFpYaDBJSGc5SWpNeE9DSWdlVDBpTWpZMklpQm1iMjUwTFdaaGJXbHNlVDBpUjJWdmNtZHBZU0lnWm05dWRDMXphWHBsUFNJeU5TSWdabWxzYkQwaUkyWXlaakptTWlJK1ZTNVRMaUJCUTBOU1JVUkpWRVZFSUVsT1ZrVlRWRTlTSUR3dmRHVjRkRDQ4WkdWbWN6NDhjbUZrYVdGc1IzSmhaR2xsYm5RZ2FXUTlJbWR5WVdReElpQmplRDBpTlRBbElpQmplVDBpTlRBbElpQnlQU0kxTUNVaUlHWjRQU0kxTUNVaUlHWjVQU0kxTUNVaVBqeHpkRzl3SUc5bVpuTmxkRDBpTUNVaUlITjBlV3hsUFNKemRHOXdMV052Ykc5eU9pTmtZV1ptTURBN0lITjBiM0F0YjNCaFkybDBlVG91TURjaUlDOCtQSE4wYjNBZ2IyWm1jMlYwUFNJeE1EQWxJaUJ6ZEhsc1pUMGljM1J2Y0MxamIyeHZjam9qTVRreFlURTRPeUJ6ZEc5d0xXOXdZV05wZEhrNkxqQTNJaUF2UGp3dmNtRmthV0ZzUjNKaFpHbGxiblErUEd4cGJtVmhja2R5WVdScFpXNTBJR2xrUFNKc2FXNUhjbUZrSWo0OGMzUnZjQ0J2Wm1aelpYUTlJakFsSWlCemRIbHNaVDBpYzNSdmNDMWpiMnh2Y2pvalpHRm1aakF3T3lCemRHOXdMVzl3WVdOcGRIazZMalFpSUM4K1BITjBiM0FnYjJabWMyVjBQU0l5TUNVaUlITjBlV3hsUFNKemRHOXdMV052Ykc5eU9pTmtZV1ptTURBN0lITjBiM0F0YjNCaFkybDBlVG93SWlBdlBqeHpkRzl3SUc5bVpuTmxkRDBpT0RBbElpQnpkSGxzWlQwaWMzUnZjQzFqYjJ4dmNqb2paR0ZtWmpBd095QnpkRzl3TFc5d1lXTnBkSGs2TUNJZ0x6NDhjM1J2Y0NCdlptWnpaWFE5SWpFd01DVWlJSE4wZVd4bFBTSnpkRzl3TFdOdmJHOXlPaU5rWVdabU1EQTdJSE4wYjNBdGIzQmhZMmwwZVRvdU5DSWdMejQ4TDJ4cGJtVmhja2R5WVdScFpXNTBQanhzYVc1bFlYSkhjbUZrYVdWdWRDQnBaRDBpZEdWNGRFZHlZV1FpSUhneFBTSXdKU0lnZVRFOUlqQWxJaUI0TWowaU1DVWlJSGt5UFNJeE1EQWxJajQ4YzNSdmNDQnZabVp6WlhROUlqQWxJaUJ6ZEhsc1pUMGljM1J2Y0MxamIyeHZjam9qWkdGbVpqQXdPeUJ6ZEc5d0xXOXdZV05wZEhrNk1TSWdMejQ4YzNSdmNDQnZabVp6WlhROUlqRXdNQ1VpSUhOMGVXeGxQU0p6ZEc5d0xXTnZiRzl5T2lOR01rWTRRMEk3SUhOMGIzQXRiM0JoWTJsMGVUb3hJaUF2UGp3dmJHbHVaV0Z5UjNKaFpHbGxiblErUEM5a1pXWnpQanh5WldOMElIZHBaSFJvUFNJeE1EQWxJaUJvWldsbmFIUTlJakV3TUNVaUlHWnBiR3c5SW5WeWJDZ2paM0poWkRFcElpQXZQangwWlhoMElIZzlJakUxTUNJZ2VUMGlNell3SWlCbWIyNTBMV1poYldsc2VUMGlSMlZ2Y21kcFlTSWdabTl1ZEMxemFYcGxQU0l6TUNJZ1ptbHNiRDBpSTJZeVpqSm1NaUlnYjNCaFkybDBlVDBpTGpZaUlENURSVkpVU1VaSlJVUWdRbGs4TDNSbGVIUStQSFJsZUhRZ2VEMGlNemcxSWlCNVBTSXpOVFVpSUdadmJuUXRabUZ0YVd4NVBTSkhaVzl5WjJsaElpQm1iMjUwTFhOcGVtVTlJak13SWlCbWFXeHNQU0oxY213b0kzUmxlSFJIY21Ga0tTSWdQa2RoWW5KcFpXd2dVMmhoY0dseWJ5d2dSWE54TGl3Z2IyWWdUV1YwWVV4bFdEd3ZkR1Y0ZEQ0OGNtVmpkQ0I0UFNJek9EQWlJSGs5SWpNMk15SWdkMmxrZEdnOUlqUTNNSEI0SWlCb1pXbG5hSFE5SWpWd2VDSWdabWxzYkQwaUkyWXlaakptTWlJZ2IzQmhZMmwwZVQwaUxqSTBJajQ4TDNKbFkzUStQSFJsZUhRZ2VEMGlNVFV3SWlCNVBTSTBOVEFpSUdadmJuUXRabUZ0YVd4NVBTSkhaVzl5WjJsaElpQm1iMjUwTFhOcGVtVTlJak13SWlCbWFXeHNQU0lqWmpKbU1tWXlJaUJ2Y0dGamFYUjVQU0l1TmlJK1IwOVBSQ0JWVGxSSlREd3ZkR1Y0ZEQ0OGRHVjRkQ0I0UFNJME9UVWlJSGs5SWpRME1DSWdabTl1ZEMxbVlXMXBiSGs5SWtkbGIzSm5hV0VpSUdadmJuUXRjMmw2WlQwaU16QWlJR1pwYkd3OUluVnliQ2dqZEdWNGRFZHlZV1FwSWlBK01USXZNalV2TVRrM01Ed3ZkR1Y0ZEQ0OGNtVmpkQ0I0UFNJek9EQWlJSGs5SWpRMU15SWdkMmxrZEdnOUlqUTNNSEI0SWlCb1pXbG5hSFE5SWpWd2VDSWdabWxzYkQwaUkyWXlaakptTWlJZ2IzQmhZMmwwZVQwaUxqSTBJajQ4TDNKbFkzUStQSFJsZUhRZ2VEMGlNekkxSWlCNVBTSTFOekFpSUdadmJuUXRabUZ0YVd4NVBTSkhaVzl5WjJsaElpQm1iMjUwTFhOcGVtVTlJakUzSWlCbWFXeHNQU0lqWmpKbU1tWXlJaUJ2Y0dGamFYUjVQU0l1TmlJK1RtOXVMWFJ5WVc1elptVnlZV0pzWlM0Z1UyOTFiQzFpYjNWdVpDNGdWbVZ5YVdacFpXUWdiMjR0WTJoaGFXNHVQQzkwWlhoMFBqeDBaWGgwSUhnOUlqSXhNQ0lnZVQwaU5qQXdJaUJtYjI1MExXWmhiV2xzZVQwaVIyVnZjbWRwWVNJZ1ptOXVkQzF6YVhwbFBTSXhOU0lnWm1sc2JEMGlJMll5WmpKbU1pSWdiM0JoWTJsMGVUMGlMakkwSWo0d2VEQXdNREF3TURBd01EQXdNREF3TURBd01EQXdNREF3TURBd01EQXdNREF3TURBd01EQXdNREF3TURBd01EQXdNREF3TURBd01EQXdNREF3TURBd01ERThMM1JsZUhRK1BDOXpkbWMrIiwgImF0dHJpYnV0ZXMiOiBbeyJ0cmFpdF90eXBlIjogIk5hbWUiLCAidmFsdWUiOiAiVGVzdCBFbnRpdHkifSx7InRyYWl0X3R5cGUiOiAiRW50aXR5IFR5cGUiLCAidmFsdWUiOiAiTExDIn0seyJ0cmFpdF90eXBlIjogIkp1cmlzZGljdGlvbiIsICJ2YWx1ZSI6ICJEZWxhd2FyZSJ9LHsidHJhaXRfdHlwZSI6ICJTdGF0dXMiLCAidmFsdWUiOiAiVmFsaWQifV19");
    }
}

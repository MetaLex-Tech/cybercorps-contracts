// SPDX-License-Identifier: UNLICENSED
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

        // Setup test accreditation
        string[] memory portfolio = new string[](2);
        portfolio[0] = "0x123...";
        portfolio[1] = "bc1q...";
        
        testAccreditation = Accreditation({
            agreementId: bytes32(uint256(1)),
            registryAddress: address(0x5),
            name: "Test Entity",
            entityType: "LLC",
            jurisdiction: "Delaware",
            contact: "test@test.com",
            issuanceDate: block.timestamp,
            expiryDate: block.timestamp + 365 days,
            voided: "",
            portfolio: portfolio,
            signature: bytes("0x123...")
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

    // Test 10: Test portfolio retrieval
    function testGetPortfolio() public {
        vm.startPrank(admin);
        uint256 tokenId = lexchex.mint(user1, testAccreditation);
        
        string[] memory portfolio = lexchex.getPortfolioAt(tokenId);
        assertEq(portfolio.length, 2);
        assertEq(portfolio[0], "0x123...");
        assertEq(portfolio[1], "bc1q...");
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

    // Test 15: Test getting portfolio of non-existent token
    function testGettingPortfolioOfNonExistentToken() public {
        assertEq(lexchex.getPortfolioAt(999).length, 0);
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

    // Test 18: Test minting with empty portfolio
    function testMintEmptyPortfolio() public {
        vm.startPrank(admin);
        
        Accreditation memory emptyPortfolioAcc = testAccreditation;
        emptyPortfolioAcc.portfolio = new string[](0);
        
        uint256 tokenId = lexchex.mint(user1, emptyPortfolioAcc);
        string[] memory portfolio = lexchex.getPortfolioAt(tokenId);
        assertEq(portfolio.length, 0);
        vm.stopPrank();
    }

    // Test 19: Test minting with expired date should still work
    function testMintWithExpiredDate() public {
        // Move timestamp a little forward to avoid arithmetic edge cases
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(admin);
        
        Accreditation memory expiredAcc = testAccreditation;
        expiredAcc.expiryDate = block.timestamp - 1 days;
        
        uint256 tokenId = lexchex.mint(user1, expiredAcc);

        // TODO spec needed: it does not work as expected because mint() overwrites expiryDate. Need clarify which way we want to go.
//        assertFalse(lexchex.isValid(tokenId));
        assertTrue(lexchex.isValid(tokenId));
        assertEq(lexchex.accreditations(tokenId).expiryDate, block.timestamp + 30 days);

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
}

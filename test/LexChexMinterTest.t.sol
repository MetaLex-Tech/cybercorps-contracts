// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "./libs/CyberAgreementUtils.sol";
import {LeXcheXUtils} from "./libs/LeXcheXUtils.sol";
import {ERC1967ProxyLib} from "./libs/ERC1967ProxyLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

    function testRequestMint() public {
        uint256 salt = uint256(keccak256("testRequestMint"));

        // Prepare funds for agent
        deal(address(paymentToken), agent, 10e6, true);
        vm.prank(agent);
        paymentToken.approve(address(lexchexMinter), 10e6);

        // TODO Use more realistic values
        bytes32 templateId = bytes32(uint256(1));
        string memory legalContractUri = "ipfs.io/ipfs/[cid]";
        string[] memory globalFields = new string[](1);
        globalFields[0] = "Global Field 1";
        string[] memory partyFields = new string[](1);
        partyFields[0] = "Party Field 1";

        vm.prank(owner);
        registry.createTemplate(
            templateId,
            "Test Template",
            legalContractUri,
            globalFields,
            partyFields
        );

        string[] memory globalValues = new string[](1);
        globalValues[0] = "Global Value 1";

        address[] memory parties = new address[](1);
        parties[0] = address(user1);

        string[][] memory partyValues = new string[][](1);
        partyValues[0] = new string[](1);
        partyValues[0][0] = "Party Value 1";

        bytes32 contractId = keccak256(
            abi.encode(
                templateId,
                salt,
                globalValues,
                parties
            )
        );

        bytes memory agreementSignature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            legalContractUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues[0],
            user1PrivateKey
        );

        string[] memory portfolio = new string[](2);
        portfolio[0] = "0x123...";
        portfolio[1] = "bc1q...";
        LeXcheXMinter.MintRequest memory request = LeXcheXMinter.MintRequest({
            owner: user1,
            name: "Test Entity",
            entityType: "LLC",
            jurisdiction: "Delaware",
            contact: "test@test.com",
            portfolio: portfolio,
            mintPrice: 10e6,
            expiry: block.timestamp + 1 days
        });

        bytes memory authoritySignature = LeXcheXUtils.signAuthorizationTypedData(
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
        vm.expectEmit(true, true, true, true);
        emit LeXcheXMinter.MintRequested(user1, 10e6, contractId);
        vm.expectEmit(true, true, true, true);
        emit LeXcheXMinter.MintCompleted(user1, 0, contractId);
        vm.prank(agent);
        lexchexMinter.requestMint(
            request,
            templateId,
            salt,
            globalValues,
            parties,
            partyValues,
            agreementSignature,
            authoritySignature
        );

        assertEq(lexchex.balanceOf(user1), 1);
        assertEq(lexchex.ownerOf(0), user1);
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

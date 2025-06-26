// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {LeXcheXMinter} from "../src/creds/lexchexMinter.sol";
import {LeXcheX} from "../src/creds/lexchex.sol";
import {Test, console} from "forge-std/Test.sol";

contract PaymentToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Payment Token", "TestUSDC") {
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }
}

contract LexChexMinterTest is Test {
    uint256 testPrivateKey = 1337;
    address testAddress = vm.addr(testPrivateKey);

    address deployer = address(1);
    address user1 = address(2);
    address user2 = address(3);
    address treasury = address(4);

    ERC20 paymentToken = new PaymentToken(100e6);

    BorgAuth auth;
    CyberAgreementRegistry registry;
    LeXcheX public lexchex;
    LeXcheXMinter public lexchexMinter;

    function setUp() public {
        bytes32 salt = bytes32(keccak256("LexChexMinterTest"));

        vm.startPrank(deployer);

        auth = new BorgAuth{salt: salt}(deployer);

        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(CyberAgreementRegistry.initialize.selector, address(auth))
        )));

        lexchex = LeXcheX(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheX{salt: salt}()),
            abi.encodeWithSelector(LeXcheX.initialize.selector, address(auth))
        )));

        lexchexMinter = LeXcheXMinter(address(new ERC1967Proxy{salt: salt}(
            address(new LeXcheXMinter{salt: salt}()),
            abi.encodeWithSelector(
                LeXcheXMinter.initialize.selector,
                address(auth),
                address(lexchex),
                address(registry),
                address(paymentToken),
                treasury
            )
        )));

        vm.stopPrank();
    }

    function testMetadata() public {
        assertEq(lexchexMinter.auth(), address(auth), "Unexpected auth");
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
            "AuthorityData(address owner,string name,string entityType,string jurisdiction,uint256 mintPrice,uint256 expiry)"
        ), "Unexpected AUTHORITY_TYPEHASH");
    }

//    function testRequestMint() public {
//        // TODO Use more realistic values
//        bytes32 templateId = bytes32(uint256(1));
//
//        string[] memory globalValues = new string[](1);
//        globalValues[0] = "Global Value 1";
//
//        address[] memory parties = new address[](2);
//        parties[0] = address(testAddress);
//        parties[1] = address(0);
//
//        uint256 _paymentAmount = 1000000000000000000;
//
//        string[][] memory partyValues = new string[][](1);
//        partyValues[0] = new string[](1);
//        partyValues[0][0] = "Party Value 1";
//
//        bytes32 contractId = keccak256(
//            abi.encode(
//                templateId,
//                block.timestamp,
//                globalValues,
//                parties
//            )
//        );
//
//        string[] memory globalFields = new string[](1);
//        globalFields[0] = "Global Field 1";
//        string[] memory partyFields = new string[](1);
//        partyFields[0] = "Party Field 1";
//
//        bytes memory signature = _signAgreementTypedData(
//            registry.DOMAIN_SEPARATOR(),
//            registry.SIGNATUREDATA_TYPEHASH(),
//            contractId,
//            "ipfs.io/ipfs/[cid]",
//            globalFields,
//            partyFields,
//            globalValues,
//            partyValues[0],
//            testPrivateKey
//        );
//
//        MintRequest memory request = MintRequest({
//
//        });
//        lexchexMinter.requestMint(
//            request,
//            templateId,
//            salt,
//            globalValues,
//            parties,
//            partyValues,
//
//        );
//    }

    function testSetLexchex() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), user1));
        vm.prank(user1);
        lexchexMinter.setLexchex(address(0x1));

        // Owner should be allowed
        vm.prank(deployer);
        lexchexMinter.setLexchex(address(0x1));
        assertEq(lexchexMinter.lexchex(), address(0x1), "lexchex should've been updated");
    }

    function testSetDealRegistry() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), user1));
        vm.prank(user1);
        lexchexMinter.setDealRegistry(address(0x1));

        // Owner should be allowed
        vm.prank(deployer);
        lexchexMinter.setDealRegistry(address(0x1));
        assertEq(lexchexMinter.dealRegistry(), address(0x1), "dealRegistry should've been updated");
    }

    function testSetPaymentToken() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), user1));
        vm.prank(user1);
        lexchexMinter.setPaymentToken(address(0x1));

        // Owner should be allowed
        vm.prank(deployer);
        lexchexMinter.setPaymentToken(address(0x1));
        assertEq(lexchexMinter.paymentToken(), address(0x1), "paymentToken should've been updated");
    }

    function testSetTreasury() public {
        // Non-owner should not be allowed
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), user1));
        vm.prank(user1);
        lexchexMinter.setTreasury(address(0x1));

        // Owner should be allowed
        vm.prank(deployer);
        lexchexMinter.setTreasury(address(0x1));
        assertEq(lexchexMinter.treasury(), address(0x1), "treasury should've been updated");
    }

    // TODO test upgradeability
}
